package com.bizarreelectronics.crm.util

import android.content.Context
import android.provider.Settings
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences

/**
 * §26.4 — Reduce-Motion decision helper.
 *
 * Two independent signals can opt a user out of non-essential animations:
 *   1. The system-wide `Settings.Global.ANIMATOR_DURATION_SCALE` — users set
 *      this to 0 in Developer Options or via "Remove Animations" in
 *      Accessibility settings. When 0, animations are globally disabled.
 *   2. The in-app override `AppPreferences.reduceMotionEnabled`, which wins
 *      regardless of system state (so a user whose OEM hides the system
 *      toggle still has a lever in our Settings screen).
 *
 * Decision logic is split into [decideReduceMotion] (pure, unit-testable)
 * and [isReduceMotion] (plumbing that reads the OS + prefs). Composables
 * should prefer [rememberReduceMotion] so they recompose only once per
 * Context/pref change.
 */
object ReduceMotion {

    /**
     * Pure decision: returns true when callers should skip non-essential
     * animations (fades, slides, shimmer, shake-on-error, etc.).
     *
     * @param userPref in-app Settings toggle. true = force-reduce regardless of OS.
     * @param systemAnimatorScale value of `Settings.Global.ANIMATOR_DURATION_SCALE`.
     *   Treated as 1.0 (animations normal) when unknown.
     */
    fun decideReduceMotion(userPref: Boolean, systemAnimatorScale: Float): Boolean {
        if (userPref) return true
        // Exact 0f comparison mirrors the platform behaviour: the window
        // manager treats any non-zero scale as "play animations, maybe
        // faster", only 0f as "skip".
        return systemAnimatorScale == 0f
    }

    /**
     * Plumbing wrapper — reads the OS setting and user pref then delegates
     * to [decideReduceMotion]. Safe on older devices: the settings lookup
     * defaults to 1.0 when the key is missing.
     */
    fun isReduceMotion(context: Context, appPreferences: AppPreferences): Boolean {
        val scale = runCatching {
            Settings.Global.getFloat(
                context.contentResolver,
                Settings.Global.ANIMATOR_DURATION_SCALE,
                1f,
            )
        }.getOrDefault(1f)
        return decideReduceMotion(appPreferences.reduceMotionEnabled, scale)
    }
}

/**
 * Composable helper. Reads the current state once per composition; callers
 * that toggle the pref at runtime should observe via a state flow instead.
 * For non-essential transitions the single-read snapshot is sufficient.
 */
@Composable
fun rememberReduceMotion(appPreferences: AppPreferences): Boolean {
    val context = LocalContext.current
    return remember(context, appPreferences.reduceMotionEnabled) {
        ReduceMotion.isReduceMotion(context, appPreferences)
    }
}
