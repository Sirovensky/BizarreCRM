package com.bizarreelectronics.crm

import android.app.assist.AssistContent
import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.Display
import android.view.MotionEvent
import android.view.WindowManager
import org.json.JSONObject
import timber.log.Timber
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.MutableState
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
import com.bizarreelectronics.crm.data.local.prefs.TrainingPreferences
import com.bizarreelectronics.crm.data.sync.SyncManager
import com.bizarreelectronics.crm.ui.auth.BiometricAuth
import com.bizarreelectronics.crm.ui.auth.PinLockScreen
import com.bizarreelectronics.crm.ui.navigation.AppNavGraph
import com.bizarreelectronics.crm.ui.theme.BizarreCrmTheme
import com.bizarreelectronics.crm.ui.theme.DashboardDensity
import com.bizarreelectronics.crm.ui.theme.LocalDashboardDensity
import com.bizarreelectronics.crm.ui.theme.shouldDefaultDarkMode
import com.bizarreelectronics.crm.util.ClockDrift
import com.bizarreelectronics.crm.util.DeepLinkBus
import com.bizarreelectronics.crm.util.RateLimiter
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import com.bizarreelectronics.crm.util.SessionTimeout
import com.bizarreelectronics.crm.util.SessionTimeoutCore
import com.bizarreelectronics.crm.util.rememberNotificationPermission
import com.bizarreelectronics.crm.util.LanguageManager
import com.bizarreelectronics.crm.ui.components.ForceUpgradeBlocker
import com.bizarreelectronics.crm.util.LockScreenBlurHelper
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

    // §53.1 — injected so AppNavGraph can drive the training-mode banner.
    @Inject
    lateinit var trainingPreferences: TrainingPreferences

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

    /**
     * §1.7 line 238 — activity-level lock state, readable by both the Compose
     * tree and [onResume]. Promoted from a local `remember { mutableStateOf }` so
     * that [onResume] can set it to `true` when the inactivity threshold has
     * elapsed, causing the Compose scaffold to re-render the biometric prompt
     * without duplicating any logic inside the composition.
     *
     * Initialized to `false`; [onCreate] overwrites it with the computed
     * `shouldLock` value before [setContent] is called, so the composition
     * always reads the correct initial value.
     */
    private val lockedState: MutableState<Boolean> = mutableStateOf(false)

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

        // AUDIT-AND-011 / §1.7 line 239 — FLAG_SECURE is now driven reactively by
        // AppPreferences.screenCapturePreventionFlow so the user can toggle it
        // from Settings without an activity recreate.
        //
        // Applied once eagerly here (before setContent) to guarantee no single
        // Compose frame is ever rendered without the flag when the pref is ON.
        // The Compose collector below then keeps the flag in sync on every pref
        // change. BuildConfig.DEBUG bypass: when the pref is false AND the build
        // is a debug build the flag is not set, allowing QA screencaps. In all
        // release builds the flag follows the pref exactly.
        val screenCapturePrevEnabled = appPreferences.screenCapturePreventionEnabled
        if (screenCapturePrevEnabled || !BuildConfig.DEBUG) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        // §2.13: Android 12+ setRecentsScreenshotEnabled — belt-and-suspenders on
        // top of FLAG_SECURE. Follows the same pref so both surfaces stay in sync.
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            setRecentsScreenshotEnabled(!(screenCapturePrevEnabled || !BuildConfig.DEBUG))
        }
        enableEdgeToEdge()
        // §29.2 — Opt into the highest available refresh rate (120 Hz on
        // Pixel 6a / 7 / 8; 60 Hz fallback on older devices).
        //
        // Approach: set Window.preferredDisplayModeId to the mode with the
        // highest refresh rate supported by the current display that matches
        // the active physical resolution. All candidate modes share the same
        // physicalWidth × physicalHeight as the current mode, so the switch
        // does not trigger a resolution change / black flash.
        //
        // Activity.display is available on API 30+ (Android 11).  We also
        // accept API 23's Display.getSupportedModes() which is gated on
        // Build.VERSION_CODES.M. The preferredDisplayModeId field was added
        // to LayoutParams in API 23 as well, so the whole block is safe from
        // API 23 onward.
        @Suppress("DEPRECATION")
        val currentDisplay: android.view.Display? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display
        } else {
            (getSystemService(Context.WINDOW_SERVICE) as WindowManager).defaultDisplay
        }
        if (currentDisplay != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val currentMode = currentDisplay.mode
            val bestMode = currentDisplay.supportedModes
                .filter { it.physicalWidth == currentMode.physicalWidth &&
                          it.physicalHeight == currentMode.physicalHeight }
                .maxByOrNull { it.refreshRate }
            if (bestMode != null && bestMode.modeId != currentMode.modeId) {
                window.attributes = window.attributes.also { params ->
                    params.preferredDisplayModeId = bestMode.modeId
                }
            }
        }
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
        // §25.2 — inbound share (ACTION_SEND / ACTION_SEND_MULTIPLE) is checked
        // first; if it matches, resolveInboundShare() publishes to the dedicated
        // DeepLinkBus.pendingInboundShare slot (not the route bus) and returns
        // true, skipping the standard deep-link / FCM resolution path.
        if (!resolveInboundShare(intent)) {
            pendingDeepLink = resolveDeepLink(intent) ?: resolveFcmRoute(intent)
            deepLinkBus.publish(pendingDeepLink)
        }

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
        lockedState.value = shouldLock

        // LOGIN-MOCK-217 — Warn when an external Presentation display is connected
        // at launch time. FLAG_SECURE suppresses screencap but does not prevent the
        // Presentation API from mirroring content to a connected secondary display
        // (e.g. Miracast, USB-C HDMI, ChromeCast). We log a warning + breadcrumb so
        // the issue surfaces in crash reports. Full UX enforcement (blocking login
        // while a display is connected) requires a product decision and is deferred.
        val displayManager = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        val presentationDisplays = displayManager.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION)
        if (presentationDisplays.isNotEmpty()) {
            Timber.w(
                "LOGIN-MOCK-217: %d external Presentation display(s) connected at launch — " +
                "FLAG_SECURE does not block Presentation API mirroring. " +
                "Displays: %s",
                presentationDisplays.size,
                presentationDisplays.joinToString { it.name },
            )
            breadcrumbs.log(
                "security",
                "external_display_at_launch: ${presentationDisplays.size} display(s)",
            )
        }

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
                // §30.8 — "system" mode: follow OS dark preference first;
                // if the OS is not in dark mode, fall back to the 7pm–7am
                // auto-schedule so the app defaults dark in the evening even
                // on devices where the user hasn't enabled system dark mode.
                else    -> systemDark || shouldDefaultDarkMode()
            }

            // §1.7 line 239 — reactive FLAG_SECURE: observe the pref flow so
            // the flag is added or cleared whenever the user changes the
            // screen-capture prevention setting. The eager apply in onCreate
            // guarantees the flag is set before the first frame; this collector
            // keeps it in sync on subsequent pref changes.
            //
            // BuildConfig.DEBUG bypass: when pref=false AND debug build, clear
            // the flag (QA screenshots). In all other cases follow the pref.
            val screenCapturePrev by appPreferences.screenCapturePreventionFlow.collectAsState(
                initial = appPreferences.screenCapturePreventionEnabled,
            )
            val applySecure = screenCapturePrev || !BuildConfig.DEBUG
            if (applySecure) {
                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                    setRecentsScreenshotEnabled(false)
                }
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                    setRecentsScreenshotEnabled(true)
                }
            }

            // §3.19 L613 — observe dashboardDensityFlow so LocalDashboardDensity
            // updates reactively whenever the user changes the pref on AppearanceScreen.
            // Shared-device gate: when sharedDeviceModeEnabled = true, always serve
            // Comfortable regardless of the persisted preference so every staff
            // member on the kiosk sees the same predictable layout.
            val rawDensity by appPreferences.dashboardDensityFlow.collectAsState(
                initial = appPreferences.dashboardDensity,
            )
            val sharedDeviceMode by appPreferences.sharedDeviceModeFlow.collectAsState(
                initial = appPreferences.sharedDeviceModeEnabled,
            )
            val dashboardDensity = if (sharedDeviceMode) DashboardDensity.Comfortable else rawDensity

            CompositionLocalProvider(LocalDashboardDensity provides dashboardDensity) {
            BizarreCrmTheme(darkTheme = darkTheme, dynamicColor = dynamicColor) {
            // §28.9 — Force-upgrade blocker: blocks the UI when the server reports a
            // min_supported_version higher than the installed app version code.
            // serverMinVersion is populated from GET /auth/me; null = no floor enforced.
            ForceUpgradeBlocker(serverMinVersion = authPreferences.serverMinVersion) {
                // §1.7 line 238 — lock state is owned by lockedState (Activity level)
                // so onResume can set it to true when the inactivity threshold has
                // elapsed, causing the biometric prompt to re-appear without any
                // logic duplication inside the composition.
                var locked by lockedState
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
                        // §2.15 L387 — "Forgot PIN?" lifts the PIN gate and
                        // publishes the ForgotPin route into the nav bus so
                        // AppNavGraph lands the user on the forgot-pin screen
                        // immediately after the gate clears.
                        onForgotPin = {
                            pinGated = false
                            deepLinkBus.publish(
                                com.bizarreelectronics.crm.ui.navigation.Screen.ForgotPin.route,
                            )
                        },
                    )
                } else {
                    // LOGIN-MOCK-214: gate POST_NOTIFICATIONS permission prompt on auth state so
                    // the system dialog never fires on the pre-login / setup screens.
                    // §13.2: prompt for POST_NOTIFICATIONS on first unlock
                    // (Android 13+ only — pre-T the permission didn't exist).
                    // Runs here so it never fires behind the lock screen.
                    val isAuthenticated by authPreferences.isLoggedInFlow.collectAsState()
                    if (isAuthenticated) {
                        rememberNotificationPermission(autoRequest = true)
                    }
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
                        // §53.1 — drives the training-mode banner above the NavHost.
                        trainingPreferences = trainingPreferences,
                    )
                }
            }
            } // end BizarreCrmTheme (ForceUpgradeBlocker + content inside)
            } // end CompositionLocalProvider(LocalDashboardDensity)
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
        // for the ordering rationale. §25.2: inbound share is checked first
        // and dispatched to DeepLinkBus.pendingInboundShare if recognised.
        if (!resolveInboundShare(intent)) {
            pendingDeepLink = resolveDeepLink(intent) ?: resolveFcmRoute(intent)
            deepLinkBus.publish(pendingDeepLink)
        }
    }

    /**
     * §1.7 line 238 — lock-gate re-evaluation on every resume.
     *
     * [SessionTimeout] ticks in the background accumulating inactivity time.
     * When the user returns to the app (e.g. after a phone call, switching tasks,
     * or the screen turning off), the system calls [onResume] before any content
     * is drawn. We check whether the elapsed inactivity has exceeded the biometric
     * threshold and, if so, set [lockedState] to `true`. The Compose scaffold
     * observes [lockedState] and immediately renders [LaunchBiometricPrompt] in
     * the same recomposition — no logic is duplicated inside the composition.
     *
     * Conditions that trigger lock:
     *   - [SessionTimeout.state] level is already [SessionTimeout.ReAuthLevel.Biometric]
     *     or higher (ticker already escalated in the background), OR
     *   - [PinPreferences.shouldLock] returns true (PIN grace window elapsed), OR
     *   - Both biometricEnabled AND canAuthenticate AND the last-activity age
     *     computed locally exceeds the biometric threshold.
     *
     * Idempotent: setting [lockedState] to `true` when it is already `true` is
     * a no-op in Compose (same reference, no recomposition triggered).
     */
    override fun onResume() {
        super.onResume()
        // §28.3 — clear the Gaussian blur that was applied in onPause so the
        // user sees normal content again when returning to the foreground.
        window.decorView.let { LockScreenBlurHelper.clearBlur(it) }

        val timeoutState = sessionTimeout.state.value
        val hasSession = authPreferences.accessToken != null ||
            authPreferences.refreshToken != null

        val shouldLockNow = hasSession && (
            timeoutState.level is SessionTimeoutCore.ReAuthLevel.Biometric ||
            timeoutState.level is SessionTimeoutCore.ReAuthLevel.Password ||
            timeoutState.level is SessionTimeoutCore.ReAuthLevel.Full ||
            pinPreferences.shouldLock() ||
            (appPreferences.biometricEnabled && biometricAuth.canAuthenticate(this) &&
                timeoutState.level !is SessionTimeoutCore.ReAuthLevel.None)
        )

        if (shouldLockNow) {
            lockedState.value = true
        }
    }

    /**
     * §28.3 — Apply Gaussian blur to the root decor view when the app moves to
     * the background (Recents / lock screen preview). This prevents PII visible
     * on ticket-detail or customer screens from leaking into the Recents
     * thumbnail on Android 12+ devices (API 31+). On older devices FLAG_SECURE
     * already suppresses the thumbnail; [LockScreenBlurHelper.applyBlur] is a
     * no-op below API 31 so the call is safe on all API levels.
     */
    override fun onPause() {
        super.onPause()
        window.decorView.let { LockScreenBlurHelper.applyBlur(it) }
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
     *  - An HTTPS App Link URI (reset-password, setup-token invite)
     *  - The Quick Settings tile action
     * Returns null if the intent doesn't carry a recognised route.
     *
     * SECURITY: the deep-link intent filter is exported (any app on the
     * device can fire `bizarrecrm://...`), so we whitelist allowed routes
     * instead of echoing whatever host/path the caller passes in. A route
     * that isn't on [com.bizarreelectronics.crm.util.DeepLinkAllowlist] is
     * dropped silently — the nav graph just lands the user on the dashboard.
     */
    private fun resolveDeepLink(intent: Intent?): String? {
        if (intent == null) return null
        if (intent.action == com.bizarreelectronics.crm.service.QuickTicketTileService
                .ACTION_NEW_TICKET_FROM_TILE) {
            return "ticket/new"
        }
        val data: Uri = intent.data ?: return null

        // §2.7 L330 — HTTPS App Link: https://bizarrecrm.com/setup/<token>
        //             or              https://app.bizarrecrm.com/setup/<token>
        // §2.21 L454 — HTTPS App Link: https://app.bizarrecrm.com/magic/<token>
        // Host is validated against a hard-coded set — we never echo
        // attacker-supplied hosts. Token is validated via DeepLinkAllowlist.
        if (data.scheme == "https") {
            val host = data.host?.lowercase() ?: return null
            val allowedSetupHosts = setOf("bizarrecrm.com", "app.bizarrecrm.com")
            if (host in allowedSetupHosts) {
                val segments = data.pathSegments
                if (segments.size == 2 && segments[0] == "setup") {
                    val rawToken = segments[1]
                    val token = com.bizarreelectronics.crm.util.DeepLinkAllowlist
                        .validateSetupToken(rawToken) ?: return null
                    return "login?setupToken=${Uri.encode(token)}"
                }
                // §2.21 L454 — magic-link: https://app.bizarrecrm.com/magic/<token>
                if (segments.size == 2 && segments[0] == "magic") {
                    val rawToken = segments[1]
                    val token = com.bizarreelectronics.crm.util.DeepLinkAllowlist
                        .validateMagicToken(rawToken) ?: return null
                    deepLinkBus.publishMagicLinkToken(token)
                    return null // no nav route — LoginViewModel handles token exchange
                }
            }
            return null
        }

        if (data.scheme != "bizarrecrm") return null

        // §2.20 L446 — SSO callback: bizarrecrm://sso/callback?code=…&state=…
        // Recognised before the generic whitelist check so the query params can
        // be extracted. The result is dispatched via DeepLinkBus.publishSsoResult
        // instead of a nav route — LoginViewModel collects and calls token exchange.
        if (data.host == "sso" && data.path?.trimStart('/') == "callback") {
            val code = data.getQueryParameter("code")
            val state = data.getQueryParameter("state")
            if (!code.isNullOrBlank() && !state.isNullOrBlank()) {
                deepLinkBus.publishSsoResult(code, state)
            }
            return null // no nav route — VM handles the result via pendingSsoResult
        }

        // §2.21 L454 — magic-link custom scheme: bizarrecrm://magic/<token>
        // Recognised before the generic whitelist so the token can be extracted
        // and published to DeepLinkBus.publishMagicLinkToken without forming
        // a nav route. LoginViewModel collects and dispatches the exchange call.
        if (data.host == "magic") {
            val rawToken = data.path?.trimStart('/').orEmpty()
            val token = com.bizarreelectronics.crm.util.DeepLinkAllowlist
                .validateMagicToken(rawToken) ?: return null
            deepLinkBus.publishMagicLinkToken(token)
            return null // no nav route — VM handles the token via pendingMagicToken
        }

        // §2.15 L387-L388 — forgot-PIN reset link: bizarrecrm://forgot-pin/<token>
        // Recognised before the generic whitelist. ForgotPinViewModel collects
        // [DeepLinkBus.pendingForgotPinToken] and advances to the SettingPin state.
        if (data.host == "forgot-pin") {
            val rawToken = data.path?.trimStart('/').orEmpty()
            val token = com.bizarreelectronics.crm.util.DeepLinkAllowlist
                .validateForgotPinToken(rawToken) ?: return null
            deepLinkBus.publishForgotPinToken(token)
            return null // no nav route — ForgotPinViewModel handles via pendingForgotPinToken
        }

        // Normalise "bizarrecrm://ticket/new" → "ticket/new". We intentionally
        // do NOT include query parameters: a route is just a static path,
        // and the current whitelist has no route that needs arguments.
        // Exception: "bizarrecrm://setup/<token>" is handled by DeepLinkAllowlist
        // which returns a parametrized "login?setupToken=…" route.
        val host = data.host ?: return null
        val path = data.path?.trimStart('/').orEmpty()
        val candidate = if (path.isEmpty()) host else "$host/$path"

        // §56.4 — Android TV / Leanback launcher fires bizarrecrm://tvqueue.
        // Map the host-only deep link to the TV queue board nav route.
        if (candidate == "tvqueue") {
            return com.bizarreelectronics.crm.ui.navigation.Screen.TvQueueBoard.route
        }

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

    /**
     * Inbound ACTION_SEND / ACTION_SEND_MULTIPLE handler. Publishes a typed
     * event to DeepLinkBus so AppNavGraph can land the user on the
     * "attach to ticket / new note" picker. Returns true when the intent was
     * recognised as a share, false otherwise. The original Intent is read at
     * the call site via [Activity.intent] for the actual content.
     */
    internal fun resolveInboundShare(intent: Intent?): Boolean {
        if (intent == null) return false
        val action = intent.action ?: return false
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return false
        val type = intent.type ?: return false
        val isHandled = type == "text/plain" || type.startsWith("image/") || type == "application/pdf"
        if (!isHandled) return false
        Timber.tag("MainActivity").i("inbound share: action=%s type=%s", action, type)
        deepLinkBus.publishInboundShare(action, type)
        return true
    }

    override fun onProvideAssistContent(outContent: AssistContent) {
        super.onProvideAssistContent(outContent)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val route = pendingDeepLink ?: intent?.data?.toString()
        val (webUrl, structuredData) = buildAssistData(route)
        outContent.webUri = Uri.parse(webUrl)
        runCatching {
            outContent.structuredData = JSONObject(structuredData).toString()
        }.onFailure { e ->
            Timber.tag("MainActivity").w(e, "onProvideAssistContent JSON error")
        }
    }

    /**
     * Pure helper — maps a route string onto a (webUrl, structuredDataJson) pair
     * for [onProvideAssistContent]. JSON is built via JSONObject (not raw string
     * templates) to avoid a known Kotlin compiler parser bug with `$var`-laden
     * triple-quoted strings inside this file.
     */
    internal fun buildAssistData(route: String?): Pair<String, String> {
        val base = "https://app.bizarrecrm.com"
        val obj = JSONObject()
        when {
            route != null && route.startsWith("tickets/") -> {
                val id = route.removePrefix("tickets/").toLongOrNull()
                if (id != null) {
                    obj.put("@type", "Thing")
                    obj.put("@id", "$base/tickets/$id")
                    obj.put("name", "Repair ticket $id")
                    return ("$base/tickets/$id") to obj.toString()
                }
                obj.put("@type", "ItemList"); obj.put("name", "Tickets")
                return ("$base/tickets") to obj.toString()
            }
            route != null && route.startsWith("customers/") -> {
                val id = route.removePrefix("customers/").toLongOrNull()
                if (id != null) {
                    obj.put("@type", "Person")
                    obj.put("@id", "$base/customers/$id")
                    obj.put("identifier", id)
                    return ("$base/customers/$id") to obj.toString()
                }
                obj.put("@type", "ItemList"); obj.put("name", "Customers")
                return ("$base/customers") to obj.toString()
            }
            else -> {
                obj.put("@type", "WebSite"); obj.put("url", "$base/")
                return ("$base/") to obj.toString()
            }
        }
    }

    companion object {
        // Historical allow-list moved to com.bizarreelectronics.crm.util.DeepLinkAllowlist
    }
}
