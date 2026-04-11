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

    // Cached dashboard KPIs for offline display
    var cachedOpenTickets: Int
        get() = prefs.getInt("cached_open_tickets", 0)
        set(value) = prefs.edit().putInt("cached_open_tickets", value).apply()

    var cachedRevenueToday: Double
        get() = prefs.getFloat("cached_revenue_today", 0f).toDouble()
        set(value) = prefs.edit().putFloat("cached_revenue_today", value.toFloat()).apply()

    var cachedLowStock: Int
        get() = prefs.getInt("cached_low_stock", 0)
        set(value) = prefs.edit().putInt("cached_low_stock", value).apply()

    var cachedMissingParts: Int
        get() = prefs.getInt("cached_missing_parts", 0)
        set(value) = prefs.edit().putInt("cached_missing_parts", value).apply()

    var cachedStaleTickets: Int
        get() = prefs.getInt("cached_stale_tickets", 0)
        set(value) = prefs.edit().putInt("cached_stale_tickets", value).apply()

    var cachedOverdueInvoices: Int
        get() = prefs.getInt("cached_overdue_invoices", 0)
        set(value) = prefs.edit().putInt("cached_overdue_invoices", value).apply()

    // --- Field-use enrichment (section 46 of the critical audit) -----------

    /**
     * Biometric quick-unlock gate. Defaults OFF — the user must opt in
     * through Settings > Security so we never surprise them with a prompt
     * on a fresh install.
     */
    var biometricEnabled: Boolean
        get() = prefs.getBoolean("biometric_enabled", false)
        set(value) = prefs.edit().putBoolean("biometric_enabled", value).apply()

    /**
     * Haptic feedback toggle. Defaults ON because short vibrations are the
     * expected UX on Android and turning them off is the exception.
     */
    var hapticEnabled: Boolean
        get() = prefs.getBoolean("haptic_enabled", true)
        set(value) = prefs.edit().putBoolean("haptic_enabled", value).apply()
}
