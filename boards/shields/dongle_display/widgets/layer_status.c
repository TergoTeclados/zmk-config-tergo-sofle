/*
 * Copyright (c) 2020 The ZMK Contributors
 *
 * SPDX-License-Identifier: MIT
 */

#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
LOG_MODULE_DECLARE(zmk, CONFIG_ZMK_LOG_LEVEL);

#include <zmk/display/widgets/layer_status.h>
#include <zmk/display.h>
#include <zmk/events/layer_state_changed.h>
#include <zmk/event_manager.h>
#include <zmk/endpoints.h>
#include <zmk/keymap.h>

#ifndef TERGO_FW_VERSION
#define TERGO_FW_VERSION "Confg"
#endif

#define TERGO_ADJUST_LAYER_ID 4

static sys_slist_t widgets = SYS_SLIST_STATIC_INIT(&widgets);

struct layer_status_state {
    uint8_t index;
    zmk_keymap_layer_id_t id;
    const char *label;
};

static void set_layer_symbol(lv_obj_t *label, struct layer_status_state state) {
    if (state.id == TERGO_ADJUST_LAYER_ID) {
        lv_label_set_text(label, TERGO_FW_VERSION);
    } else if (state.label == NULL) {
        char text[7] = {};

        sprintf(text, "%i", state.index);

        lv_label_set_text(label, text);
    } else {
        char text[13] = {};

        snprintf(text, sizeof(text), "%s", state.label);

        lv_label_set_text(label, text);
    }
}

static void layer_status_update_cb(struct layer_status_state state) {
    struct zmk_widget_layer_status *widget;
    SYS_SLIST_FOR_EACH_CONTAINER(&widgets, widget, node) { set_layer_symbol(widget->obj, state); }
}

static struct layer_status_state layer_status_get_state(const zmk_event_t *eh) {
    zmk_keymap_layer_index_t index = zmk_keymap_highest_layer_active();
    zmk_keymap_layer_id_t id = zmk_keymap_layer_index_to_id(index);
    return (struct layer_status_state) {
        .index = index,
        .id = id,
        .label = zmk_keymap_layer_name(id),
    };
}

ZMK_DISPLAY_WIDGET_LISTENER(widget_layer_status, struct layer_status_state, layer_status_update_cb,
                            layer_status_get_state)

ZMK_SUBSCRIPTION(widget_layer_status, zmk_layer_state_changed);

int zmk_widget_layer_status_init(struct zmk_widget_layer_status *widget, lv_obj_t *parent) {
    widget->obj = lv_label_create(parent);

    sys_slist_append(&widgets, &widget->node);

    widget_layer_status_init();
    return 0;
}

lv_obj_t *zmk_widget_layer_status_obj(struct zmk_widget_layer_status *widget) {
    return widget->obj;
}
