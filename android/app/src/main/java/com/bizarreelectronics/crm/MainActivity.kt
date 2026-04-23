package com.bizarreelectronics.crm

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.MotionEvent
import android.view.WindowManager
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.fragment.app.FragmentActivity
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.local.prefs.PinPreferences
import com.bizarreelectronics.crm.data.sync.SyncManager
import com.bizarreelectronics.crm.ui.auth.BiometricAuth
import com.bizarreelectronics.crm.ui.auth.PinLockScreen
import com.bizarreelectronics.crm.ui.navigation.AppNavGraph
import com.bizarreelectronics.crm.ui.theme.BizarreCrmTheme
import com.bizarreelectronics.crm.util.ClockDrift
import com.bizarreelectronics.crm.util.DeepLinkBus
import com.bizarreelectronics.crm.util.RateLimiter
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import com.bizarreelectronics.crm.util.SessionTimeout
import com.bizarreelectronics.crm.util.rememberNotificationPermission
import com.bizarreelectronics.crm.util.LanguageManager
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject

/**
 * Hosts the Compose navigation graph and is the single entry point for
 * every intent that wants to land the user on a specific screen:
 *   - Launcher icon → dashboard
 *   - Home widget tap → dashboard (with cached values already rendered)
 *   - Quick-Settings tile tap → ticket-create (via ACTION_NEW_TICKET_FROM_TILE)
 *   - Google Assistant / shortcut deep link → route resolved from bizarrecrm://
 *   - FCM push notification tap → route resolved from `navigate_to` +
 *     `entity_id` extras (see AND-20260414-H2)
 *
 * Changed from ComponentActivity to FragmentActivity so BiometricPrompt can
 * attach its host fragment. FragmentActivity is a superset of
 * ComponentActivity and does not require any other code changes.
 */
@AndroidEntryPoint
class MainActivity : FragmentActivity() {

    @Inject
    lateinit var authPreferences: AuthPreferences

    @Inject
    lateinit var appPreferences: AppPreferences

    @Inject
    lateinit var serverReachabilityMonitor: ServerReachabilityMonitor

    @Inject
    lateinit var syncQueueDao: SyncQueueDao

    @Inject
    lateinit var syncManager: SyncManager

    @Inject
    lateinit var biometricAuth: BiometricAuth

    @Inject
    lateinit var pinPreferences: PinPreferences

    @Inject
    lateinit var breadcrumbs: com.bizarreelectronics.crm.util.Breadcrumbs

    @Inject
    lateinit var jankReporter: com.bizarreelectronics.crm.util.JankReporter

    @Inject
    lateinit var sessionTimeout: SessionTimeout

    @Inject
    lateinit var clockDrift: ClockDrift

    @Inject
    lateinit var rateLimiter: RateLimiter

    /**
     * Hilt-scoped handoff bus for routes extracted from launch /
     * onNewIntent intents. Shared by two entry points that both need to
     * feed a route into the nav graph once the NavController is composed:
     *   - AND-20260414-H1: launcher shortcut / App Actions / QS tile
     *     resolved by [resolveDeepLink].
     *   - AND-20260414-H2: FCM notification tap resolved by
     *     [resolveFcmRoute].
     * [com.bizarreelectronics.crm.ui.navigation.AppNavGraph] collects from
     * this bus and dispatches the navigate call, then consumes the value so
     * a configuration change doesn't re-fire the same route.
     */
    @Inject
    lateinit var deepLinkBus: DeepLinkBus

    /** Pending deep-link route extracted from the launch intent, if any. */
    private var pendingDeepLink: String? = null

    /** True until biometric unlock has either succeeded or been skipped. */
    private var isLocked: Boolean = false

    /**
     * §27 — pre-Android-13 locale persistence.
     *
     * On API 33+ [android.app.LocaleManager] keeps the locale durable across
     * cold starts and the system-provided context already carries the right
     * configuration; [LanguageManager.wrapContext] is a no-op in that case.
     *
     * On API 26-32 the OS has no knowledge of the per-app preference, so we
     * must wrap the base context with a [android.content.res.Configuration]
     * that sets the user-selected locale before any view inflation occurs.
     * This override fires early enough in the lifecycle that even the first
     * call to [resources.getString] during [onCreate] picks up the override.
     *
     * The read is performed without Hilt injection because this hook fires
     * before the activity Hilt component is created. [LanguageManager.wrapContext]
     * reads the shared preferences file directly and falls back to the
     * unmodified context if the file or key is absent.
     */
    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(LanguageManager.wrapContext(newBase))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // AUDIT-AND-011: FLAG_SECURE — customer PII should not leak via Recents thumbnail,
        // MediaProjection, or adb screencap. GDPR Article 32 + PCI-DSS 3.4.
        // DEBUG builds skip FLAG_SECURE so QA / on-device debugging via
        // adb screencap can capture screens. Release keeps it on.
        if (!BuildConfig.DEBUG) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        // §2.13: Android 12+ adds a dedicated switch to hide the current
        // Activity from the Recents task thumbnail on top of FLAG_SECURE.
        // Belt-and-suspenders: FLAG_SECURE already blanks the thumbnail, but
        // setRecentsScreenshotEnabled is the supported API going forward
        // and keeps us covered if the flag semantics drift.
        if (!BuildConfig.DEBUG && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            setRecentsScreenshotEnabled(false)
        }
        enableEdgeToEdge()
        // §29 — start frame-timing collection so jank surfaces in
        // breadcrumbs without an external profiler.
        jankReporter.attach(this)

        // Resolve a route from two possible sources, in priority order:
        //   1. AND-20260414-H1: launcher shortcut / App Actions / QS tile
        //      surfaces a whitelisted `bizarrecrm://` path via
        //      [resolveDeepLink].
        //   2. AND-20260414-H2: an FCM notification tap carries
        //      `navigate_to` + `entity_id` extras that [resolveFcmRoute]
        //      maps onto a concrete nav route like `tickets/{id}`.
        // A plain launcher-icon launch yields null and falls through to the
        // start destination. Publishing null is a no-op by contract on
        // [DeepLinkBus.publish].
        pendingDeepLink = resolveDeepLink(intent) ?: resolveFcmRoute(intent)
        deepLinkBus.publish(pendingDeepLink)

        // Decide whether to lock the UI behind a biometric prompt. The gate
        // is OFF unless (a) the user enabled it in Settings, (b) they still
        // hold EITHER an access token OR a refresh token (the latter covers
        // the case where the access token has expired but the session is
        // still valid server-side — the next request will silently refresh),
        // and (c) the device actually has a biometric / device-credential
        // enrolled. Requiring only accessToken was too narrow and caused
        // the gate to skip after any cold-start that wiped the short-lived
        // access JWT, leaving the user at the plain login screen despite
        // having a live session.
        val hasSession = authPreferences.accessToken != null ||
            authPreferences.refreshToken != null
        val shouldLock = appPreferences.biometricEnabled &&
            hasSession &&
            biometricAuth.canAuthenticate(this)
        isLocked = shouldLock

        setContent {
            // AUDIT-AND-003 / Wave-3: observe darkModeFlow and dynamicColorFlow
            // as Compose State so the theme re-renders immediately when the user
            // changes the setting on ThemeScreen — no activity recreate needed.
            val darkMode by appPreferences.darkModeFlow.collectAsState()
            val dynamicColor by appPreferences.dynamicColorFlow.collectAsState()
            val systemDark = isSystemInDarkTheme()
            val darkTheme = when (darkMode) {
                "dark"  -> true
                "light" -> false
                else    -> systemDark   // "system" follows OS setting
            }
            BizarreCrmTheme(darkTheme = darkTheme, dynamicColor = dynamicColor) {
                var locked by remember { mutableStateOf(isLocked) }
                // AUDIT §2.5: PIN gate. Shown after biometric (or on devices
                // without biometric) whenever the user has set a PIN and
                // PinPreferences.shouldLock() decides the grace window has
                // elapsed. A successful verify clears pinGated; Sign-out
                // clears the full session, which drops the user on Login via
                // AppNavGraph's own isLoggedIn observer.
                val hasSessionForPin = authPreferences.accessToken != null ||
                    authPreferences.refreshToken != null
                var pinGated by remember {
                    mutableStateOf(hasSessionForPin && pinPreferences.shouldLock())
                }

                if (locked) {
                    LaunchBiometricPrompt(
                        locked = locked,
                        onUnlocked = { locked = false },
                        onCancelled = { finish() },
                    )
                } else if (pinGated) {
                    PinLockScreen(
                        onUnlocked = { pinGated = false },
                        onSignOut = {
                            pinPreferences.reset()
                            authPreferences.clear()
                            pinGated = false
                        },
                    )
                } else {
                    // §13.2: prompt for POST_NOTIFICATIONS on first unlock
                    // (Android 13+ only — pre-T the permission didn't exist).
                    // Runs here so it never fires behind the lock screen.
                    rememberNotificationPermission(autoRequest = true)
                    AppNavGraph(
                        authPreferences = authPreferences,
                        serverReachabilityMonitor = serverReachabilityMonitor,
                        syncQueueDao = syncQueueDao,
                        syncManager = syncManager,
                        deepLinkBus = deepLinkBus,
                        breadcrumbs = breadcrumbs,
                        clockDrift = clockDrift,
                        rateLimiter = rateLimiter,
                        sessionTimeout = sessionTimeout,
                    )
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // On warm-start (Activity already on the back stack, e.g. user taps
        // a push while the app is backgrounded) we must reprocess the
        // incoming intent — otherwise the nav graph keeps showing whichever
        // screen was last visible. setIntent() keeps getIntent() in sync for
        // any Compose code that re-reads it during recomposition.
        setIntent(intent)
        // Same two-source resolution as onCreate — see publish call there
        // for the ordering rationale.
        pendingDeepLink = resolveDeepLink(intent) ?: resolveFcmRoute(intent)
        deepLinkBus.publish(pendingDeepLink)
    }

    /**
     * §2.16 activity signal — every touch ACTION_DOWN resets the inactivity
     * timer via [SessionTimeout.onActivity]. Scroll and text-entry events
     * surface as a series of touch events through this same path, so no
     * additional wiring is needed for those signals.
     *
     * Background push handlers and sync workers must NOT call
     * [SessionTimeout.onActivity] — only user-originated events count (line 398).
     */
    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        if (ev.action == MotionEvent.ACTION_DOWN) {
            sessionTimeout.onActivity()
        }
        return super.dispatchTouchEvent(ev)
    }

    /**
     * Wraps [BiometricAuth.showPrompt] in a composable-friendly launcher.
     *
     * AUDIT-AND-016: keyed on [locked] (the outer `var locked` state) rather
     * than `Unit` so that if the screen is restored while [locked] is still
     * true (e.g. user backgrounds the app and returns) the effect re-fires
     * and the prompt re-appears. With `LaunchedEffect(Unit)` a configuration
     * change or process-death restore could leave a permanently blank,
     * unresponsive screen because the effect ran once and never repeated.
     */
    @androidx.compose.runtime.Composable
    private fun LaunchBiometricPrompt(
        locked: Boolean,
        onUnlocked: () -> Unit,
        onCancelled: () -> Unit,
    ) {
        val activity = this
        androidx.compose.runtime.LaunchedEffect(locked) {
            if (locked) {
                biometricAuth.showPrompt(
                    activity = activity,
                    onSuccess = onUnlocked,
                    onError = { onCancelled() },
                )
            }
        }
    }

    /**
     * Pulls an internal deep-link path out of either:
     *  - A `bizarrecrm://` URI (launcher shortcut / Assistant)
     *  - The Quick Settings tile action
     * Returns null if the intent doesn't carry a recognised route.
     *
     * SECURITY: the deep-link intent filter is exported (any app on the
     * device can fire `bizarrecrm://...`), so we whitelist allowed routes
     * instead of echoing whatever host/path the caller passes in. A route
     * that isn't on [ALLOWED_DEEP_LINK_ROUTES] is dropped silently — the
     * nav graph just lands the user on the dashboard in that case.
     */
    private fun resolveDeepLink(intent: Intent?): String? {
        if (intent == null) return null
        if (intent.action == com.bizarreelectronics.crm.service.QuickTicketTileService
                .ACTION_NEW_TICKET_FROM_TILE) {
            return "ticket/new"
        }
        val data: Uri = intent.data ?: return null
        if (data.scheme != "bizarrecrm") return null

        // Normalise "bizarrecrm://ticket/new" → "ticket/new". We intentionally
        // do NOT include query parameters: a route is just a static path,
        // and the current whitelist has no route that needs arguments.
        val host = data.host ?: return null
        val path = data.path?.trimStart('/').orEmpty()
        val candidate = if (path.isEmpty()) host else "$host/$path"

        // §68.3 — delegate to the testable allow-list util so the check
        // can be exercised from a JVM unit test without needing a Context.
        return com.bizarreelectronics.crm.util.DeepLinkAllowlist.resolve(candidate)
    }

    /**
     * AND-20260414-H2: translate FCM push notification extras written by
     * [com.bizarreelectronics.crm.service.FcmService.onMessageReceived] into
     * a concrete nav route. FcmService puts two extras on the PendingIntent:
     *
     *   - `navigate_to`  — an entity type (`ticket`, `invoice`, `customer`,
     *                      `lead`, `estimate`, `inventory`, `appointment`,
     *                      `expense`, `sms`, `notification`). Only values
     *                      that pass FcmService's ALLOWED_ENTITY_TYPES reach
     *                      us, but we re-validate here via the exhaustive
     *                      `when` so an unexpected value maps to null rather
     *                      than an unknown route.
     *   - `entity_id`    — numeric primary key for detail-capable types.
     *
     * For entity types that don't have a dedicated detail screen on Android
     * yet (`appointment`, `expense`, `sms`) we fall back to the list route
     * so the user at least lands in the right section instead of the
     * dashboard. Returns null if the intent isn't an FCM tap or the type
     * is unknown — the caller falls through to the default start
     * destination.
     */
    private fun resolveFcmRoute(intent: Intent?): String? {
        if (intent == null) return null
        val entityType = intent.getStringExtra("navigate_to") ?: return null
        val entityId = intent.getStringExtra("entity_id")?.toLongOrNull()

        return when (entityType) {
            "ticket"       -> entityId?.let { "tickets/$it" }
            "invoice"      -> entityId?.let { "invoices/$it" }
            "customer"     -> entityId?.let { "customers/$it" }
            "lead"         -> entityId?.let { "leads/$it" }
            "estimate"     -> entityId?.let { "estimates/$it" }
            "inventory"    -> entityId?.let { "inventory/$it" }
            // Appointments and expenses don't have a detail route on Android
            // yet, so land the user on the list where they can locate the
            // referenced record themselves rather than the dashboard.
            "appointment"  -> "appointments"
            "expense"      -> "expenses"
            // FCM `sms` payloads send a message id in entity_id, but the SMS
            // thread route keys by phone number. Landing on the inbox is the
            // closest we can get without a phone-number extra from the
            // server.
            "sms"          -> "messages"
            "notification" -> "notifications"
            else           -> null
        }
    }

    companion object {
        /**
         * Closed set of routes any external caller can jump to via
         * `bizarrecrm://<route>`. Must stay in sync with the shortcuts.xml
         * entries and any launcher shortcut / App Actions capability. New
         * routes should only be added here after the nav graph is confirmed
         * to handle them safely without trusting any caller-supplied data.
         */
        // Historical allow-list moved to [com.bizarreelectronics.crm.util.DeepLinkAllowlist]
        // so it can be unit-tested without touching Activity lifecycle.
    }
}
