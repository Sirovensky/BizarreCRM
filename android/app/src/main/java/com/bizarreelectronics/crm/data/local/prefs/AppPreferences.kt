package com.bizarreelectronics.crm.data.local.prefs

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AppPreferences @Inject constructor(
    @ApplicationContext context: Context,
) {
    private val prefs: SharedPreferences = context.getSharedPreferences("app_prefs", Context.MODE_PRIVATE)

    /**
     * Separate EncryptedSharedPreferences file for sensitive tokens.
     * Keys are AES256-SIV encrypted; values are AES256-GCM encrypted.
     * Master key is stored in the Android Keystore (AES256_GCM scheme).
     */
    private val encryptedPrefs: SharedPreferences = EncryptedSharedPreferences.create(
        context,
        "app_secure_prefs",
        MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build(),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    init {
        // One-time migration: if fcmToken exists in plain prefs, move it to
        // encrypted prefs and remove it from plain prefs. Idempotent — once
        // the plain-prefs key is absent this block is a no-op on every subsequent init.
        val plainToken = prefs.getString("fcm_token", null)
        if (plainToken != null) {
            encryptedPrefs.edit().putString("fcm_token", plainToken).apply()
            prefs.edit().remove("fcm_token").apply()
        }
    }

    var syncInterval: Int
        get() = prefs.getInt("sync_interval_minutes", 15)
        set(value) = prefs.edit().putInt("sync_interval_minutes", value).apply()

    // Backing StateFlows so Compose callers can observe theme changes without
    // activity recreate. Both are initialised from the persisted pref values so
    // there is no stale-read window between init and first emit.
    private val _darkModeFlow = MutableStateFlow(
        prefs.getString("dark_mode", "system") ?: "system",
    )
    val darkModeFlow: StateFlow<String> = _darkModeFlow.asStateFlow()

    var darkMode: String
        get() = prefs.getString("dark_mode", "system") ?: "system" // system, light, dark
        set(value) {
            prefs.edit().putString("dark_mode", value).apply()
            _darkModeFlow.value = value
        }

    var lastFullSyncAt: String?
        get() = prefs.getString("last_full_sync", null)
        set(value) = prefs.edit().putString("last_full_sync", value).apply()

    /** FCM registration token stored in EncryptedSharedPreferences (AES256-GCM). */
    var fcmToken: String?
        get() = encryptedPrefs.getString("fcm_token", null)
        set(value) = encryptedPrefs.edit().putString("fcm_token", value).apply()

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

    // --- CROSS38b-notif: notification preferences ---------------------------
    //
    // Device-local toggles for the six notification categories surfaced on
    // `NotificationSettingsScreen`. All default ON so a fresh install gets the
    // expected out-of-the-box behavior (match the 65-of-70-toggles-do-nothing
    // doc note — these ARE wired, but server-side enforcement of the same
    // categories is tracked separately). Stored as a flat boolean each so the
    // UI can bind a Switch to each key without a JSON blob.

    var notifEmailAlertsEnabled: Boolean
        get() = prefs.getBoolean("notif_email_alerts", true)
        set(value) = prefs.edit().putBoolean("notif_email_alerts", value).apply()

    var notifSmsAlertsEnabled: Boolean
        get() = prefs.getBoolean("notif_sms_alerts", true)
        set(value) = prefs.edit().putBoolean("notif_sms_alerts", value).apply()

    var notifPushEnabled: Boolean
        get() = prefs.getBoolean("notif_push", true)
        set(value) = prefs.edit().putBoolean("notif_push", value).apply()

    var notifLowStockEnabled: Boolean
        get() = prefs.getBoolean("notif_low_stock", true)
        set(value) = prefs.edit().putBoolean("notif_low_stock", value).apply()

    var notifNewTicketEnabled: Boolean
        get() = prefs.getBoolean("notif_new_ticket", true)
        set(value) = prefs.edit().putBoolean("notif_new_ticket", value).apply()

    var notifAppointmentReminderEnabled: Boolean
        get() = prefs.getBoolean("notif_appointment_reminder", true)
        set(value) = prefs.edit().putBoolean("notif_appointment_reminder", value).apply()

    // --- §13.2 quiet hours --------------------------------------------------
    //
    // When [quietHoursEnabled] is true, FcmService consults
    // [QuietHours.isInQuietWindow] before posting a non-critical notification
    // and downgrades alert importance (no sound / no vibration) if the local
    // clock is between [quietHoursStartMinutes] and [quietHoursEndMinutes].
    //
    // Times stored as minutes-from-midnight so the wrap-around case
    // (e.g. start=22:00 end=07:00) doesn't need a separate "ends next day"
    // flag — caller handles via modulo.

    var quietHoursEnabled: Boolean
        get() = prefs.getBoolean("quiet_hours_enabled", false)
        set(value) = prefs.edit().putBoolean("quiet_hours_enabled", value).apply()

    /** Minutes from midnight, 0..1439. Default 22:00 = 1320. */
    var quietHoursStartMinutes: Int
        get() = prefs.getInt("quiet_hours_start_min", 22 * 60)
        set(value) = prefs.edit().putInt("quiet_hours_start_min", value.coerceIn(0, 1439)).apply()

    /** Minutes from midnight, 0..1439. Default 07:00 = 420. */
    var quietHoursEndMinutes: Int
        get() = prefs.getInt("quiet_hours_end_min", 7 * 60)
        set(value) = prefs.edit().putInt("quiet_hours_end_min", value.coerceIn(0, 1439)).apply()

    /**
     * §13.2 — channels that bypass quiet hours regardless of the user's
     * preference. Security alerts and SLA breaches are urgent enough that
     * silencing them risks customer-impact incidents.
     */
    val criticalChannelIds: Set<String> = setOf("sla_breach", "security_event")

    /** §3.5 — once the user dismisses the dashboard onboarding card, stay hidden. */
    var onboardingDismissed: Boolean
        get() = prefs.getBoolean("onboarding_dismissed", false)
        set(value) = prefs.edit().putBoolean("onboarding_dismissed", value).apply()

    /**
     * §26.4 — in-app Reduce Motion override. Defaults OFF; when ON, UI code
     * consults [com.bizarreelectronics.crm.util.ReduceMotion.isReduceMotion]
     * which forces animation-skip regardless of the system
     * `ANIMATOR_DURATION_SCALE` value. Gives users on OEMs that hide the
     * system toggle a reliable way to opt out of motion in-app.
     */
    var reduceMotionEnabled: Boolean
        get() = prefs.getBoolean("reduce_motion_enabled", false)
        set(value) = prefs.edit().putBoolean("reduce_motion_enabled", value).apply()

    /**
     * §27 — per-app language tag (ActionPlan §27).
     * Stored as a BCP-47 tag ("en", "es", "fr") or "system" to follow the
     * device locale. LanguageManager reads/writes this key and mirrors it to
     * the OS via LocaleManager (API 33+) or a manual Configuration override
     * (API 26-32). "system" means "clear the per-app override" so the device
     * locale takes effect.
     */
    var languageTag: String
        get() = prefs.getString("language_tag", "system") ?: "system"
        set(value) = prefs.edit().putString("language_tag", value).apply()

    /**
     * §1.4 (ActionPlan line 190) — Material You dynamic color opt-in.
     * Defaults FALSE so the Bizarre brand palette always renders out of the
     * box. When true AND device runs Android 12+ (API 31+), BizarreCrmTheme /
     * DesignSystemTheme will use dynamicLightColorScheme / dynamicDarkColorScheme
     * derived from the user's wallpaper. Exposed via Settings > Appearance.
     */
    private val _dynamicColorFlow = MutableStateFlow(
        prefs.getBoolean("dynamic_color_enabled", false),
    )
    val dynamicColorFlow: StateFlow<Boolean> = _dynamicColorFlow.asStateFlow()

    var dynamicColorEnabled: Boolean
        get() = prefs.getBoolean("dynamic_color_enabled", false)
        set(value) {
            prefs.edit().putBoolean("dynamic_color_enabled", value).apply()
            _dynamicColorFlow.value = value
        }

    // --- §18.1 recent global-search queries ---------------------------------
    //
    // Stored as a single \u0001-separated string under "recent_searches". The
    // raw list math (dedupe, case-fold, LIMIT-cap) lives in
    // [com.bizarreelectronics.crm.util.RecentSearches] so unit tests can
    // exercise it without a Context. Persistence here is deliberately plain
    // (not encrypted) — search queries are low-sensitivity hints, not PII.

    var recentSearches: List<String>
        get() = com.bizarreelectronics.crm.util.RecentSearches.deserialize(
            prefs.getString("recent_searches", null),
        )
        set(value) = prefs.edit()
            .putString(
                "recent_searches",
                com.bizarreelectronics.crm.util.RecentSearches.serialize(value),
            )
            .apply()

    /** Prepend a new query, respecting dedupe + LIMIT. See [RecentSearches.prepend]. */
    fun addRecentSearch(query: String) {
        recentSearches = com.bizarreelectronics.crm.util.RecentSearches.prepend(recentSearches, query)
    }

    /** Wipe the cache (user-requested clear). */
    fun clearRecentSearches() {
        prefs.edit().remove("recent_searches").apply()
    }

    // --- §1.7 line 239 — screen-capture prevention pref -----------------------
    //
    // When true, MainActivity applies FLAG_SECURE + setRecentsScreenshotEnabled(false)
    // to prevent PII leaking via Recents thumbnails, MediaProjection, or adb screencap.
    // Defaults TRUE so all release installs are protected out of the box (GDPR Art 32 /
    // PCI-DSS 3.4). The Settings toggle UI is owned by a separate agent (Wave 3).
    //
    // BuildConfig.DEBUG callers bypass FLAG_SECURE regardless of this pref so QA can
    // take screenshots — see MainActivity.onCreate.

    private val _screenCapturePreventionFlow = MutableStateFlow(
        prefs.getBoolean("screen_capture_prevention_enabled", true),
    )

    /**
     * §1.7 line 239 — observable screen-capture prevention preference.
     *
     * Collect in MainActivity via [collectAsState] to reactively add/clear
     * [android.view.WindowManager.LayoutParams.FLAG_SECURE] without an activity
     * recreate. Defaults TRUE (enabled).
     */
    val screenCapturePreventionFlow: Flow<Boolean> = _screenCapturePreventionFlow.asStateFlow()

    /**
     * §1.7 line 239 — screen-capture prevention toggle.
     *
     * Writing this pref causes [screenCapturePreventionFlow] to emit immediately so
     * MainActivity can react within the same Compose recomposition cycle.
     * DO NOT add a Settings UI toggle here — that is owned by the Wave-3 Settings agent.
     */
    var screenCapturePreventionEnabled: Boolean
        get() = prefs.getBoolean("screen_capture_prevention_enabled", true)
        set(value) {
            prefs.edit().putBoolean("screen_capture_prevention_enabled", value).apply()
            _screenCapturePreventionFlow.value = value
        }

    // --- §1.7 line 238 — FCM token refresh timestamp --------------------------
    //
    // Epoch-ms of the last successful FCM token registration with the server.
    // FcmTokenRefresher.refreshIfStale() reads this to gate the 24-hour refresh
    // window. Stored in plain prefs (not encrypted) — the timestamp itself is not
    // sensitive; the token value is in encryptedPrefs.

    /**
     * §1.7 line 238 — epoch-ms when the FCM token was last successfully refreshed
     * and posted to the server. Zero on a fresh install.
     */
    var lastFcmTokenRefreshAtMs: Long
        get() = prefs.getLong("last_fcm_token_refresh_at_ms", 0L)
        set(value) = prefs.edit().putLong("last_fcm_token_refresh_at_ms", value).apply()

    // --- plan:L644 — ticket list view mode (list vs kanban) -----------------

    /**
     * Persisted ticket-list view mode. Values: "list" (default) | "kanban".
     * Read and written by [TicketListViewModel] on toggle; the Kanban option
     * renders a placeholder until full Kanban is implemented.
     */
    var ticketListViewMode: String
        get() = prefs.getString("ticket_list_view_mode", "list") ?: "list"
        set(value) = prefs.edit().putString("ticket_list_view_mode", value).apply()

    // --- plan:L645 — ticket list saved view ---------------------------------

    /**
     * Persisted saved-view selection for the ticket list. Stored as the
     * [TicketSavedView.name] enum literal. Defaults to "None" (no preset).
     */
    var ticketListSavedView: String
        get() = prefs.getString("ticket_list_saved_view", "None") ?: "None"
        set(value) = prefs.edit().putString("ticket_list_saved_view", value).apply()
}
