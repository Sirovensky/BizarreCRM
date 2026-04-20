package com.bizarreelectronics.crm.util

import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import java.time.LocalTime
import javax.inject.Inject
import javax.inject.Singleton

/**
 * §13.2 — quiet-hours decision helper.
 *
 * Single source of truth for "should this push be silenced?" so FcmService,
 * in-app banners, and any future scheduled notification path all agree.
 *
 * Behavior:
 *   - If `quietHoursEnabled == false` → never silence.
 *   - If the channel is in [AppPreferences.criticalChannelIds] → never silence.
 *   - Otherwise compare [LocalTime.now] (system tz) against the inclusive
 *     start / exclusive end window. Wrap-around windows (start > end, e.g.
 *     22:00–07:00) are handled by the OR branch.
 */
@Singleton
class QuietHours @Inject constructor(
    private val appPreferences: AppPreferences,
) {

    fun shouldSilence(channelId: String, now: LocalTime = LocalTime.now()): Boolean {
        if (!appPreferences.quietHoursEnabled) return false
        if (channelId in appPreferences.criticalChannelIds) return false
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
