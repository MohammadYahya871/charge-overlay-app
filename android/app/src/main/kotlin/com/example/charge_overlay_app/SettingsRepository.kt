package com.example.charge_overlay_app

import android.content.Context

object SettingsRepository {
    private const val PREFS_NAME = "charge_overlay_settings"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_MODE = "displayMode"
    private const val KEY_LIVE_SCREEN_STYLE = "liveScreenStyle"
    private const val KEY_BACKGROUND_STYLE = "backgroundStyle"
    private const val KEY_DURATION = "durationMinutes"
    private const val KEY_VIDEO_PATH = "videoPath"
    private const val KEY_SHOW_PERCENTAGE_ON_VIDEO = "showPercentageOnVideo"
    private const val KEY_SHOW_NOTIFICATIONS = "showNotifications"
    private const val KEY_KEEP_SCREEN_AWAKE = "keepScreenAwake"

    fun read(context: Context): Map<String, Any?> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return mapOf(
            KEY_ENABLED to prefs.getBoolean(KEY_ENABLED, false),
            KEY_MODE to prefs.getString(KEY_MODE, "live"),
            KEY_LIVE_SCREEN_STYLE to prefs.getString(KEY_LIVE_SCREEN_STYLE, "wave"),
            KEY_BACKGROUND_STYLE to prefs.getString(KEY_BACKGROUND_STYLE, "pulse"),
            KEY_DURATION to prefs.getInt(KEY_DURATION, 2),
            KEY_VIDEO_PATH to prefs.getString(KEY_VIDEO_PATH, null),
            KEY_SHOW_PERCENTAGE_ON_VIDEO to prefs.getBoolean(KEY_SHOW_PERCENTAGE_ON_VIDEO, true),
            KEY_SHOW_NOTIFICATIONS to prefs.getBoolean(KEY_SHOW_NOTIFICATIONS, true),
            KEY_KEEP_SCREEN_AWAKE to prefs.getBoolean(KEY_KEEP_SCREEN_AWAKE, true),
        )
    }

    fun write(context: Context, values: Map<*, *>) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().apply {
            putBoolean(KEY_ENABLED, values[KEY_ENABLED] as? Boolean ?: false)
            putString(KEY_MODE, values[KEY_MODE] as? String ?: "live")
            putString(KEY_LIVE_SCREEN_STYLE, values[KEY_LIVE_SCREEN_STYLE] as? String ?: "wave")
            putString(KEY_BACKGROUND_STYLE, values[KEY_BACKGROUND_STYLE] as? String ?: "pulse")
            putInt(KEY_DURATION, (values[KEY_DURATION] as? Number)?.toInt() ?: 2)

            val videoPath = values[KEY_VIDEO_PATH] as? String
            if (videoPath.isNullOrBlank()) {
                remove(KEY_VIDEO_PATH)
            } else {
                putString(KEY_VIDEO_PATH, videoPath)
            }

            putBoolean(
                KEY_SHOW_PERCENTAGE_ON_VIDEO,
                values[KEY_SHOW_PERCENTAGE_ON_VIDEO] as? Boolean ?: true,
            )
            putBoolean(KEY_SHOW_NOTIFICATIONS, values[KEY_SHOW_NOTIFICATIONS] as? Boolean ?: true)
            putBoolean(KEY_KEEP_SCREEN_AWAKE, values[KEY_KEEP_SCREEN_AWAKE] as? Boolean ?: true)
            apply()
        }
    }
}
