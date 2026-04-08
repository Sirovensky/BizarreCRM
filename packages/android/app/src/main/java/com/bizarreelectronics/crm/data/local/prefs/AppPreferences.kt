package com.bizarreelectronics.crm.data.local.prefs

import android.content.Context
import android.content.SharedPreferences
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AppPreferences @Inject constructor(
    @ApplicationContext context: Context,
) {
    private val prefs: SharedPreferences = context.getSharedPreferences("app_prefs", Context.MODE_PRIVATE)

    var syncInterval: Int
        get() = prefs.getInt("sync_interval_minutes", 15)
        set(value) = prefs.edit().putInt("sync_interval_minutes", value).apply()

    var darkMode: String
        get() = prefs.getString("dark_mode", "system") ?: "system" // system, light, dark
        set(value) = prefs.edit().putString("dark_mode", value).apply()

    var lastFullSyncAt: String?
        get() = prefs.getString("last_full_sync", null)
        set(value) = prefs.edit().putString("last_full_sync", value).apply()

    var fcmToken: String?
        get() = prefs.getString("fcm_token", null)
        set(value) = prefs.edit().putString("fcm_token", value).apply()

    var fcmTokenRegistered: Boolean
        get() = prefs.getBoolean("fcm_token_registered", false)
        set(value) = prefs.edit().putBoolean("fcm_token_registered", value).apply()
}
