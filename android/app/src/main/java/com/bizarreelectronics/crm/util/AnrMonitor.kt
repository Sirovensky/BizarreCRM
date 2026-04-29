package com.bizarreelectronics.crm.util

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import dagger.hilt.android.qualifiers.ApplicationContext
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

/**
 * §32.8 — Samples ANR exit reasons from [ActivityManager.getHistoricalProcessExitReasons]
 * (available on API 30+; minSdk=26 so the call is version-gated).
 *
 * Called once on cold-start (from [BizarreCrmApp.onCreate]) so we catch any
 * ANR that occurred in the previous process life-cycle before this launch.
 *
 * Sovereignty: no data leaves the device from this class.
 * Upload to the tenant server is deferred until §32.2 TelemetryClient lands
 * (see NOTE-defer annotation on §32.8 in ActionPlan.md).
 *
 * Thread-safety: [sample] does synchronous I/O on whatever thread calls it.
 * BizarreCrmApp calls it on the main thread early in onCreate; the work is
 * fast (O(N) where N is the number of exit records kept by the OS, typically ≤ 16).
 */
@Singleton
class AnrMonitor @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    /**
     * Reads recent process exit reasons and logs any ANR entries through Timber
     * (which is wrapped in [RedactorTree] and [ReleaseTree] at this point so
     * log lines are already redacted + placed in the ring buffer).
     *
     * No-op on API < 30.
     */
    fun sample() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return

        val am = context.getSystemService(ActivityManager::class.java) ?: return

        val reasons = runCatching {
            am.getHistoricalProcessExitReasons(context.packageName, 0, MAX_REASONS)
        }.getOrElse { t ->
            Timber.w(t, "AnrMonitor: failed to read process exit reasons")
            return
        }

        val anrs = reasons.filter { it.reason == ApplicationExitInfo.REASON_ANR }
        if (anrs.isEmpty()) return

        Timber.w("AnrMonitor: %d ANR(s) detected in previous session(s)", anrs.size)
        anrs.forEach { info ->
            Timber.w(
                "AnrMonitor: ANR pid=%d importance=%d desc=%s",
                info.pid,
                info.importance,
                info.description ?: "(no description)",
            )
            // §32.8 — trace input stream would give a full ANR trace but
            // parsing it inline on the main thread is too slow. Log the
            // summary for now; full trace extraction deferred to §32.2 upload.
        }
    }

    private companion object {
        /** How many most-recent exit records to request from the OS. */
        private const val MAX_REASONS = 16
    }
}
