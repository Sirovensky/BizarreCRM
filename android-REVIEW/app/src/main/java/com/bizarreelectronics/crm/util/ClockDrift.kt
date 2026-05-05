package com.bizarreelectronics.crm.util

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.time.Instant
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Tracks the difference between the device clock and the CRM server clock.
 *
 * The drift is calculated as:
 *   driftMs = serverEpochMs - System.currentTimeMillis()
 *
 * A positive drift means the server clock is ahead of the device; negative
 * means the device is ahead. For most downstream consumers (TOTP, audit
 * timestamps) only the magnitude matters, so the sign is retained but
 * callers that just need the magnitude should use abs(driftMs).
 *
 * Thread safety: MutableStateFlow.value writes are atomic and visible across
 * threads. No additional synchronisation is required.
 */
@Singleton
class ClockDrift @Inject constructor() {

    /**
     * Snapshot of the current drift measurement.
     *
     * @param driftMs Signed offset in milliseconds (server – device). Zero
     *   until the first server Date header has been observed.
     * @param warnThresholdCrossed True when |driftMs| exceeds [WARN_DRIFT_MS].
     *   UI agents should surface a banner to the user when this is true.
     * @param serverTimeAvailable False until at least one server Date header
     *   has been successfully parsed and recorded.
     */
    data class State(
        val driftMs: Long,
        val warnThresholdCrossed: Boolean,
        val serverTimeAvailable: Boolean,
    )

    /**
     * Timestamps for a pending (offline) operation, pairing the device clock
     * reading at the moment of creation with the epoch at which the app first
     * went offline (if known).
     *
     * Both values are device-clock milliseconds. Callers can correct for drift
     * via [toAuditTimestamp] once server time becomes available again.
     *
     * @param deviceMs  System.currentTimeMillis() at the moment of the pending op.
     * @param offlineSinceMs  System.currentTimeMillis() captured when the app
     *   detected it was offline, or null if that information is not available.
     */
    data class PendingOpTimestamps(
        val deviceMs: Long,
        val offlineSinceMs: Long?,
    )

    private val _state = MutableStateFlow(State(driftMs = 0L, warnThresholdCrossed = false, serverTimeAvailable = false))

    /** Publicly exposed as a read-only StateFlow so collectors cannot mutate state. */
    val state: StateFlow<State> = _state.asStateFlow()

    /**
     * Called by [ClockDriftInterceptor] whenever a response carries a `Date`
     * header. Updates the internal drift and re-evaluates the warning threshold.
     *
     * @param serverEpochMs The server time in milliseconds since the Unix epoch,
     *   as parsed from the HTTP `Date` response header.
     */
    fun recordServerDate(serverEpochMs: Long) {
        val deviceMs = System.currentTimeMillis()
        val drift = serverEpochMs - deviceMs
        _state.value = State(
            driftMs = drift,
            warnThresholdCrossed = Math.abs(drift) > WARN_DRIFT_MS,
            serverTimeAvailable = true,
        )
    }

    /**
     * Returns true when the drift is small enough that a TOTP token generated
     * by the device will be accepted by the server.
     *
     * TOTP window is ±30 seconds in most implementations. We use the full
     * 30-second constant (not half) because servers often accept one window
     * ahead and one window behind, making the effective tolerance 60 seconds.
     * Treating the 30-second mark as the cut-off gives us a conservative
     * safety margin.
     *
     * If no server time has been observed yet, returns true (optimistic default:
     * don't block 2FA before we have evidence of a problem).
     */
    fun isSafeFor2FA(): Boolean {
        val s = _state.value
        if (!s.serverTimeAvailable) return true
        return Math.abs(s.driftMs) < TOTP_DRIFT_MS
    }

    /**
     * Returns an [Instant] representing the best-known absolute time for an
     * event that was originally timestamped on the device at [localMs].
     *
     * If server time is available, the current drift is applied. If no server
     * contact has been made (e.g. fully offline), the device timestamp is
     * returned unchanged.
     *
     * @param localMs  A device-clock reading in epoch milliseconds (e.g. the
     *   value of System.currentTimeMillis() at event time).
     */
    fun toAuditTimestamp(localMs: Long): Instant {
        val drift = if (_state.value.serverTimeAvailable) _state.value.driftMs else 0L
        return Instant.ofEpochMilli(localMs + drift)
    }

    /**
     * Packages device-clock timestamps for a pending offline operation so
     * that the caller can attach correct audit timestamps once back online.
     *
     * @param deviceMs       System.currentTimeMillis() at the moment the operation was created.
     * @param offlineSinceMs System.currentTimeMillis() when the app last detected it was offline,
     *   or null if not available.
     */
    fun recordPendingOp(deviceMs: Long, offlineSinceMs: Long?): PendingOpTimestamps =
        PendingOpTimestamps(deviceMs = deviceMs, offlineSinceMs = offlineSinceMs)

    companion object {
        /** Drift threshold above which the app shows a clock-warning banner (2 minutes). */
        const val WARN_DRIFT_MS = 2 * 60 * 1000L

        /**
         * Drift threshold above which TOTP codes are likely to be rejected by
         * the server (30 seconds — one TOTP window).
         */
        const val TOTP_DRIFT_MS = 30 * 1000L
    }
}
