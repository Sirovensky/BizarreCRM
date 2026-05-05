package com.bizarreelectronics.crm.util

import android.app.Activity
import android.util.Log
import android.view.Window
import androidx.metrics.performance.JankStats
import androidx.metrics.performance.PerformanceMetricsState
import com.bizarreelectronics.crm.BuildConfig
import javax.inject.Inject
import javax.inject.Singleton

/**
 * §29 — JankStats integration.
 *
 * Attached once per Activity (currently MainActivity). Each frame that
 * misses its deadline is logged into Breadcrumbs (CAT_NAV) so a future
 * crash report can tell whether the user was sitting on a janky frame
 * before the crash. Listener also writes to Logcat in debug builds so
 * the dev sees the spike immediately.
 *
 * The `metrics-performance` artifact is the tiny native instrumentation
 * — same primitive Profileable apps use, no third-party telemetry.
 */
@Singleton
class JankReporter @Inject constructor(
    private val breadcrumbs: Breadcrumbs,
) {

    private var stats: JankStats? = null

    /**
     * Hook the current Activity's window. Re-entrant — calling twice for
     * the same Activity simply re-binds; the previous JankStats instance
     * is dropped + GC'd.
     */
    fun attach(activity: Activity) {
        val window: Window = activity.window
        // Tag the metrics state with a coarse "activity" label so any frame
        // events recorded against it are easy to attribute later.
        PerformanceMetricsState.getHolderForHierarchy(window.decorView)
            .state
            ?.putState("activity", activity.localClassName)

        stats = JankStats.createAndTrack(window) { frame ->
            if (!frame.isJank) return@createAndTrack
            val ms = frame.frameDurationUiNanos / 1_000_000
            // Skip noise floor — only crumb anything past 32ms.
            if (ms < 32) return@createAndTrack
            val label = "jank ${ms}ms @ ${frame.states.firstOrNull()?.value ?: "?"}"
            breadcrumbs.log(Breadcrumbs.CAT_NAV, label)
            if (BuildConfig.DEBUG) {
                Log.w(TAG, label)
            }
        }
    }

    private companion object {
        private const val TAG = "JankReporter"
    }
}
