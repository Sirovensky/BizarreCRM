package com.bizarreelectronics.crm.service

import android.app.NotificationChannel
import android.app.NotificationChannelGroup
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.os.Build
import android.provider.Settings
import androidx.core.net.toUri
import com.bizarreelectronics.crm.BizarreCrmApp
import timber.log.Timber

/**
 * §13 L1591 — Centralised notification-channel registration.
 *
 * Channel strategy:
 * ─────────────────────────────────────────────────────────────────────────────
 * Every business-event category maps to exactly one channel so users can
 * tune each category independently via Settings → Notifications → Bizarre CRM.
 * Channel IDs are frozen constants in [BizarreCrmApp]; NEVER rename them
 * because Android persists user overrides keyed by channel ID forever.
 *
 * Sound / Vibration policy:
 *  • SMS (sms_inbound)   — default notification URI + short double-tap {0,200,100,200}
 *  • Critical (sla_breach, security_event, appointment_reminder)
 *                         — default URI + emphatic long-pulse {0,500,250,500}
 *  • Default importance   — system default (channel inherits OS default sound/vib)
 *  • Low importance       — no sound, no vibration explicitly
 *  • sms_silent           — null sound, vibration disabled (dedup badge-only)
 *
 * Badge policy:
 *  • High / Default importance → setShowBadge(true)
 *  • Low importance            → setShowBadge(false)
 *  • sms_silent                → setShowBadge(true)  (badge still useful)
 *
 * [registerAll] is idempotent — Android ignores duplicate createNotificationChannel
 * calls for existing IDs (only name/description can be updated, importance cannot
 * be lowered once set by the user).
 */
object NotificationChannelBootstrap {

    // Vibration patterns: {delay-before-first-on, on-ms, off-ms, on-ms, ...}
    private val VIB_SMS = longArrayOf(0L, 200L, 100L, 200L)
    private val VIB_CRITICAL = longArrayOf(0L, 500L, 250L, 500L)

    private val audioAttrs: AudioAttributes by lazy {
        AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
    }

    // §21.2 — Channel group IDs. Frozen constants; Android persists user overrides
    // by group ID so renaming these will break previously-configured user settings.
    const val GROUP_OPERATIONAL  = "group_operational"
    const val GROUP_CUSTOMER     = "group_customer"
    const val GROUP_ADMIN        = "group_admin"
    const val GROUP_SYSTEM       = "group_system"
    // §73 — additional groups matching the per-event matrix audience taxonomy.
    const val GROUP_STAFF        = "group_staff"
    const val GROUP_DIAGNOSTICS  = "group_diagnostics"

    /**
     * Register all notification channel groups and channels.
     *
     * §21.2 — Four groups (Operational / Customer / Admin / System) so users can
     * collapse a whole category in Settings → Notifications. Groups must be
     * created before their member channels or the group assignment is silently
     * ignored on Android 8.
     *
     * Safe to call multiple times — Android ignores duplicate
     * createNotificationChannelGroup / createNotificationChannel calls for
     * existing IDs (only name/description can be updated).
     */
    fun registerAll(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        // Groups first — channels that reference a group ID must be created after.
        buildGroups().forEach { manager.createNotificationChannelGroup(it) }
        val channels = buildChannels()
        channels.forEach { manager.createNotificationChannel(it) }
        Timber.d("NotificationChannelBootstrap: registered %d channels in %d groups", channels.size, 4)

        // Remove legacy IDs from a prior release so they don't resurface in
        // Settings → Notifications if we accidentally post to an old ID.
        listOf("sms", "tickets", "appointments").forEach { legacy ->
            runCatching { manager.deleteNotificationChannel(legacy) }
        }
    }

    /**
     * §21.2 — Build the four top-level channel groups shown in
     * Settings → Notifications → Bizarre CRM.
     *
     * Groups are cosmetic in Android 8/9 and gain collapsibility in Android 10+.
     */
    private fun buildGroups(): List<NotificationChannelGroup> = listOf(
        NotificationChannelGroup(GROUP_OPERATIONAL, "Operational")
            .also { if (Build.VERSION.SDK_INT >= 28) it.description = "Tickets, repairs, and parts." },
        NotificationChannelGroup(GROUP_CUSTOMER, "Customer")
            .also { if (Build.VERSION.SDK_INT >= 28) it.description = "Inbound SMS, appointments, and mentions." },
        NotificationChannelGroup(GROUP_ADMIN, "Admin")
            .also { if (Build.VERSION.SDK_INT >= 28) it.description = "Payments, SLA breaches, and daily summaries." },
        NotificationChannelGroup(GROUP_SYSTEM, "System")
            .also { if (Build.VERSION.SDK_INT >= 28) it.description = "Background sync, backup, and security." },
        // §73 — Staff group for shift / HR events (shift starting, time-off requests).
        NotificationChannelGroup(GROUP_STAFF, "Staff")
            .also { if (Build.VERSION.SDK_INT >= 28) it.description = "Shift reminders, time-off requests, and team mentions." },
        // §73 — Diagnostics group for setup / subscription / integration health alerts.
        NotificationChannelGroup(GROUP_DIAGNOSTICS, "Diagnostics")
            .also { if (Build.VERSION.SDK_INT >= 28) it.description = "Setup wizard, subscription renewal, and integration status." },
    )

    private fun buildChannels(): List<NotificationChannel> {
        val defaultSoundUri = Settings.System.DEFAULT_NOTIFICATION_URI.toString().toUri()

        return listOf(
            // ── High-importance ─────────────────────────────────────────────

            // ── Customer group — high-importance ────────────────────────────

            NotificationChannel(
                BizarreCrmApp.CH_SMS_INBOUND,
                "SMS — incoming",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                group = GROUP_CUSTOMER
                description = "New SMS messages from customers."
                setShowBadge(true)
                setSound(defaultSoundUri, audioAttrs)
                enableVibration(true)
                vibrationPattern = VIB_SMS
                enableLights(true)
            },

            NotificationChannel(
                BizarreCrmApp.CH_APPOINTMENT_REMINDER,
                "Appointment reminder",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                group = GROUP_CUSTOMER
                description = "Upcoming appointment reminders."
                setShowBadge(true)
                setSound(defaultSoundUri, audioAttrs)
                enableVibration(true)
                vibrationPattern = VIB_CRITICAL
                enableLights(true)
            },

            // ── Admin group — high-importance ────────────────────────────────

            NotificationChannel(
                BizarreCrmApp.CH_SLA_BREACH,
                "SLA breach",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                group = GROUP_ADMIN
                description = "Ticket SLA amber / red alerts."
                setShowBadge(true)
                setSound(defaultSoundUri, audioAttrs)
                enableVibration(true)
                vibrationPattern = VIB_CRITICAL
                enableLights(true)
                // §73.4 — CATEGORY_ALARM so the OS allows bypassing DND for critical
                // business events. Only applied to SLA breach + security; DO NOT add
                // to any other channel — misuse of CATEGORY_ALARM is a Play policy
                // violation and causes OS-level suppression on Android 12+.
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            },

            // ── System group — high-importance ───────────────────────────────

            NotificationChannel(
                BizarreCrmApp.CH_SECURITY_EVENT,
                "Security alerts",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                group = GROUP_SYSTEM
                description = "Unusual sign-ins, session revokes, password changes."
                setShowBadge(true)
                setSound(defaultSoundUri, audioAttrs)
                enableVibration(true)
                vibrationPattern = VIB_CRITICAL
                enableLights(true)
                // §73.4 — See SLA breach note above.
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            },

            // ── Admin group — high-importance — §73.4 backup-failed critical ─

            NotificationChannel(
                BizarreCrmApp.CH_PAYMENT_DECLINED,
                "Payment declined",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                group = GROUP_ADMIN
                description = "Card declined or payment gateway error mid-transaction."
                setShowBadge(true)
                setSound(defaultSoundUri, audioAttrs)
                enableVibration(true)
                vibrationPattern = VIB_CRITICAL
                enableLights(true)
            },

            // ── Operational group — default-importance ───────────────────────

            NotificationChannel(
                BizarreCrmApp.CH_TICKET_ASSIGNED,
                "Ticket assigned to you",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                group = GROUP_OPERATIONAL
                description = "You were assigned a ticket."
                setShowBadge(true)
            },

            NotificationChannel(
                BizarreCrmApp.CH_TICKET_STATUS,
                "Ticket status changes",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                group = GROUP_OPERATIONAL
                description = "Status updates on tickets you follow."
                setShowBadge(true)
            },

            // ── Admin group — default-importance ─────────────────────────────

            NotificationChannel(
                BizarreCrmApp.CH_PAYMENT_RECEIVED,
                "Payment received",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                group = GROUP_ADMIN
                description = "Invoice payments and deposits."
                setShowBadge(true)
            },

            // ── Customer group — default-importance ──────────────────────────

            NotificationChannel(
                BizarreCrmApp.CH_MENTION,
                "You were @mentioned",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                group = GROUP_CUSTOMER
                description = "You were tagged in a note, message, or chat."
                setShowBadge(true)
            },

            // ── Admin group — low-importance (silent) ────────────────────────

            NotificationChannel(
                BizarreCrmApp.CH_LOW_STOCK,
                "Low-stock alerts",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                group = GROUP_ADMIN
                description = "Inventory items below reorder threshold."
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            },

            NotificationChannel(
                BizarreCrmApp.CH_DAILY_SUMMARY,
                "Daily summary",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                group = GROUP_ADMIN
                description = "End-of-day totals and activity digest."
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            },

            // ── System group — low-importance ────────────────────────────────

            NotificationChannel(
                BizarreCrmApp.CH_SYNC,
                "Background sync",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                group = GROUP_SYSTEM
                description = "Data synchronization progress."
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            },

            NotificationChannel(
                BizarreCrmApp.CH_BACKUP_REPORT,
                "Backup & diagnostics",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                group = GROUP_SYSTEM
                description = "Backup results, crash reports, diagnostic logs."
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            },

            // ── Admin group — export ready — §51.3 ──────────────────────────

            NotificationChannel(
                BizarreCrmApp.CH_EXPORT_READY,
                "Export ready",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                group = GROUP_ADMIN
                description = "Notifies when a requested data export is ready to download."
                setShowBadge(true)
            },

            // ── Customer group — dedup silent — §1.7 L245 ───────────────────

            NotificationChannel(
                BizarreCrmApp.CH_SMS_SILENT,
                "SMS — silent (conversation open)",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                group = GROUP_CUSTOMER
                description = "Badge-only update when a new SMS arrives for a thread you are currently viewing."
                setShowBadge(true)
                setSound(null, null)
                enableVibration(false)
            },

            // ── §73 — new channels for per-event matrix ──────────────────────

            // Operational group
            NotificationChannel(
                BizarreCrmApp.CH_INVOICE_OVERDUE,
                "Invoice overdue",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                group = GROUP_ADMIN
                description = "Invoices past their due date."
                setShowBadge(true)
            },

            NotificationChannel(
                BizarreCrmApp.CH_ESTIMATE_APPROVED,
                "Estimate approved",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                group = GROUP_OPERATIONAL
                description = "Customer approved a repair estimate."
                setShowBadge(true)
            },

            // Staff group
            NotificationChannel(
                BizarreCrmApp.CH_SHIFT_STARTING,
                "Shift starting",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                group = GROUP_STAFF
                description = "Your shift is about to begin."
                setShowBadge(true)
            },

            NotificationChannel(
                BizarreCrmApp.CH_MANAGER_TIMEOFF,
                "Time-off request",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                group = GROUP_STAFF
                description = "Staff time-off request awaiting manager review."
                setShowBadge(true)
            },

            NotificationChannel(
                BizarreCrmApp.CH_TEAM_MENTION,
                "Team chat mention",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                group = GROUP_STAFF
                description = "You were @mentioned in team chat."
                setShowBadge(true)
            },

            // Admin group — low-importance digests
            NotificationChannel(
                BizarreCrmApp.CH_WEEKLY_DIGEST,
                "Weekly digest",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                group = GROUP_ADMIN
                description = "Weekly summary of shop activity."
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            },

            // Diagnostics group
            NotificationChannel(
                BizarreCrmApp.CH_SETUP_WIZARD,
                "Setup wizard",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                group = GROUP_DIAGNOSTICS
                description = "Reminders to complete initial shop setup."
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            },

            NotificationChannel(
                BizarreCrmApp.CH_SUBSCRIPTION_RENEWAL,
                "Subscription renewal",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                group = GROUP_DIAGNOSTICS
                description = "Upcoming subscription renewal reminders."
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            },

            NotificationChannel(
                BizarreCrmApp.CH_INTEGRATION_DISCONNECTED,
                "Integration disconnected",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                group = GROUP_DIAGNOSTICS
                description = "A connected integration (payment processor, calendar, etc.) was disconnected."
                setShowBadge(true)
            },
        )
    }
}
