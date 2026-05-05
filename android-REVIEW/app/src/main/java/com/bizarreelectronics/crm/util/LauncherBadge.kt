package com.bizarreelectronics.crm.util

import android.content.Context
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.pm.ShortcutManagerCompat
import com.bizarreelectronics.crm.BizarreCrmApp
import timber.log.Timber

/**
 * §13 L1601 — Launcher badge count helper.
 *
 * Android Badge Strategy
 * ──────────────────────
 * Android's launcher badge system is decentralised: the system launcher reads
 * the badge count from the *notification shade* — specifically from the
 * `setNumber()` stamped on each posted notification.  The aggregate count
 * shown on the launcher icon is the sum of all active notifications' numbers.
 * We therefore do NOT call a proprietary Badge API; instead every notification
 * posted through [NotificationController] already carries `setNumber(totalUnread)`
 * (wired by FcmService via the `_badge_count` internal hint), which makes
 * AOSP / Pixel / Motorola launchers all show the correct dot/count.
 *
 * Samsung One UI (BadgeProvider)
 * ──────────────────────────────
 * Samsung launchers read badge counts from a proprietary ContentProvider
 * (`content://com.sec.badge/apps`). Writing to it requires the undocumented
 * `com.sec.android.provider.badge.permission.WRITE` permission which is only
 * granted to system-signed APKs on modern One UI versions.  The stable,
 * user-facing solution for Samsung is exactly what AOSP launchers use:
 * post notifications with `setNumber()` set — One UI reads that field through
 * the standard NotificationListenerService channel.
 *
 * ShortcutManagerCompat
 * ─────────────────────
 * [ShortcutManagerCompat.reportShortcutUsed] informs the launcher about
 * shortcut activity so it can surface the app in suggestions, but it does NOT
 * control the badge count.  We call it opportunistically when a notification is
 * posted so the launcher's recency model stays fresh.
 *
 * Usage
 * ─────
 * Call [update] from FcmService after posting a notification, passing the
 * aggregated unread count already computed by [NotificationController].
 */
object LauncherBadge {

    private const val TAG = "LauncherBadge"

    // The shortcut ID registered in res/xml/shortcuts.xml (or dynamic shortcut).
    // Matches what ShortcutManagerCompat expects — "main" is the conventional
    // entry-point shortcut. If no static shortcut is defined this call is a
    // graceful no-op.
    private const val SHORTCUT_ID_MAIN = "main"

    /**
     * Update the launcher badge count.
     *
     * Primary mechanism: every notification in the shade already carries
     * [setNumber(totalUnread)][androidx.core.app.NotificationCompat.Builder.setNumber].
     * The launcher aggregates these automatically.  This function reports the
     * shortcut usage so the launcher's prediction model knows the app is active,
     * and logs for debugging.
     *
     * @param context   Application or service context.
     * @param totalUnread Aggregate count across SMS + tickets + notifications.
     *                    Pass 0 to clear the badge (no active notifications).
     */
    fun update(context: Context, totalUnread: Int) {
        Timber.d("%s: badge count = %d", TAG, totalUnread)

        // Report shortcut usage so launcher keeps the app in suggestions.
        // ShortcutManagerCompat.reportShortcutUsed is a no-op when the
        // shortcut ID is not registered — safe to call unconditionally.
        runCatching {
            ShortcutManagerCompat.reportShortcutUsed(context, SHORTCUT_ID_MAIN)
        }.onFailure { e ->
            Timber.w(e, "%s: ShortcutManagerCompat.reportShortcutUsed failed (non-fatal)", TAG)
        }

        // Samsung One UI TODO: if we ever need to support the legacy
        // BadgeProvider path (One UI 2 / pre-NotificationListenerService era),
        // insert a ContentResolver.insert("content://com.sec.badge/apps", ...)
        // call here guarded by Build.MANUFACTURER == "samsung" &&
        // Build.VERSION.SDK_INT < Build.VERSION_CODES.Q.  Requires declaring
        // "com.sec.android.provider.badge.permission.WRITE" in the manifest
        // (only granted on Samsung firmware) and a try/catch for
        // SecurityException on non-Samsung devices.
        //
        // This is NOT needed for current Samsung One UI 4+ targets because One UI
        // reads setNumber() from posted notifications via NotificationListenerService.
    }

    /**
     * Compute the total unread count by summing [setNumber] values across all
     * active notifications in the badge-eligible channels.
     *
     * Channels with [setShowBadge(false)][android.app.NotificationChannel.setShowBadge]
     * (low_stock, daily_summary, sync, backup_report) are excluded because they
     * represent background info, not actionable unread items.
     */
    fun computeUnread(context: Context): Int {
        val nm = NotificationManagerCompat.from(context)
        // getActiveNotifications requires POST_NOTIFICATIONS permission on API 33+;
        // if it throws SecurityException return 0 rather than crashing.
        return runCatching {
            nm.activeNotifications
                .filter { sbn -> sbn.notification.extras != null }
                .filter { sbn -> isBadgeChannel(sbn.notification.channelId) }
                .sumOf { sbn -> sbn.notification.number.coerceAtLeast(1) }
        }.getOrElse { e ->
            Timber.w(e, "%s: could not read active notifications (non-fatal)", TAG)
            0
        }
    }

    private fun isBadgeChannel(channelId: String?): Boolean = when (channelId) {
        BizarreCrmApp.CH_SMS_INBOUND,
        BizarreCrmApp.CH_SMS_SILENT,
        BizarreCrmApp.CH_APPOINTMENT_REMINDER,
        BizarreCrmApp.CH_SLA_BREACH,
        BizarreCrmApp.CH_SECURITY_EVENT,
        BizarreCrmApp.CH_TICKET_ASSIGNED,
        BizarreCrmApp.CH_TICKET_STATUS,
        BizarreCrmApp.CH_PAYMENT_RECEIVED,
        BizarreCrmApp.CH_MENTION -> true
        else -> false
    }
}
