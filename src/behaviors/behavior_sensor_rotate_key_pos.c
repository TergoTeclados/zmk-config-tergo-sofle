/*
 * Copyright (c) 2026 Tergo Teclados
 *
 * SPDX-License-Identifier: MIT
 */

#define DT_DRV_COMPAT zmk_behavior_sensor_rotate_key_pos

#include <zephyr/device.h>
#include <zephyr/drivers/sensor.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>

#include <drivers/behavior.h>
#include <zmk/behavior.h>
#include <zmk/behavior_queue.h>
#include <zmk/events/position_state_changed.h>
#include <zmk/keymap.h>
#include <zmk/matrix.h>
#include <zmk/sensors.h>
#include <zmk/virtual_key_position.h>

LOG_MODULE_DECLARE(zmk, CONFIG_ZMK_LOG_LEVEL);

#if DT_HAS_COMPAT_STATUS_OKAY(DT_DRV_COMPAT)

struct behavior_sensor_rotate_key_pos_config {
    int tap_ms;
};

struct behavior_sensor_rotate_key_pos_data {
    struct sensor_value remainder[ZMK_KEYMAP_SENSORS_LEN][ZMK_KEYMAP_LAYERS_LEN];
    int triggers[ZMK_KEYMAP_SENSORS_LEN][ZMK_KEYMAP_LAYERS_LEN];
};

static inline bool is_transparent_behavior(const struct device *dev) {
#if DT_HAS_COMPAT_STATUS_OKAY(zmk_behavior_transparent)
    static const struct device *const trans_dev =
        DEVICE_DT_GET_OR_NULL(DT_COMPAT_GET_ANY_STATUS_OKAY(zmk_behavior_transparent));
    return dev == trans_dev;
#else
    ARG_UNUSED(dev);
    return false;
#endif
}

static bool resolve_active_binding_for_position(uint32_t key_pos,
                                                struct zmk_behavior_binding *out_binding,
                                                zmk_keymap_layer_id_t *out_layer) {
    if (key_pos >= ZMK_KEYMAP_LEN) {
        LOG_WRN("Virtual key position %u out of range (max %u)", key_pos,
                (unsigned int)ZMK_KEYMAP_LEN);
        return false;
    }

    const zmk_keymap_layer_id_t default_layer = zmk_keymap_layer_default();

    for (int layer_idx = ZMK_KEYMAP_LAYERS_LEN - 1; layer_idx >= 0; layer_idx--) {
        zmk_keymap_layer_id_t layer_id = zmk_keymap_layer_index_to_id(layer_idx);
        if (layer_id == ZMK_KEYMAP_LAYER_ID_INVAL) {
            continue;
        }

        if (zmk_keymap_layer_active(layer_id)) {
            const struct zmk_behavior_binding *candidate =
                zmk_keymap_get_layer_binding_at_idx(layer_id, key_pos);
            if (candidate && candidate->behavior_dev && candidate->behavior_dev[0] != '\0') {
                const struct device *beh_dev = zmk_behavior_get_binding(candidate->behavior_dev);
                if (beh_dev && !is_transparent_behavior(beh_dev)) {
                    *out_binding = *candidate;
                    *out_layer = layer_id;
                    return true;
                }
            }
        }

        if (layer_id == default_layer) {
            break;
        }
    }

    return false;
}

static int on_sensor_binding_accept_data(struct zmk_behavior_binding *binding,
                                         struct zmk_behavior_binding_event event,
                                         const struct zmk_sensor_config *sensor_config,
                                         size_t channel_data_size,
                                         const struct zmk_sensor_channel_data *channel_data) {
    if (!sensor_config || channel_data_size == 0 || !channel_data) {
        return -EINVAL;
    }

    const struct device *dev = zmk_behavior_get_binding(binding->behavior_dev);
    if (!dev) {
        return -ENODEV;
    }

    struct behavior_sensor_rotate_key_pos_data *data = dev->data;
    const int sensor_index = ZMK_SENSOR_POSITION_FROM_VIRTUAL_KEY_POSITION(event.position);

    if (sensor_index < 0 || sensor_index >= ZMK_KEYMAP_SENSORS_LEN ||
        event.layer >= ZMK_KEYMAP_LAYERS_LEN) {
        return -EINVAL;
    }

    const struct sensor_value value = channel_data[0].value;
    int triggers;

    if (value.val1 == 0) {
        triggers = value.val2;
    } else {
        if (sensor_config->triggers_per_rotation <= 0) {
            return -EINVAL;
        }

        struct sensor_value remainder = data->remainder[sensor_index][event.layer];
        remainder.val1 += value.val1;
        remainder.val2 += value.val2;

        if (remainder.val2 >= 1000000 || remainder.val2 <= -1000000) {
            remainder.val1 += remainder.val2 / 1000000;
            remainder.val2 %= 1000000;
        }

        const int trigger_degrees = 360 / sensor_config->triggers_per_rotation;
        if (trigger_degrees <= 0) {
            return -EINVAL;
        }

        triggers = remainder.val1 / trigger_degrees;
        remainder.val1 %= trigger_degrees;

        data->remainder[sensor_index][event.layer] = remainder;
    }

    LOG_DBG("sensor %d layer %d: val1=%d val2=%d triggers=%d cw_pos=%u ccw_pos=%u", sensor_index,
            event.layer, value.val1, value.val2, triggers, binding->param1, binding->param2);

    data->triggers[sensor_index][event.layer] = triggers;
    return 0;
}

static int on_sensor_binding_process(struct zmk_behavior_binding *binding,
                                     struct zmk_behavior_binding_event event,
                                     enum behavior_sensor_binding_process_mode mode) {
    const struct device *dev = zmk_behavior_get_binding(binding->behavior_dev);
    if (!dev) {
        return -ENODEV;
    }

    const struct behavior_sensor_rotate_key_pos_config *cfg = dev->config;
    struct behavior_sensor_rotate_key_pos_data *data = dev->data;
    const int sensor_index = ZMK_SENSOR_POSITION_FROM_VIRTUAL_KEY_POSITION(event.position);

    if (sensor_index < 0 || sensor_index >= ZMK_KEYMAP_SENSORS_LEN ||
        event.layer >= ZMK_KEYMAP_LAYERS_LEN) {
        return -EINVAL;
    }

    if (mode != BEHAVIOR_SENSOR_BINDING_PROCESS_MODE_TRIGGER) {
        data->triggers[sensor_index][event.layer] = 0;
        return ZMK_BEHAVIOR_TRANSPARENT;
    }

    int triggers = data->triggers[sensor_index][event.layer];
    data->triggers[sensor_index][event.layer] = 0;

    uint32_t target_pos;
    if (triggers > 0) {
        target_pos = binding->param1;
    } else if (triggers < 0) {
        triggers = -triggers;
        target_pos = binding->param2;
    } else {
        return ZMK_BEHAVIOR_TRANSPARENT;
    }

    struct zmk_behavior_binding resolved_binding = {0};
    zmk_keymap_layer_id_t resolved_layer = 0;

    if (!resolve_active_binding_for_position(target_pos, &resolved_binding, &resolved_layer)) {
        LOG_DBG("No active binding found for virtual key position %u", target_pos);
        return ZMK_BEHAVIOR_TRANSPARENT;
    }

    struct zmk_behavior_binding_event target_event = {
        .layer = resolved_layer,
        .position = target_pos,
        .timestamp = event.timestamp,
#if IS_ENABLED(CONFIG_ZMK_SPLIT)
        .source = ZMK_POSITION_STATE_CHANGE_SOURCE_LOCAL,
#endif
    };

    LOG_DBG("Triggering pos %u on layer %u (%s p1=0x%x p2=0x%x) x%d", target_pos, resolved_layer,
            resolved_binding.behavior_dev, resolved_binding.param1, resolved_binding.param2,
            triggers);

    for (int i = 0; i < triggers; i++) {
        zmk_behavior_queue_add(&target_event, resolved_binding, true, cfg->tap_ms);
        zmk_behavior_queue_add(&target_event, resolved_binding, false, 0);
    }

    return ZMK_BEHAVIOR_OPAQUE;
}

static const struct behavior_driver_api behavior_sensor_rotate_key_pos_driver_api = {
    .sensor_binding_accept_data = on_sensor_binding_accept_data,
    .sensor_binding_process = on_sensor_binding_process,
};

#define SENSOR_ROTATE_KEY_POS_INST(n)                                                              \
    static const struct behavior_sensor_rotate_key_pos_config                                      \
        behavior_sensor_rotate_key_pos_config_##n = {                                              \
            .tap_ms = DT_INST_PROP(n, tap_ms),                                                     \
    };                                                                                             \
    static struct behavior_sensor_rotate_key_pos_data behavior_sensor_rotate_key_pos_data_##n =    \
        {};                                                                                        \
    BEHAVIOR_DT_INST_DEFINE(n, NULL, NULL, &behavior_sensor_rotate_key_pos_data_##n,               \
                            &behavior_sensor_rotate_key_pos_config_##n, POST_KERNEL,               \
                            CONFIG_KERNEL_INIT_PRIORITY_DEFAULT,                                   \
                            &behavior_sensor_rotate_key_pos_driver_api);

DT_INST_FOREACH_STATUS_OKAY(SENSOR_ROTATE_KEY_POS_INST)

#endif /* DT_HAS_COMPAT_STATUS_OKAY(DT_DRV_COMPAT) */
