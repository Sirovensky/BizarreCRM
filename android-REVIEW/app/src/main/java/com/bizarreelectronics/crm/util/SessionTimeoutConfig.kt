package com.bizarreelectronics.crm.util

/**
 * Shared-device-mode-aware session timeout configuration (§2.14, ActionPlan L369-L378).
 *
 * ## Contract
 *
 * When shared-device mode is OFF ([sharedDeviceEnabled] = false), this object returns
 * the standard §2.16 defaults (biometric re-auth after 15 minutes, password after 4 hours,
 * full re-auth after 30 days). The existing [SessionTimeout] / [SessionTimeoutCore.Config]
 * defaults are left untouched so single-user flow is unaffected.
 *
 * When shared-device mode is ON, the inactivity threshold collapses to the tenant-configured
 * [inactivityMinutes] value (one of 5 / 10 / 15 / 30 / 240). Exceeding this window forces a
 * lock to the [StaffPickerScreen] — not just a PIN prompt — so the counter/kiosk device
 * presents the full staff avatar grid.
 *
 * ## Allowed inactivity values (minutes)
 * ```
 * 5, 10, 15, 30, 240
 * ```
 * 240 minutes = 4 hours (maps to the §2.16 "password" tier for single-user mode, kept here
 * as the max practical kiosk window). Values outside this set are coerced to the nearest
 * allowed value by [coerceInactivityMinutes].
 *
 * ## Follow-ups
 * - DraftStore must key drafts by `user_id` — schema update required (out of scope here).
 * - POS cart should bind to [AppPreferences.sharedDeviceCurrentUserId]; switch parks the
 *   active cart under that user_id. POS integration tracks this as a separate contract.
 */
object SessionTimeoutConfig {

    /** Allowed inactivity windows (minutes) for shared-device mode. */
    val ALLOWED_INACTIVITY_MINUTES: List<Int> = listOf(5, 10, 15, 30, 240)

    /** Default inactivity window when shared-device mode is first enabled. */
    const val DEFAULT_INACTIVITY_MINUTES: Int = 10

    /**
     * Build a [SessionTimeoutCore.Config] appropriate for the current mode.
     *
     * When [sharedDeviceEnabled] is true, [biometricAfterMs] is set to the tenant-configured
     * [inactivityMinutes] * 60_000. The other thresholds (password / full) are scaled
     * proportionally so they remain strictly greater (required by [Config.init] constraints).
     *
     * When [sharedDeviceEnabled] is false, standard §2.16 defaults are returned.
     */
    fun buildConfig(
        sharedDeviceEnabled: Boolean,
        inactivityMinutes: Int,
    ): SessionTimeoutCore.Config {
        if (!sharedDeviceEnabled) {
            return SessionTimeoutCore.Config() // §2.16 defaults
        }
        val safeMinutes = coerceInactivityMinutes(inactivityMinutes)
        val biometricMs = safeMinutes * 60_000L
        // Password threshold = 2× biometric (min 1 h), capped at 8 h.
        val passwordMs = (biometricMs * 2L).coerceIn(60 * 60_000L, 8L * 60 * 60_000L)
        // Full threshold = password × 3 (min 4 h), capped at 30 days.
        val fullMs = (passwordMs * 3L).coerceIn(4L * 60 * 60_000L, SessionTimeoutCore.MAX_FULL_AUTH_MS)
        // Warning lead = min(60s, biometricMs) — can't exceed biometric threshold.
        val warnMs = minOf(60_000L, biometricMs)
        return SessionTimeoutCore.Config(
            biometricAfterMs = biometricMs,
            passwordAfterMs = passwordMs,
            fullAuthAfterMs = fullMs,
            warningLeadMs = warnMs,
        )
    }

    /**
     * Coerce [minutes] to the nearest value in [ALLOWED_INACTIVITY_MINUTES].
     * Unknown values snap to [DEFAULT_INACTIVITY_MINUTES].
     */
    fun coerceInactivityMinutes(minutes: Int): Int =
        if (minutes in ALLOWED_INACTIVITY_MINUTES) minutes else DEFAULT_INACTIVITY_MINUTES
}
