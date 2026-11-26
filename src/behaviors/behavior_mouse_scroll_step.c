/*
 * Copyright (c) 2026 Tergo Teclados
 *
 * SPDX-License-Identifier: MIT
 */

#define DT_DRV_COMPAT zmk_behavior_mouse_scroll_step

#include <zephyr/device.h>
#include <zephyr/logging/log.h>

#include <drivers/behavior.h>
#include <zmk/behavior.h>
#include <zmk/endpoints.h>
#include <zmk/hid.h>

LOG_MODULE_DECLARE(zmk, CONFIG_ZMK_LOG_LEVEL);

#if DT_HAS_COMPAT_STATUS_OKAY(DT_DRV_COMPAT) && IS_ENABLED(CONFIG_ZMK_POINTING)

struct behavior_mouse_scroll_step_config {
    int16_t scroll_x;
    int16_t scroll_y;
};

static int on_keymap_binding_pressed(struct zmk_behavior_binding *binding,
                                     struct zmk_behavior_binding_event event) {
    const struct device *dev = zmk_behavior_get_binding(binding->behavior_dev);
    if (!dev) {
        return -ENODEV;
    }

    const struct behavior_mouse_scroll_step_config *cfg = dev->config;

    LOG_DBG("position %d scroll step x=%d y=%d", event.position, cfg->scroll_x, cfg->scroll_y);

    zmk_hid_mouse_scroll_set(cfg->scroll_x, cfg->scroll_y);
    zmk_endpoints_send_mouse_report();
    zmk_hid_mouse_scroll_set(0, 0);

    return ZMK_BEHAVIOR_OPAQUE;
}

static int on_keymap_binding_released(struct zmk_behavior_binding *binding,
                                      struct zmk_behavior_binding_event event) {
    ARG_UNUSED(binding);
    ARG_UNUSED(event);
    return ZMK_BEHAVIOR_OPAQUE;
}

static const struct behavior_driver_api behavior_mouse_scroll_step_driver_api = {
    .binding_pressed = on_keymap_binding_pressed,
    .binding_released = on_keymap_binding_released,
#if IS_ENABLED(CONFIG_ZMK_BEHAVIOR_METADATA)
    .get_parameter_metadata = zmk_behavior_get_empty_param_metadata,
#endif
};

#define MOUSE_SCROLL_STEP_INST(n)                                                                  \
    static const struct behavior_mouse_scroll_step_config                                          \
        behavior_mouse_scroll_step_config_##n = {                                                  \
            .scroll_x = (int16_t)(int32_t)DT_INST_PROP_OR(n, scroll_x, 0),                         \
            .scroll_y = (int16_t)(int32_t)DT_INST_PROP_OR(n, scroll_y, 0),                         \
    };                                                                                             \
    BEHAVIOR_DT_INST_DEFINE(n, NULL, NULL, NULL, &behavior_mouse_scroll_step_config_##n,           \
                            POST_KERNEL, CONFIG_KERNEL_INIT_PRIORITY_DEFAULT,                      \
                            &behavior_mouse_scroll_step_driver_api);

DT_INST_FOREACH_STATUS_OKAY(MOUSE_SCROLL_STEP_INST)

#endif /* DT_HAS_COMPAT_STATUS_OKAY(DT_DRV_COMPAT) && IS_ENABLED(CONFIG_ZMK_POINTING) */
