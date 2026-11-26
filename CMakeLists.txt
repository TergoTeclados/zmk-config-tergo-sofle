if ((NOT CONFIG_ZMK_SPLIT) OR CONFIG_ZMK_SPLIT_ROLE_CENTRAL)
  target_sources_ifdef(CONFIG_ZMK_BEHAVIOR_SENSOR_ROTATE_KEY_POS app PRIVATE src/behaviors/behavior_sensor_rotate_key_pos.c)
  target_sources_ifdef(CONFIG_ZMK_BEHAVIOR_MOUSE_SCROLL_STEP app PRIVATE src/behaviors/behavior_mouse_scroll_step.c)
endif()
