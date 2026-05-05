package com.bizarreelectronics.crm.util

import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Device-local session-timeout policy (§2.16, lines 394-403).
 *
 * **Sovereignty (line 403):** All idle detection is purely client-side.
 * The server is never queried for session-expiry decisions. The device alone
 * tracks user activity and drives re-auth prompts. This preserves
 * data-sovereignty and works fully offline.
 *
 * ## Activity signals (line 397)
 * Only explicit user interactions count: touch events, scrolls, and text entry
 * forwarded via [onActivity]. Silent push notifications and background sync
 * workers MUST NOT call [onActivity] — they run without the user's awareness
 * and must not silently extend a session (line 398).
 *
 * ## Threshold levels (defaults; configurable via [Config], line 402)
 * - Biometric re-auth after 15 minutes of inactivity (line 394).
 * - Full-password re-auth after 4 hours of inactivity (line 395).
 * - Full re-auth including email after 30 days of inactivity (line 396).
 *
 * ## Warning window (lines 399-400)
 * A 60-second countdown fires before the biometric threshold.
 * [State.warningRemainingMs] carries the remaining countdown millis (null when
 * no warning is active). The "Still there?" overlay and countdown ring
 * composables are left for a later wave — consumers observe [state] and render
 * accordingly.
 *
 * ## Sensitive screens (line 401)
 * [requireReAuthNow] forces an immediate level change. The UI layer observes
 * [state] and navigates to the appropriate auth screen. Composable wiring is
 * left for a later wave.
 */
@Singleton
class SessionTimeout @Inject constructor(
    @Suppress("UNUSED_PARAMETER") appPreferences: AppPreferences,
    authPreferences: AuthPreferences,
) : SessionTimeoutCore(
    nowMs = System::currentTimeMillis,
    isLoggedIn = authPreferences::isLoggedIn,
) {
    companion object
}

/**
 * Testable core of [SessionTimeout].
 *
 * Separated from the Hilt-injected shell so that unit tests can supply
 * a fake clock ([nowMs]) and a fake auth predicate ([isLoggedIn]) without
 * requiring an Android [android.content.Context].
 *
 * Production code should use [SessionTimeout] directly; tests should use
 * [SessionTimeout.forTest].
 */
open class SessionTimeoutCore(
    internal val nowMs: () -> Long,
    private val isLoggedIn: () -> Boolean,
) {

    // -------------------------------------------------------------------------
    // Config — tenant-configurable thresholds (line 402)
    // -------------------------------------------------------------------------

    /**
     * Threshold configuration. Values may be overridden by tenant admin via
     * [AppPreferences] after a settings sync. Global min/max constraints are
     * enforced in [init] to prevent misconfiguration — fail fast at construction.
     *
     * Constraints:
     *   - [biometricAfterMs] in [[MIN_BIOMETRIC_MS]..[fullAuthAfterMs]]
     *   - [passwordAfterMs] in [[biometricAfterMs]..[fullAuthAfterMs]]
     *   - [fullAuthAfterMs] <= [MAX_FULL_AUTH_MS] (30 days)
     *   - [warningLeadMs] in (0..[biometricAfterMs]]
     */
    data class Config(
        val biometricAfterMs: Long = 15L * 60_000L,
        val passwordAfterMs: Long = 4L * 60L * 60_000L,
        val fullAuthAfterMs: Long = 30L * 24L * 60L * 60_000L,
        val warningLeadMs: Long = 60_000L,
    ) {
        init {
            require(biometricAfterMs >= MIN_BIOMETRIC_MS) {
                "biometricAfterMs ($biometricAfterMs) must be >= $MIN_BIOMETRIC_MS (1 min)"
            }
            require(biometricAfterMs <= fullAuthAfterMs) {
                "biometricAfterMs ($biometricAfterMs) must be <= fullAuthAfterMs ($fullAuthAfterMs)"
            }
            require(passwordAfterMs >= biometricAfterMs) {
                "passwordAfterMs ($passwordAfterMs) must be >= biometricAfterMs ($biometricAfterMs)"
            }
            require(passwordAfterMs <= fullAuthAfterMs) {
                "passwordAfterMs ($passwordAfterMs) must be <= fullAuthAfterMs ($fullAuthAfterMs)"
            }
            require(fullAuthAfterMs <= MAX_FULL_AUTH_MS) {
                "fullAuthAfterMs ($fullAuthAfterMs) must be <= $MAX_FULL_AUTH_MS (30 days)"
            }
            require(warningLeadMs > 0L) {
                "warningLeadMs must be > 0"
            }
            require(warningLeadMs <= biometricAfterMs) {
                "warningLeadMs ($warningLeadMs) must be <= biometricAfterMs ($biometricAfterMs)"
            }
        }

        companion object {
            // Mirrors the constants on SessionTimeoutCore.Companion so Config.init
            // can reference them without needing access to the outer class.
            const val MIN_BIOMETRIC_MS = 60_000L
            const val MAX_FULL_AUTH_MS = 30L * 24L * 60L * 60_000L
        }
    }

    // -------------------------------------------------------------------------
    // Re-auth level
    // -------------------------------------------------------------------------

    /** Level of re-authentication required, in ascending severity order. */
    sealed class ReAuthLevel {
        /** No re-auth needed — session is within its active window. */
        object None : ReAuthLevel()

        /** Biometric (fingerprint / face) prompt is sufficient (line 394). */
        object Biometric : ReAuthLevel()

        /** Full password required — biometric alone is not sufficient (line 395). */
        object Password : ReAuthLevel()

        /**
         * Full re-auth including email verification required (line 396).
         * Triggered after 30 days of inactivity.
         */
        object Full : ReAuthLevel()
    }

    // -------------------------------------------------------------------------
    // Emitted state
    // -------------------------------------------------------------------------

    /**
     * Immutable snapshot emitted by [state].
     *
     * @param level              Current re-auth requirement.
     * @param lastActivityMs     Device epoch-ms of the most recent user activity.
     * @param warningRemainingMs Countdown millis before the biometric threshold
     *   (line 400). Non-null only during the warning window. Consumers render a
     *   countdown ring from this value. Null when outside the window.
     */
    data class State(
        val level: ReAuthLevel = ReAuthLevel.None,
        val lastActivityMs: Long = 0L,
        val warningRemainingMs: Long? = null,
    )

    // -------------------------------------------------------------------------
    // Internal state
    // -------------------------------------------------------------------------

    private val _state = MutableStateFlow(State(lastActivityMs = nowMs()))

    /** Read-only state flow for UI consumers. */
    val state: StateFlow<State> = _state.asStateFlow()

    /**
     * Active config. Exposed as [open] so test subclasses can supply a custom
     * [Config] with shorter thresholds.
     *
     * AppPreferences does not currently expose session-timeout overrides;
     * conservative built-in defaults apply. Tenant-configurable thresholds are
     * wired in a future settings-sync wave (line 402).
     */
    open val config: Config = Config()

    private val tickerScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var tickerJob: Job? = null

    init {
        startTicker()
    }

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------

    /**
     * Records a user-originated activity event (touch, scroll, text entry).
     *
     * This is the **only** entry point that resets the inactivity timer. It
     * must exclusively be called from user-interaction dispatch paths — never
     * from background workers, FCM handlers, or sync routines (line 398).
     */
    fun onActivity() {
        _state.value = _state.value.copy(
            level = ReAuthLevel.None,
            lastActivityMs = nowMs(),
            warningRemainingMs = null,
        )
    }

    /**
     * Called by [com.bizarreelectronics.crm.BizarreCrmApp]'s
     * ProcessLifecycleOwner observer on ON_START.
     * Resumes the inactivity ticker after the app returns to the foreground.
     */
    fun onAppForeground() {
        if (tickerJob?.isActive != true) {
            startTicker()
        }
    }

    /**
     * Called by [com.bizarreelectronics.crm.BizarreCrmApp]'s
     * ProcessLifecycleOwner observer on ON_STOP.
     *
     * Background time deliberately accumulates in the inactivity window —
     * the last-activity timestamp is not updated here. The ticker continues
     * evaluating elapsed time from the last [onActivity] call.
     */
    fun onAppBackground() {
        // Intentional no-op. Background elapsed time counts toward inactivity.
    }

    /**
     * Forces immediate re-auth at [level], bypassing the inactivity timer.
     *
     * Call from sensitive screen entry points (payment terminal, GDPR export,
     * employee management). The UI layer observes [state] and navigates to the
     * appropriate auth screen. Composable wiring is left for a later wave (line 401).
     *
     * [ReAuthLevel.None] is silently ignored to prevent accidental downgrade.
     */
    fun requireReAuthNow(level: ReAuthLevel) {
        if (level == ReAuthLevel.None) return
        _state.value = _state.value.copy(
            level = level,
            warningRemainingMs = null,
        )
    }

    /**
     * Clears the re-auth requirement after successful authentication.
     *
     * Resets [State.lastActivityMs] to now so the inactivity window restarts.
     */
    fun clear() {
        _state.value = State(
            level = ReAuthLevel.None,
            lastActivityMs = nowMs(),
            warningRemainingMs = null,
        )
    }

    // -------------------------------------------------------------------------
    // Internal ticker
    // -------------------------------------------------------------------------

    private fun startTicker() {
        tickerJob?.cancel()
        tickerJob = tickerScope.launch {
            while (isActive) {
                tick()
                delay(TICK_INTERVAL_MS)
            }
        }
    }

    /**
     * Evaluates idle time and emits a new [State]. Called by the background
     * ticker every [TICK_INTERVAL_MS] ms; also directly callable from unit tests
     * to drive state changes synchronously without waiting for coroutines.
     */
    internal fun tick() {
        if (!isLoggedIn()) return

        val elapsedMs = nowMs() - _state.value.lastActivityMs

        val newLevel: ReAuthLevel = when {
            elapsedMs >= config.fullAuthAfterMs  -> ReAuthLevel.Full
            elapsedMs >= config.passwordAfterMs  -> ReAuthLevel.Password
            elapsedMs >= config.biometricAfterMs -> ReAuthLevel.Biometric
            else                                 -> ReAuthLevel.None
        }

        // Warning window: [biometricAfterMs - warningLeadMs, biometricAfterMs).
        // warningRemainingMs is non-null only when still in None territory but
        // past the warning start (lines 399-400).
        val warningStart = config.biometricAfterMs - config.warningLeadMs
        val warningRemainingMs: Long? = when {
            newLevel != ReAuthLevel.None -> null
            elapsedMs >= warningStart    -> (config.biometricAfterMs - elapsedMs).coerceAtLeast(0L)
            else                         -> null
        }

        _state.value = _state.value.copy(
            level = newLevel,
            warningRemainingMs = warningRemainingMs,
        )
    }

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    companion object {
        /** How often the ticker evaluates idle state. */
        internal const val TICK_INTERVAL_MS = 1_000L

        /** Global minimum biometric threshold (1 minute). */
        const val MIN_BIOMETRIC_MS = 60_000L

        /** Global maximum full-auth threshold (30 days). */
        const val MAX_FULL_AUTH_MS = 30L * 24L * 60L * 60_000L
    }
}

// -------------------------------------------------------------------------
// Test factory — file-level extension outside the Hilt component graph
// -------------------------------------------------------------------------

/**
 * Creates a [SessionTimeoutCore] with a controlled clock and auth predicate
 * for JVM unit tests. Bypasses Android Context entirely.
 *
 * Accessed via `SessionTimeout.forTest(...)` in tests.
 *
 * @param isLoggedIn Predicate controlling the simulated auth state.
 * @param nowMs      Clock provider — advance this to simulate elapsed time.
 * @param config     Optional [SessionTimeoutCore.Config] override.
 */
fun SessionTimeout.Companion.forTest(
    isLoggedIn: Boolean,
    nowMs: () -> Long,
    config: SessionTimeoutCore.Config = SessionTimeoutCore.Config(),
): SessionTimeoutCore = SessionTimeoutCore.forTest(
    isLoggedIn = isLoggedIn,
    nowMs = nowMs,
    config = config,
)

/**
 * Internal factory on [SessionTimeoutCore.Companion] that actually builds the
 * test instance. The [SessionTimeout.Companion] extension above delegates here
 * so callers can use the familiar [SessionTimeout.forTest] spelling.
 */
fun SessionTimeoutCore.Companion.forTest(
    isLoggedIn: Boolean,
    nowMs: () -> Long,
    config: SessionTimeoutCore.Config = SessionTimeoutCore.Config(),
): SessionTimeoutCore = object : SessionTimeoutCore(
    nowMs = nowMs,
    isLoggedIn = { isLoggedIn },
) {
    override val config: SessionTimeoutCore.Config = config
}
