/*
 * Copyright (c) 2024 The ZMK Contributors
 *
 * SPDX-License-Identifier: MIT
 */

#include <zephyr/kernel.h>
#include <zephyr/bluetooth/services/bas.h>

#include <zephyr/logging/log.h>
LOG_MODULE_DECLARE(zmk, CONFIG_ZMK_LOG_LEVEL);

#include "battery_status.h"

#include <zmk/battery.h>
#include <zmk/ble.h>
#include <zmk/display.h>
#include <zmk/event_manager.h>
#include <zmk/events/battery_state_changed.h>
#include <zmk/events/layer_state_changed.h>
#include <zmk/events/usb_conn_state_changed.h>
#include <zmk/keymap.h>
#include <zmk/usb.h>

#if IS_ENABLED(CONFIG_ZMK_DONGLE_DISPLAY_DONGLE_BATTERY)
    #define SOURCE_OFFSET 1
#else
    #define SOURCE_OFFSET 0
#endif

#define BATTERY_SLOT_COUNT (ZMK_SPLIT_BLE_PERIPHERAL_COUNT + SOURCE_OFFSET)
#define TERGO_ADJUST_LAYER_ID 4

/* O display OLED usa inversion-on: white = fundo apagado, black = pixel aceso */
#define OLED_BG lv_color_white()
#define OLED_FG lv_color_black()

#define BATT_W 21
#define BATT_H 9
#define BATT_ROW_STEP 11
#define BATT_RIGHT_MARGIN 1
#define BATT_CONTAINER_W 68
#define BATT_HYSTERESIS_PCT 3

static sys_slist_t widgets = SYS_SLIST_STATIC_INIT(&widgets);

struct battery_state {
    uint8_t source;
    uint8_t level;
    bool usb_present;
    bool valid;
};

struct battery_layer_state {
    bool show_pct;
};

struct cached_battery_slot {
    uint8_t raw_level;
    uint8_t calibrated_level;
    int8_t bars;
    bool usb_present;
};

struct lipo_curve_point {
    int16_t mv;
    uint8_t pct;
};

/* Curva aproximada de descarga de LiPo 3.7V sob baixa corrente (teclado BLE) */
static const struct lipo_curve_point lipo_curve[] = {
    {4200, 100},
    {4120,  95},
    {4050,  90},
    {3960,  80},
    {3880,  70},
    {3830,  60},
    {3790,  50},
    {3760,  40},
    {3730,  30},
    {3690,  20},
    {3630,  10},
    {3550,   5},
    {3450,   1},
};

static lv_color_t battery_image_buffer[BATTERY_SLOT_COUNT][BATT_W * BATT_H];
static struct cached_battery_slot cached_slots[BATTERY_SLOT_COUNT];
static bool show_approx_pct = false;

static uint8_t remap_zmk_linear_pct_to_lipo(uint8_t raw_pct) {
    if (raw_pct == 0) {
        return 0;
    }
    if (raw_pct >= 100) {
        return 100;
    }

    /* Inverte a reta do ZMK (pct = mv * 2 / 15 - 459) de volta para mV aproximados */
    int32_t mv = ((int32_t)raw_pct + 459) * 15 / 2 + 4;

    if (mv >= lipo_curve[0].mv) {
        return lipo_curve[0].pct;
    }

    const size_t last = ARRAY_SIZE(lipo_curve) - 1;
    if (mv <= lipo_curve[last].mv) {
        return lipo_curve[last].pct;
    }

    for (size_t i = 0; i < last; i++) {
        int32_t hi_mv = lipo_curve[i].mv;
        int32_t lo_mv = lipo_curve[i + 1].mv;
        if (mv >= lo_mv) {
            int32_t hi_pct = lipo_curve[i].pct;
            int32_t lo_pct = lipo_curve[i + 1].pct;
            int32_t pct = lo_pct + ((mv - lo_mv) * (hi_pct - lo_pct)) / (hi_mv - lo_mv);
            return (uint8_t)CLAMP(pct, 1, 100);
        }
    }

    return 1;
}

static int8_t compute_battery_bars(uint8_t pct, int8_t prev_bars) {
    /* Limiares base para 1, 2, 3 e 4 barras (abaixo de 12% exibe alerta '!') */
    static const uint8_t thresholds[4] = {12, 25, 50, 75};

    if (prev_bars < 0 || prev_bars > 4) {
        int8_t bars = 0;
        for (int i = 0; i < 4; i++) {
            if (pct >= thresholds[i]) {
                bars = i + 1;
            }
        }
        return bars;
    }

    int8_t bars = prev_bars;
    while (bars < 4 && pct >= thresholds[bars] + BATT_HYSTERESIS_PCT) {
        bars++;
    }
    while (bars > 0 && pct < thresholds[bars - 1] - BATT_HYSTERESIS_PCT) {
        bars--;
    }
    return bars;
}

static void draw_filled_rect(lv_obj_t *canvas, lv_coord_t x, lv_coord_t y, lv_coord_t w,
                             lv_coord_t h, lv_color_t color) {
    for (lv_coord_t yy = y; yy < y + h; yy++) {
        for (lv_coord_t xx = x; xx < x + w; xx++) {
            lv_canvas_set_px(canvas, xx, yy, color);
        }
    }
}

static void draw_horizontal_battery(lv_obj_t *canvas, int8_t bars, bool usb_present) {
    lv_canvas_fill_bg(canvas, OLED_BG, LV_OPA_COVER);

    /* Contorno do corpo da bateria (x=0..18, y=0..8) */
    draw_filled_rect(canvas, 0, 0, 19, 1, OLED_FG);
    draw_filled_rect(canvas, 0, BATT_H - 1, 19, 1, OLED_FG);
    draw_filled_rect(canvas, 0, 0, 1, BATT_H, OLED_FG);
    draw_filled_rect(canvas, 18, 0, 1, BATT_H, OLED_FG);

    /* Terminal positivo a direita (x=19..20, y=2..6) */
    draw_filled_rect(canvas, 19, 2, 2, 5, OLED_FG);

    if (usb_present) {
        /* Indicador simples de alimentacao USB: cruz fina central */
        draw_filled_rect(canvas, 3, 4, 13, 1, OLED_FG);
        draw_filled_rect(canvas, 9, 2, 1, 5, OLED_FG);
        return;
    }

    if (bars <= 0) {
        /* Alerta '!' centralizado para bateria critica (< 12%) */
        draw_filled_rect(canvas, 9, 2, 1, 3, OLED_FG);
        draw_filled_rect(canvas, 9, 6, 1, 1, OLED_FG);
        return;
    }

    /* Ate 4 blocos internos de 3x5 px com 1 px de espaco entre eles */
    for (int b = 0; b < bars && b < 4; b++) {
        lv_coord_t bx = 2 + b * 4;
        draw_filled_rect(canvas, bx, 2, 3, 5, OLED_FG);
    }
}

static const char *slot_prefix(uint8_t source) {
#if IS_ENABLED(CONFIG_ZMK_DONGLE_DISPLAY_DONGLE_BATTERY)
    if (source == 0) {
        return "D";
    }
    uint8_t peripheral_idx = source - 1;
#else
    uint8_t peripheral_idx = source;
#endif
    if (peripheral_idx == 0) {
        return "L";
    }
    if (peripheral_idx == 1) {
        return "R";
    }
    return "?";
}

static void render_battery_slot(lv_obj_t *widget, uint8_t source) {
    if (source >= BATTERY_SLOT_COUNT) {
        return;
    }

    const struct cached_battery_slot *slot = &cached_slots[source];
    lv_obj_t *symbol = lv_obj_get_child(widget, source * 3);
    lv_obj_t *side_label = lv_obj_get_child(widget, source * 3 + 1);
    lv_obj_t *pct_label = lv_obj_get_child(widget, source * 3 + 2);

    bool visible = (slot->raw_level > 0 || slot->usb_present);
    if (!visible) {
        lv_obj_add_flag(symbol, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(side_label, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(pct_label, LV_OBJ_FLAG_HIDDEN);
        return;
    }

    if (show_approx_pct) {
        lv_obj_add_flag(symbol, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(side_label, LV_OBJ_FLAG_HIDDEN);
        lv_label_set_text_fmt(pct_label, "%s ~%u%%", slot_prefix(source), slot->calibrated_level);
        lv_obj_align(pct_label, LV_ALIGN_TOP_RIGHT, -BATT_RIGHT_MARGIN,
                     source * BATT_ROW_STEP + 1);
        lv_obj_clear_flag(pct_label, LV_OBJ_FLAG_HIDDEN);
    } else {
        lv_obj_add_flag(pct_label, LV_OBJ_FLAG_HIDDEN);
        draw_horizontal_battery(symbol, slot->bars, slot->usb_present);
        lv_label_set_text(side_label, slot_prefix(source));
        lv_obj_align(symbol, LV_ALIGN_TOP_RIGHT, -BATT_RIGHT_MARGIN, source * BATT_ROW_STEP);
        lv_obj_align(side_label, LV_ALIGN_TOP_RIGHT, -(BATT_W + BATT_RIGHT_MARGIN + 3),
                     source * BATT_ROW_STEP + 1);
        lv_obj_clear_flag(symbol, LV_OBJ_FLAG_HIDDEN);
        lv_obj_clear_flag(side_label, LV_OBJ_FLAG_HIDDEN);
    }
}

static void battery_status_update_cb(struct battery_state state) {
    if (!state.valid || state.source >= BATTERY_SLOT_COUNT) {
        return;
    }

    struct cached_battery_slot *slot = &cached_slots[state.source];
    slot->raw_level = state.level;
    slot->usb_present = state.usb_present;

    if (state.level == 0) {
        slot->calibrated_level = 0;
        slot->bars = -1;
    } else {
        slot->calibrated_level = remap_zmk_linear_pct_to_lipo(state.level);
        slot->bars = compute_battery_bars(slot->calibrated_level, slot->bars);
    }

    LOG_DBG("source: %d, raw: %d%%, lipo: %d%%, bars: %d, usb: %d", state.source, slot->raw_level,
            slot->calibrated_level, slot->bars, slot->usb_present);

    struct zmk_widget_dongle_battery_status *widget;
    SYS_SLIST_FOR_EACH_CONTAINER(&widgets, widget, node) {
        render_battery_slot(widget->obj, state.source);
    }
}

static struct battery_state battery_status_get_state(const zmk_event_t *eh) {
    const struct zmk_peripheral_battery_state_changed *periph_ev =
        as_zmk_peripheral_battery_state_changed(eh);
    if (periph_ev != NULL) {
        return (struct battery_state){
            .source = periph_ev->source + SOURCE_OFFSET,
            .level = periph_ev->state_of_charge,
            .usb_present = false,
            .valid = true,
        };
    }

#if IS_ENABLED(CONFIG_ZMK_DONGLE_DISPLAY_DONGLE_BATTERY)
    const struct zmk_battery_state_changed *central_ev = as_zmk_battery_state_changed(eh);
    if (central_ev != NULL || as_zmk_usb_conn_state_changed(eh) != NULL || eh == NULL) {
        return (struct battery_state){
            .source = 0,
            .level = (central_ev != NULL) ? central_ev->state_of_charge
                                          : zmk_battery_state_of_charge(),
#if IS_ENABLED(CONFIG_USB_DEVICE_STACK)
            .usb_present = zmk_usb_is_powered(),
#endif
            .valid = true,
        };
    }
#endif

    return (struct battery_state){.valid = false};
}

static void battery_layer_update_cb(struct battery_layer_state state) {
    show_approx_pct = state.show_pct;

    struct zmk_widget_dongle_battery_status *widget;
    SYS_SLIST_FOR_EACH_CONTAINER(&widgets, widget, node) {
        for (uint8_t i = 0; i < BATTERY_SLOT_COUNT; i++) {
            render_battery_slot(widget->obj, i);
        }
    }
}

static struct battery_layer_state battery_layer_get_state(const zmk_event_t *eh) {
    ARG_UNUSED(eh);
    zmk_keymap_layer_index_t idx = zmk_keymap_highest_layer_active();
    zmk_keymap_layer_id_t id = zmk_keymap_layer_index_to_id(idx);
    return (struct battery_layer_state){
        .show_pct = (id == TERGO_ADJUST_LAYER_ID),
    };
}

ZMK_DISPLAY_WIDGET_LISTENER(widget_dongle_battery_status, struct battery_state,
                            battery_status_update_cb, battery_status_get_state)
ZMK_SUBSCRIPTION(widget_dongle_battery_status, zmk_peripheral_battery_state_changed);

ZMK_DISPLAY_WIDGET_LISTENER(widget_dongle_battery_layer, struct battery_layer_state,
                            battery_layer_update_cb, battery_layer_get_state)
ZMK_SUBSCRIPTION(widget_dongle_battery_layer, zmk_layer_state_changed);

#if IS_ENABLED(CONFIG_ZMK_DONGLE_DISPLAY_DONGLE_BATTERY)
#if !IS_ENABLED(CONFIG_ZMK_SPLIT) || IS_ENABLED(CONFIG_ZMK_SPLIT_ROLE_CENTRAL)

ZMK_SUBSCRIPTION(widget_dongle_battery_status, zmk_battery_state_changed);
#if IS_ENABLED(CONFIG_USB_DEVICE_STACK)
ZMK_SUBSCRIPTION(widget_dongle_battery_status, zmk_usb_conn_state_changed);
#endif /* IS_ENABLED(CONFIG_USB_DEVICE_STACK) */
#endif /* !IS_ENABLED(CONFIG_ZMK_SPLIT) || IS_ENABLED(CONFIG_ZMK_SPLIT_ROLE_CENTRAL) */
#endif /* IS_ENABLED(CONFIG_ZMK_DONGLE_DISPLAY_DONGLE_BATTERY) */

int zmk_widget_dongle_battery_status_init(struct zmk_widget_dongle_battery_status *widget,
                                          lv_obj_t *parent) {
    widget->obj = lv_obj_create(parent);

    /* Tamanho fixo evita colapso de layout no LVGL 8 ao alternar filhos com LV_ALIGN_TOP_RIGHT */
    lv_obj_set_size(widget->obj, BATT_CONTAINER_W, BATTERY_SLOT_COUNT * BATT_ROW_STEP);
    lv_obj_set_style_pad_all(widget->obj, 0, 0);
    lv_obj_set_style_border_width(widget->obj, 0, 0);
    lv_obj_clear_flag(widget->obj, LV_OBJ_FLAG_SCROLLABLE);

    for (int i = 0; i < BATTERY_SLOT_COUNT; i++) {
        cached_slots[i].bars = -1;

        lv_obj_t *image_canvas = lv_canvas_create(widget->obj);
        lv_obj_t *side_label = lv_label_create(widget->obj);
        lv_obj_t *pct_label = lv_label_create(widget->obj);

        lv_canvas_set_buffer(image_canvas, battery_image_buffer[i], BATT_W, BATT_H,
                             LV_IMG_CF_TRUE_COLOR);

        lv_obj_align(image_canvas, LV_ALIGN_TOP_RIGHT, -BATT_RIGHT_MARGIN, i * BATT_ROW_STEP);
        lv_obj_align(side_label, LV_ALIGN_TOP_RIGHT, -(BATT_W + BATT_RIGHT_MARGIN + 3),
                     i * BATT_ROW_STEP + 1);
        lv_obj_align(pct_label, LV_ALIGN_TOP_RIGHT, -BATT_RIGHT_MARGIN, i * BATT_ROW_STEP + 1);

        lv_obj_add_flag(image_canvas, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(side_label, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(pct_label, LV_OBJ_FLAG_HIDDEN);
    }

    sys_slist_append(&widgets, &widget->node);

    widget_dongle_battery_status_init();
    widget_dongle_battery_layer_init();

    return 0;
}

lv_obj_t *zmk_widget_dongle_battery_status_obj(struct zmk_widget_dongle_battery_status *widget) {
    return widget->obj;
}
