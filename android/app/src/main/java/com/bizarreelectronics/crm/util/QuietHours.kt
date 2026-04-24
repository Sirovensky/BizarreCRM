package com.bizarreelectronics.crm.util

import android.app.NotificationManager
import android.content.Context
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import java.time.LocalTime
import javax.inject.Inject
import javax.inject.Singleton

/**
 * §13.2 / §13 L1593 — quiet-hours + system DND decision helper.
 *
 * Single source of truth for "should this push be silenced?" so FcmService,
 * in-app banners, and any future scheduled notification path all agree.
 *
 * Behavior (evaluated in order — first true wins):
 *   1. If the channel is in [AppPreferences.criticalChannelIds] → never silence
 *      (critical alerts bypass both quiet-hours and system DND).
 *   2. §13 L1593 — System DND: if the device interruption filter is anything
 *      other than [NotificationManager.INTERRUPTION_FILTER_ALL], return true.
 *      This respects the user's system-wide Do-Not-Disturb setting without
 *      requiring the app to re-implement DND logic itself.
 *   3. §13.2 — App quiet-hours: if `quietHoursEnabled == true` and the current
 *      time falls inside the configured window, return true.
 *   4. Otherwise return false.
 *
 * The two-argument overload [shouldSilence(channelId, now)] is kept for
 * unit-testability (no Context / system call needed).  The three-argument
 * overload [shouldSilence(context, channelId, now)] adds the system DND check.
 */
@Singleton
class QuietHours @Inject constructor(
    private val appPreferences: AppPreferences,
) {

    /**
     * Pure time-based check (no system DND). Suitable for unit tests and
     * contexts where a [Context] is unavailable.
     *
     * @param channelId Channel being evaluated.
     * @param now       Current wall-clock time; defaults to [LocalTime.now].
     * @return `true` if the notification should be silenced.
     */
    fun shouldSilence(channelId: String, now: LocalTime = LocalTime.now()): Boolean {
        if (channelId in appPreferences.criticalChannelIds) return false
        if (!appPreferences.quietHoursEnabled) return false
        return inQuietWindow(now)
    }

    /**
     * §13 L1593 — Full check including system DND state.
     *
     * Silences the notification when either the system DND is active OR the
     * app quiet-hours window covers the current time.  Critical channels are
     * exempt from both.
     *
     * DND states that trigger silencing:
     *   - [NotificationManager.INTERRUPTION_FILTER_NONE]        (total silence)
     *   - [NotificationManager.INTERRUPTION_FILTER_PRIORITY]    (priority only)
     *   - [NotificationManager.INTERRUPTION_FILTER_ALARMS]      (alarms only)
     *
     * [NotificationManager.INTERRUPTION_FILTER_ALL] (DND off) does NOT silence.
     * [NotificationManager.INTERRUPTION_FILTER_UNKNOWN] is treated conservatively
     * as "not silenced" to avoid blocking notifications due to an API glitch.
     *
     * @param context   Any context; used only to call [NotificationManager].
     * @param channelId Channel being evaluated.
     * @param now       Current wall-clock time; defaults to [LocalTime.now].
     * @return `true` if the notification should be silenced.
     */
    fun shouldSilence(
        context: Context,
        channelId: String,
        now: LocalTime = LocalTime.now(),
    ): Boolean {
        if (channelId in appPreferences.criticalChannelIds) return false
        if (isSystemDndActive(context)) return true
        if (!appPreferences.quietHoursEnabled) return false
        return inQuietWindow(now)
    }

    // ── Internal helpers ─────────────────────────────────────────────────────

    /**
     * Returns true when the system interruption filter is anything other than
     * [NotificationManager.INTERRUPTION_FILTER_ALL] (i.e. some form of DND is
     * currently active). Returns false on any error / unknown filter value.
     */
    internal fun isSystemDndActive(context: Context): Boolean {
        val nm = context.getSystemService(NotificationManager::class.java) ?: return false
        return when (nm.currentInterruptionFilter) {
            NotificationManager.INTERRUPTION_FILTER_NONE,
            NotificationManager.INTERRUPTION_FILTER_PRIORITY,
            NotificationManager.INTERRUPTION_FILTER_ALARMS -> true
            // INTERRUPTION_FILTER_ALL (1) = DND off → do NOT silence
            // INTERRUPTION_FILTER_UNKNOWN (0) = treated as off to be safe
            else -> false
        }
    }

    private fun inQuietWindow(now: LocalTime): Boolean {
        val start = appPreferences.quietHoursStartMinutes
        val end = appPreferences.quietHoursEndMinutes
        if (start == end) return false // zero-width window — disabled
        val nowMin = now.hour * 60 + now.minute
        return if (start < end) {
            nowMin in start until end
        } else {
            // Wrap-around (e.g. 22:00 start, 07:00 end): silenced if past
            // start OR before end.
            nowMin >= start || nowMin < end
        }
    }
}
