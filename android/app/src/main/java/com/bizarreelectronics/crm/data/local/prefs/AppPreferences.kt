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
import com.bizarreelectronics.crm.ui.theme.DashboardDensity
import com.bizarreelectronics.crm.ui.theme.DashboardDensity.Companion.toKey

@Singleton
class AppPreferences @Inject constructor(
    @ApplicationContext private val context: Context,
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

    // --- L1528 SMS compliance opt-in tracking ---------------------------------
    //
    // Tracks which phone numbers have already received the TCPA/CTIA opt-out footer
    // "Reply STOP to opt out." on first send. Only added once per number so repeat
    // sends in the same thread don't keep appending the footer.
    //
    // Stored as a JSON-array string (same serialisation as dismissedAttentionIds).
    // Plain prefs are sufficient; these are business-operational phone numbers, not PII credentials.

    /**
     * L1528 — set of phone numbers (E.164 or normalized 10-digit) that have already
     * received the compliance opt-out footer in their first outbound message.
     */
    val smsOptInSentTo: Set<String>
        get() {
            val raw = prefs.getString("sms_opt_in_sent_to", null) ?: return emptySet()
            return runCatching {
                raw.removeSurrounding("[", "]")
                    .split(",")
                    .map { it.trim().removeSurrounding("\"") }
                    .filter { it.isNotBlank() }
                    .toSet()
            }.getOrDefault(emptySet())
        }

    /**
     * Mark [phone] as having received the compliance footer.
     * Idempotent — adding an already-present phone is a no-op (set semantics).
     */
    fun markSmsOptInSent(phone: String) {
        val updated = smsOptInSentTo + phone
        prefs.edit().putString("sms_opt_in_sent_to", serializeStringSet(updated)).apply()
    }

    /** Returns true if [phone] has already received the compliance opt-out footer. */
    fun hasSmsOptInBeenSent(phone: String): Boolean = phone in smsOptInSentTo

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

    // --- plan:L653 — pinned ticket IDs (local cache) -----------------------
    //
    // Up to 5 ticket IDs persisted locally as a comma-separated Long string.
    // Pinning is also synced to the server via PATCH /tickets/{id}/pin;
    // when the server returns 404 the change is kept local-only without blocking
    // the UI (see TicketListViewModel.togglePin).

    /**
     * plan:L653 — Set of ticket IDs currently pinned by the user.
     *
     * Persisted as a comma-separated string (e.g. "1,42,7"). Returns an empty
     * set on a fresh install. Use [addPinnedTicketId] / [removePinnedTicketId]
     * to mutate; reading is idempotent.
     */
    var pinnedTicketIds: Set<Long>
        get() {
            val raw = prefs.getString("pinned_ticket_ids", null) ?: return emptySet()
            return runCatching {
                raw.split(",")
                    .mapNotNull { it.trim().toLongOrNull() }
                    .toSet()
            }.getOrDefault(emptySet())
        }
        set(value) {
            prefs.edit()
                .putString("pinned_ticket_ids", value.joinToString(","))
                .apply()
        }

    /** Add [ticketId] to the pinned set. Idempotent. */
    fun addPinnedTicketId(ticketId: Long) {
        pinnedTicketIds = pinnedTicketIds + ticketId
    }

    /** Remove [ticketId] from the pinned set. Idempotent. */
    fun removePinnedTicketId(ticketId: Long) {
        pinnedTicketIds = pinnedTicketIds - ticketId
    }

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

    // --- §3.13 L565–L567 — display / TV mode preferences --------------------
    //
    // [keepScreenOn] prevents the display from sleeping while the app is in the
    // foreground during normal (non-TV-board) use. The TV queue board always
    // keeps the screen on for its own lifetime via view.keepScreenOn regardless
    // of this setting. This pref is for the regular app shell.

    /**
     * §3.13 — When true, the regular app shell keeps the screen on via
     * `FLAG_KEEP_SCREEN_ON`.  Defaults false (standard power-saving behaviour).
     */
    var keepScreenOn: Boolean
        get() = prefs.getBoolean("keep_screen_on", false)
        set(value) = prefs.edit().putBoolean("keep_screen_on", value).apply()

    // --- §2.14 [plan:L369-L378] — shared-device / counter-kiosk mode --------
    //
    // When [sharedDeviceModeEnabled] is true, the app shows a staff-picker
    // screen (LazyVerticalGrid of avatars) after [sharedDeviceInactivityMinutes]
    // of inactivity instead of the single-user PIN lock. This is the primary
    // toggle that gates the entire shared-device flow.
    //
    // [sharedDeviceCurrentUserId] tracks the user_id of the staff member
    // currently signed in on the shared device. POS cart binds to this id;
    // switching staff parks the active cart (POS integration contract — out of
    // scope for this commit, tracked as a follow-up).
    //
    // All three fields are stored in EncryptedSharedPreferences because they
    // contain business-operational metadata and the current userId is PII-adjacent.

    private val _sharedDeviceModeFlow = MutableStateFlow(
        encryptedPrefs.getBoolean("shared_device_mode_enabled", false),
    )

    /**
     * §2.14 — observable shared-device mode flag.
     *
     * Collect in UI layers to reactively adapt the lock-screen target (StaffPicker
     * vs PIN-only). Defaults FALSE so single-user installs are unaffected.
     */
    val sharedDeviceModeFlow: Flow<Boolean> = _sharedDeviceModeFlow.asStateFlow()

    /**
     * §2.14 — shared-device mode master switch.
     *
     * Enabling triggers SessionTimeoutConfig.buildConfig() to return tightened
     * thresholds; disabling reverts to §2.16 standard defaults. Gated in the UI
     * behind [KeyguardManager.isDeviceSecure] and a minimum-two-staff-accounts
     * check — those guards live in [SharedDeviceViewModel], not here.
     *
     * Stored in EncryptedSharedPreferences (AES256-GCM).
     */
    var sharedDeviceModeEnabled: Boolean
        get() = encryptedPrefs.getBoolean("shared_device_mode_enabled", false)
        set(value) {
            encryptedPrefs.edit().putBoolean("shared_device_mode_enabled", value).apply()
            _sharedDeviceModeFlow.value = value
        }

    private val _sharedDeviceInactivityFlow = MutableStateFlow(
        encryptedPrefs.getInt("shared_device_inactivity_minutes", 10),
    )

    /**
     * §2.14 — observable inactivity window (minutes) for shared-device mode.
     *
     * Allowed values: 5 / 10 / 15 / 30 / 240. Written by [SharedDeviceViewModel]
     * after the user moves the slider. Collect to drive SessionTimeoutConfig.
     */
    val sharedDeviceInactivityMinutesFlow: Flow<Int> = _sharedDeviceInactivityFlow.asStateFlow()

    /**
     * §2.14 — inactivity window (minutes) before the app locks to the StaffPicker.
     *
     * Default 10 minutes. Allowed values: 5 / 10 / 15 / 30 / 240.
     * SessionTimeoutConfig.coerceInactivityMinutes() enforces the allowed set.
     *
     * Stored in EncryptedSharedPreferences (AES256-GCM).
     */
    var sharedDeviceInactivityMinutes: Int
        get() = encryptedPrefs.getInt("shared_device_inactivity_minutes", 10)
        set(value) {
            encryptedPrefs.edit().putInt("shared_device_inactivity_minutes", value).apply()
            _sharedDeviceInactivityFlow.value = value
        }

    // --- §3.3 L513 — dismissed attention IDs (client-side dismiss cache) -------

    /**
     * §3.3 L513 — client-side set of dismissed needs-attention item IDs.
     *
     * Returns an immutable copy. Use [addDismissedAttentionId] / [removeDismissedAttentionId]
     * to mutate. Stored as a JSON array string. Not sensitive — plain prefs.
     */
    val dismissedAttentionIds: Set<String>
        get() {
            val raw = prefs.getString("dismissed_attention_ids", null) ?: return emptySet()
            return runCatching {
                raw.removeSurrounding("[", "]")
                    .split(",")
                    .map { it.trim().removeSurrounding("\"") }
                    .filter { it.isNotBlank() }
                    .toSet()
            }.getOrDefault(emptySet())
        }

    /** Add [id] to the local dismiss cache. Idempotent. */
    fun addDismissedAttentionId(id: String) {
        val updated = dismissedAttentionIds + id
        prefs.edit().putString("dismissed_attention_ids", serializeStringSet(updated)).apply()
    }

    /** Remove [id] from the local dismiss cache (Undo support). */
    fun removeDismissedAttentionId(id: String) {
        val updated = dismissedAttentionIds - id
        prefs.edit().putString("dismissed_attention_ids", serializeStringSet(updated)).apply()
    }

    private fun serializeStringSet(set: Set<String>): String =
        "[${set.joinToString(",") { "\"$it\"" }}]"

    // --- §3.3 L513 — seen attention IDs (local mark-seen cache) ---------------

    /**
     * §3.3 L513 — client-side set of seen needs-attention item IDs.
     * "Mark seen" is lighter than dismiss: item stays visible but priority is
     * demoted in the UI. Local-only; no server call.
     */
    val seenAttentionIds: Set<String>
        get() {
            val raw = prefs.getString("seen_attention_ids", null) ?: return emptySet()
            return runCatching {
                raw.removeSurrounding("[", "]")
                    .split(",")
                    .map { it.trim().removeSurrounding("\"") }
                    .filter { it.isNotBlank() }
                    .toSet()
            }.getOrDefault(emptySet())
        }

    /** Mark [id] as seen locally. Idempotent. */
    fun addSeenAttentionId(id: String) {
        val updated = seenAttentionIds + id
        prefs.edit().putString("seen_attention_ids", serializeStringSet(updated)).apply()
    }

    // --- §3.4 L519 — My Queue section visibility toggle ---------------------------

    /**
     * §3.4 L519 — controls whether the My Queue section is shown on the Dashboard.
     *
     * Defaults TRUE so users see their queue out of the box. The setting is
     * surfaced via Dashboard preferences (long-press section header or Settings).
     * Independent of the server-side `ticket_all_employees_view_all` flag — both
     * must be true for the section to appear.
     */
    var dashboardShowMyQueue: Boolean
        get() = prefs.getBoolean("dashboard_show_my_queue", true)
        set(value) = prefs.edit().putBoolean("dashboard_show_my_queue", value).apply()

    // --- §3.5 L531 — Celebratory modal last-seen date -------------------------

    /**
     * §3.5 L531 — ISO-date string (yyyy-MM-dd) of the last day the celebratory
     * "Queue clear" modal was shown. Used to gate the "show once per day" rule.
     *
     * Null on a fresh install — means the modal has never been shown.
     */
    var lastCelebrationDate: String?
        get() = prefs.getString("last_celebration_date", null)
        set(value) = prefs.edit().putString("last_celebration_date", value).apply()

    // --- §3.7 L538 — dismissed announcement ID --------------------------------

    /**
     * §3.7 L538 — ID of the last announcement the user dismissed. When this
     * matches the server's current announcement ID the banner is hidden.
     *
     * Null on a fresh install — means no announcement has ever been dismissed.
     */
    var dismissedAnnouncementId: String?
        get() = prefs.getString("dismissed_announcement_id", null)
        set(value) = prefs.edit().putString("dismissed_announcement_id", value).apply()

    /**
     * §2.14 — user_id of the staff member currently signed in on a shared device.
     *
     * Null when shared-device mode is off or no switch has occurred since the
     * initial login. POS cart contract: when this id changes (staff switch),
     * the POS layer must park the in-progress cart under the outgoing user_id
     * and restore any parked cart for the incoming user_id. This is a contract
     * the POS integration will consume; enforcement is out of scope here.
     *
     * Stored in EncryptedSharedPreferences (AES256-GCM).
     *
     * Follow-up: DraftStore must key drafts by user_id (schema update required —
     * tracked separately; not implemented in this commit).
     */
    var sharedDeviceCurrentUserId: Long?
        get() = encryptedPrefs.getLong("shared_device_current_user_id", -1L)
            .takeIf { it != -1L }
        set(value) {
            if (value == null) {
                encryptedPrefs.edit().remove("shared_device_current_user_id").apply()
            } else {
                encryptedPrefs.edit().putLong("shared_device_current_user_id", value).apply()
            }
        }

    // --- §3.16 L597 — Activity feed per-user notification preference ----------
    //
    // When true, the Android app opts in to receive push notifications for
    // events on tickets assigned to the current user. This is a local-only
    // preference; the server-side FCM opt-in is driven by this value when the
    // next FCM token registration fires. Defaults OFF (user must opt in).

    /**
     * §3.16 L597 — When true, send push notifications for activity events
     * affecting tickets assigned to the current user.
     *
     * Surfaced via Settings > Notifications > "Notify me when X happens to
     * my tickets" sub-toggle row.
     */
    var activityNotifyOnMyTickets: Boolean
        get() = prefs.getBoolean("activity_notify_my_tickets", false)
        set(value) = prefs.edit().putBoolean("activity_notify_my_tickets", value).apply()

    // --- §36 L585–L588 — Morning-open checklist state -----------------------
    //
    // Three pref groups track the daily morning-checklist lifecycle:
    //
    //  1. [lastMorningChecklistDate]   — ISO-date of the last day a checklist
    //     session was started (or the date for which the banner was dismissed).
    //     Used by [MorningOpenCard] to decide whether to show today's banner.
    //
    //  2. [morningChecklistDismissedFor] — whether the user dismissed the
    //     checklist banner without completing it for a given date.
    //
    //  3. [morningChecklistCompletedSteps] — set of step IDs that were checked
    //     off during the checklist session for a given date. Serialised as a
    //     comma-separated integer string under key
    //     "morning_checklist_steps_<dateKey>".
    //
    // All three keys are plain prefs (not encrypted) — they contain business
    // operational metadata, not credentials.

    /**
     * §36 L585 — ISO-date string (yyyy-MM-dd) of the last day the morning
     * checklist was started or dismissed.  Null on a fresh install.
     *
     * Written by [MorningChecklistViewModel] on first screen open or banner
     * dismiss. Read by [MorningOpenCard] to gate the banner's visibility.
     */
    var lastMorningChecklistDate: String?
        get() = prefs.getString("morning_checklist_last_date", null)
        set(value) = prefs.edit().putString("morning_checklist_last_date", value).apply()

    /**
     * §36 L585 — Returns true if the morning-checklist banner was dismissed
     * (without fully completing it) for [date].
     *
     * [date] should be an ISO-date string (yyyy-MM-dd).
     */
    fun morningChecklistDismissedFor(date: String): Boolean =
        prefs.getBoolean("morning_checklist_dismissed_$date", false)

    /**
     * Mark the morning-checklist banner as dismissed for [date].
     *
     * Idempotent. Updates [lastMorningChecklistDate] as a side-effect so
     * the next comparison does not re-show the banner on the same day.
     */
    fun setMorningChecklistDismissed(date: String) {
        prefs.edit()
            .putBoolean("morning_checklist_dismissed_$date", true)
            .putString("morning_checklist_last_date", date)
            .apply()
    }

    /**
     * §36 L588 — Returns the set of step IDs checked off during the morning
     * checklist for [date].  Empty set when no steps have been completed or
     * when the pref key is absent.
     *
     * [date] should be an ISO-date string (yyyy-MM-dd).
     */
    fun morningChecklistCompletedSteps(date: String): Set<Int> {
        val raw = prefs.getString("morning_checklist_steps_$date", null)
            ?: return emptySet()
        return runCatching {
            raw.split(",")
                .mapNotNull { it.trim().toIntOrNull() }
                .toSet()
        }.getOrDefault(emptySet())
    }

    /**
     * §36 L588 — Persist the completion state for the morning checklist.
     *
     * Stores [completedSteps] for [dateKey] and records the latest
     * [lastMorningChecklistDate] for the dashboard trigger check.
     *
     * @param dateKey        ISO-date string (yyyy-MM-dd).
     * @param staffId        ID of the staff member completing the checklist
     *                       (stored alongside the steps for audit purposes).
     * @param completedSteps Set of step IDs that were checked off.
     */
    fun setMorningChecklistCompleted(dateKey: String, staffId: Long, completedSteps: Set<Int>) {
        val serialized = completedSteps.joinToString(",")
        prefs.edit()
            .putString("morning_checklist_steps_$dateKey", serialized)
            .putString("morning_checklist_last_date", dateKey)
            .putLong("morning_checklist_last_staff_$dateKey", staffId)
            .apply()
    }

    // --- §3.17 L602-L610 — Dashboard layout customization ---------------------
    //
    // Three keys store the user's layout customisation independently of density:
    //
    //  [dashboardTileOrder]   — ordered list of tile IDs; persisted JSON array.
    //                           Empty → no saved order (use role-template default).
    //  [dashboardHiddenTiles] — set of tile IDs the user has hidden.
    //  [savedDashboards]      — list of named saved layouts (JSON array of
    //                           SavedDashboard objects), up to 5 entries.
    //
    // On first launch (no [dashboardTileOrder] key) the ViewModel applies the
    // role-template default and hides advanced tiles per L610.

    /**
     * §3.17 L606 — Ordered list of tile IDs reflecting the user's drag-to-rearrange
     * choice. Empty list = no override (role-template order applies).
     *
     * Written by [DashboardCustomizationSheet] on save. Read by [DashboardViewModel]
     * during layout-config assembly.
     */
    var dashboardTileOrder: List<String>
        get() {
            val raw = prefs.getString("dashboard_tile_order", null) ?: return emptyList()
            return runCatching {
                raw.removeSurrounding("[", "]")
                    .split(",")
                    .map { it.trim().removeSurrounding("\"") }
                    .filter { it.isNotBlank() }
            }.getOrDefault(emptyList())
        }
        set(value) = prefs.edit()
            .putString("dashboard_tile_order", serializeTileList(value))
            .apply()

    /**
     * §3.17 L496 — Set of tile IDs the user has explicitly hidden via the
     * customisation sheet. Empty set = no tiles hidden.
     *
     * Written by [DashboardCustomizationSheet] on save. Read by [DashboardViewModel]
     * to filter the rendered tile list.
     */
    var dashboardHiddenTiles: Set<String>
        get() {
            val raw = prefs.getString("dashboard_hidden_tiles", null) ?: return emptySet()
            return runCatching {
                raw.removeSurrounding("[", "]")
                    .split(",")
                    .map { it.trim().removeSurrounding("\"") }
                    .filter { it.isNotBlank() }
                    .toSet()
            }.getOrDefault(emptySet())
        }
        set(value) = prefs.edit()
            .putString("dashboard_hidden_tiles", serializeStringSet(value))
            .apply()

    /**
     * §3.17 L607-L608 — List of saved named dashboard layouts. Up to 5 entries.
     *
     * Stored as a JSON array of SavedDashboard objects (compact representation).
     * Null / missing key = no saved dashboards (only the built-in Default layout exists).
     *
     * Use [setSavedDashboards] to persist; never mutate the list in-place.
     */
    val savedDashboards: List<SavedDashboard>
        get() {
            val raw = prefs.getString("saved_dashboards", null) ?: return emptyList()
            return runCatching { SavedDashboard.deserializeList(raw) }.getOrDefault(emptyList())
        }

    /** Replace the entire saved-dashboard list. Immutable contract: always pass a new list. */
    fun setSavedDashboards(dashboards: List<SavedDashboard>) {
        prefs.edit()
            .putString("saved_dashboards", SavedDashboard.serializeList(dashboards))
            .apply()
    }

    private fun serializeTileList(tiles: List<String>): String =
        "[${tiles.joinToString(",") { "\"$it\"" }}]"

    // --- §4.14 L786 — accepted waiver versions (re-sign detection) -----------
    //
    // Tracks the template version that was last successfully signed by the user
    // for each waiver template ID. When the server returns a template with a
    // higher [WaiverTemplateDto.version], [WaiverListScreen] flags that template
    // as requiring re-sign on next interaction.
    //
    // Stored as a flat key-per-template-id scheme: "waiver_version_<templateId>"
    // maps to the Int version that was accepted. Plain prefs — not sensitive
    // (versions are monotonic counters; no PII).

    /**
     * §4.14 L786 — map of `templateId → accepted version` for re-sign detection.
     *
     * Returns an immutable snapshot. Use [setAcceptedWaiverVersion] to update.
     * Templates absent from the map are treated as never signed (version 0).
     */
    val acceptedWaiverVersions: Map<String, Int>
        get() {
            return prefs.all
                .filter { (k, _) -> k.startsWith("waiver_version_") }
                .mapNotNull { (k, v) ->
                    val templateId = k.removePrefix("waiver_version_")
                    val version = (v as? Int) ?: return@mapNotNull null
                    templateId to version
                }
                .toMap()
        }

    /**
     * §4.14 L786 — record that [templateId] at [version] has been signed.
     *
     * Idempotent — writing the same version twice is a no-op from the perspective
     * of the re-sign gate. Writing a higher version replaces the stored value.
     *
     * @param templateId  Template identifier from [WaiverTemplateDto.id].
     * @param version     Version from [WaiverTemplateDto.version] that was signed.
     */
    fun setAcceptedWaiverVersion(templateId: String, version: Int) {
        prefs.edit().putInt("waiver_version_$templateId", version).apply()
    }

    /**
     * §4.14 L786 — retrieve the last accepted version for [templateId], or 0
     * if the template has never been signed on this device.
     *
     * @param templateId Template identifier from [WaiverTemplateDto.id].
     * @return Last accepted version, or 0 (never signed).
     */
    fun getAcceptedWaiverVersion(templateId: String): Int =
        prefs.getInt("waiver_version_$templateId", 0)

    // --- §3.19 L613–L616 — Dashboard density mode ------------------------------
    //
    // Three modes: "comfortable" (default phone) / "cozy" (default tablet) / "compact".
    //
    // Default is determined once at init-time from the screen width so a fresh
    // tablet install starts at Cozy (more information) and a phone install starts
    // at Comfortable (more breathing room). The check uses DisplayMetrics.widthPixels
    // divided by density to obtain logical dp — the same breakpoint as WindowMode.
    //
    // Shared-device gate: when sharedDeviceModeEnabled = true, the density
    // preference is ignored by DashboardScreen and always reads Comfortable so
    // the counter-kiosk view is predictable for every staff member. The pref
    // is still persisted and written normally so switching back to personal
    // mode restores the user's last choice without re-prompting.

    private val defaultDensityKey: String by lazy {
        val metrics = context.resources.displayMetrics
        val widthDp = metrics.widthPixels / metrics.density
        if (widthDp >= 600f) DashboardDensity.Cozy.toKey() else DashboardDensity.Comfortable.toKey()
    }

    private val _dashboardDensityFlow = MutableStateFlow(
        DashboardDensity.fromKey(prefs.getString("dashboard_density", null) ?: defaultDensityKey),
    )

    /**
     * §3.19 L613 — observable dashboard density.
     *
     * Collect in [MainActivity] via [collectAsState] to reactively provide
     * [com.bizarreelectronics.crm.ui.theme.LocalDashboardDensity] around the
     * content tree. Defaults to [DashboardDensity.Comfortable] on phones and
     * [DashboardDensity.Cozy] on tablets for fresh installs.
     */
    val dashboardDensityFlow: Flow<DashboardDensity> = _dashboardDensityFlow.asStateFlow()

    /**
     * §3.19 L613 — current dashboard density (non-reactive snapshot).
     *
     * Prefer [dashboardDensityFlow] in Compose; use this getter only from
     * non-composable call sites (e.g. ViewModel init).
     */
    val dashboardDensity: DashboardDensity
        get() = DashboardDensity.fromKey(
            prefs.getString("dashboard_density", null) ?: defaultDensityKey,
        )

    /**
     * §3.19 L613 — persist the user's chosen density and emit to [dashboardDensityFlow].
     *
     * Writing this pref causes [dashboardDensityFlow] to emit immediately so
     * [MainActivity] can update [com.bizarreelectronics.crm.ui.theme.LocalDashboardDensity]
     * within the same Compose recomposition cycle — no activity recreate needed.
     */
    fun setDashboardDensity(density: DashboardDensity) {
        prefs.edit().putString("dashboard_density", density.toKey()).apply()
        _dashboardDensityFlow.value = density
    }

    // --- plan:L1997 — Tenant accent color override -------------------------
    //
    // Null means "use the default brand palette". Non-null is a packed ARGB
    // Int (android.graphics.Color / androidx.compose.ui.graphics.Color toArgb()).
    // AppearanceScreen writes via [tenantAccentColor] setter;
    // BizarreCrmTheme reads [tenantAccentColorFlow] to provide LocalBrandAccent.

    private val _tenantAccentColorFlow = MutableStateFlow<Int?>(
        prefs.getInt("tenant_accent_color", Int.MIN_VALUE).takeIf { it != Int.MIN_VALUE },
    )

    /**
     * plan:L1997 — Observable tenant accent color (packed ARGB Int, or null to restore
     * the default brand palette). Collect in BizarreCrmTheme to provide LocalBrandAccent.
     */
    val tenantAccentColorFlow: StateFlow<Int?> = _tenantAccentColorFlow.asStateFlow()

    /**
     * plan:L1997 — Tenant accent color override (packed ARGB Int, nullable).
     * Writing null clears the override and restores the default brand palette.
     */
    var tenantAccentColor: Int?
        get() = prefs.getInt("tenant_accent_color", Int.MIN_VALUE)
            .takeIf { it != Int.MIN_VALUE }
        set(value) {
            if (value == null) {
                prefs.edit().remove("tenant_accent_color").apply()
            } else {
                prefs.edit().putInt("tenant_accent_color", value).apply()
            }
            _tenantAccentColorFlow.value = value
        }

    // --- plan:L1999 — Font scale override ---------------------------------
    //
    // Maps to a UI SegmentedButton with four labels:
    //   "default" → fontScale = 1.0f
    //   "medium"  → fontScale = 1.15f
    //   "large"   → fontScale = 1.30f
    //   "xlarge"  → fontScale = 1.50f

    private val _fontScaleKeyFlow = MutableStateFlow(
        prefs.getString("font_scale_key", "default") ?: "default",
    )

    /** plan:L1999 — Observable font-scale key. */
    val fontScaleKeyFlow: StateFlow<String> = _fontScaleKeyFlow.asStateFlow()

    /** plan:L1999 — Selected font-scale key ("default" | "medium" | "large" | "xlarge"). */
    var fontScaleKey: String
        get() = prefs.getString("font_scale_key", "default") ?: "default"
        set(value) {
            prefs.edit().putString("font_scale_key", value).apply()
            _fontScaleKeyFlow.value = value
        }

    // --- plan:L2000 — High contrast mode -----------------------------------
    //
    // When true, AppearanceScreen swaps the ColorScheme for an AA 7:1 palette
    // via CompositionLocalProvider. Defaults false.

    private val _highContrastFlow = MutableStateFlow(
        prefs.getBoolean("high_contrast_enabled", false),
    )

    /** plan:L2000 — Observable high-contrast toggle. */
    val highContrastEnabledFlow: StateFlow<Boolean> = _highContrastFlow.asStateFlow()

    /** plan:L2000 — High-contrast mode toggle. */
    var highContrastEnabled: Boolean
        get() = prefs.getBoolean("high_contrast_enabled", false)
        set(value) {
            prefs.edit().putBoolean("high_contrast_enabled", value).apply()
            _highContrastFlow.value = value
        }

    // --- plan:L2004 — Timezone override ------------------------------------
    //
    // Null means "use the device default". Non-null is a ZoneId string
    // (e.g. "America/New_York"). DateFormatter reads this when non-null;
    // LanguageScreen writes via [timezoneOverride] setter.

    /** plan:L2004 — In-app timezone override (ZoneId string), or null to use device default. */
    var timezoneOverride: String?
        get() = prefs.getString("timezone_override", null)
        set(value) {
            if (value == null) {
                prefs.edit().remove("timezone_override").apply()
            } else {
                prefs.edit().putString("timezone_override", value).apply()
            }
        }

    // --- plan:L2006 — Currency override ------------------------------------
    //
    // Null means "use the device/OS currency from the active locale".
    // Non-null is an ISO 4217 currency code (e.g. "USD", "EUR").

    /** plan:L2006 — In-app currency override (ISO 4217), or null to use locale default. */
    var currencyOverride: String?
        get() = prefs.getString("currency_override", null)
        set(value) {
            if (value == null) {
                prefs.edit().remove("currency_override").apply()
            } else {
                prefs.edit().putString("currency_override", value).apply()
            }
        }

    // --- plan:L1992 — Per-channel ringtone URIs ----------------------------
    //
    // Stored as flat "notif_sound_<channelId>" keys in plain prefs.
    // Null means "use the channel default ringtone".

    /**
     * plan:L1992 — Get the persisted ringtone URI string for [channelId], or null
     * for the channel default.
     */
    fun getNotifSoundUri(channelId: String): String? =
        prefs.getString("notif_sound_$channelId", null)

    /**
     * plan:L1992 — Persist a ringtone URI for [channelId]. Pass null to restore
     * the channel default.
     */
    fun setNotifSoundUri(channelId: String, uri: String?) {
        if (uri == null) {
            prefs.edit().remove("notif_sound_$channelId").apply()
        } else {
            prefs.edit().putString("notif_sound_$channelId", uri).apply()
        }
    }

    // --- plan:L1991 — Per-event × per-channel notification matrix ---------
    //
    // Keys: "notif_matrix_<eventId>_<channelId>" where channelId ∈ {push, sms, email}.
    // All default true (opt-out model matching existing single-channel prefs).

    /**
     * plan:L1991 — Returns whether the [eventId] × [channelId] cell is enabled.
     * Defaults true.
     */
    fun getNotifMatrixEnabled(eventId: String, channelId: String): Boolean =
        prefs.getBoolean("notif_matrix_${eventId}_$channelId", true)

    /**
     * plan:L1991 — Persist the [enabled] state for the [eventId] × [channelId] cell.
     */
    fun setNotifMatrixEnabled(eventId: String, channelId: String, enabled: Boolean) {
        prefs.edit().putBoolean("notif_matrix_${eventId}_$channelId", enabled).apply()
    }
}
