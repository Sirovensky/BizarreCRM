package com.bizarreelectronics.crm.service

import android.app.NotificationChannel
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

    /**
     * Register all notification channels. Safe to call multiple times —
     * no-op for channels that already exist at the same importance level.
     */
    fun registerAll(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        val channels = buildChannels()
        channels.forEach { manager.createNotificationChannel(it) }
        Timber.d("NotificationChannelBootstrap: registered %d channels", channels.size)

        // Remove legacy IDs from a prior release so they don't resurface in
        // Settings → Notifications if we accidentally post to an old ID.
        listOf("sms", "tickets", "appointments").forEach { legacy ->
            runCatching { manager.deleteNotificationChannel(legacy) }
        }
    }

    private fun buildChannels(): List<NotificationChannel> {
        val defaultSoundUri = Settings.System.DEFAULT_NOTIFICATION_URI.toString().toUri()

        return listOf(
            // ── High-importance ─────────────────────────────────────────────

            NotificationChannel(
                BizarreCrmApp.CH_SMS_INBOUND,
                "SMS — incoming",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
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
                description = "Upcoming appointment reminders."
                setShowBadge(true)
                setSound(defaultSoundUri, audioAttrs)
                enableVibration(true)
                vibrationPattern = VIB_CRITICAL
                enableLights(true)
            },

            NotificationChannel(
                BizarreCrmApp.CH_SLA_BREACH,
                "SLA breach",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Ticket SLA amber / red alerts."
                setShowBadge(true)
                setSound(defaultSoundUri, audioAttrs)
                enableVibration(true)
                vibrationPattern = VIB_CRITICAL
                enableLights(true)
            },

            NotificationChannel(
                BizarreCrmApp.CH_SECURITY_EVENT,
                "Security alerts",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Unusual sign-ins, session revokes, password changes."
                setShowBadge(true)
                setSound(defaultSoundUri, audioAttrs)
                enableVibration(true)
                vibrationPattern = VIB_CRITICAL
                enableLights(true)
            },

            // ── Default-importance ───────────────────────────────────────────

            NotificationChannel(
                BizarreCrmApp.CH_TICKET_ASSIGNED,
                "Ticket assigned to you",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "You were assigned a ticket."
                setShowBadge(true)
            },

            NotificationChannel(
                BizarreCrmApp.CH_TICKET_STATUS,
                "Ticket status changes",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "Status updates on tickets you follow."
                setShowBadge(true)
            },

            NotificationChannel(
                BizarreCrmApp.CH_PAYMENT_RECEIVED,
                "Payment received",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "Invoice payments and deposits."
                setShowBadge(true)
            },

            NotificationChannel(
                BizarreCrmApp.CH_MENTION,
                "You were @mentioned",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "You were tagged in a note, message, or chat."
                setShowBadge(true)
            },

            // ── Low-importance (silent) ──────────────────────────────────────

            NotificationChannel(
                BizarreCrmApp.CH_LOW_STOCK,
                "Low-stock alerts",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
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
                description = "End-of-day totals and activity digest."
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            },

            NotificationChannel(
                BizarreCrmApp.CH_SYNC,
                "Background sync",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
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
                description = "Backup results, crash reports, diagnostic logs."
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            },

            // ── Dedup silent — §1.7 L245 ─────────────────────────────────────

            NotificationChannel(
                BizarreCrmApp.CH_SMS_SILENT,
                "SMS — silent (conversation open)",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Badge-only update when a new SMS arrives for a thread you are currently viewing."
                setShowBadge(true)
                setSound(null, null)
                enableVibration(false)
            },
        )
    }
}
