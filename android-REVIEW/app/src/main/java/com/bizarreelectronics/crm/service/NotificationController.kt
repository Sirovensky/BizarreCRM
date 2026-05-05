package com.bizarreelectronics.crm.service

import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.os.Bundle
import androidx.core.app.NotificationCompat
import androidx.core.app.RemoteInput
import coil3.ImageLoader
import coil3.request.ImageRequest
import coil3.request.SuccessResult
import coil3.toBitmap
import com.bizarreelectronics.crm.BizarreCrmApp
import com.bizarreelectronics.crm.MainActivity
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.util.ActiveChatTracker
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import timber.log.Timber
import java.util.concurrent.atomic.AtomicInteger

/**
 * §1.7 lines 244–245 — Centralised notification builder.
 *
 * Accepts a raw FCM data map, decides channel + action buttons, and returns
 * a fully-built [Notification]. The caller (FcmService) is responsible for
 * posting it via [androidx.core.app.NotificationManagerCompat].
 *
 * SMS dedup: if [data["thread_phone"]] matches the thread currently open in
 * SmsThreadScreen (tracked by [ActiveChatTracker]), a silent low-importance
 * notification is emitted instead so the badge updates without interrupting
 * the user with sound/vibration.
 *
 * This class is stateless. It is safe to construct once per FCM message on
 * the IO thread.
 */
object NotificationController {

    // Intent action constants — must match NotificationActionReceiver filter.
    const val ACTION_REPLY_SMS = "com.bizarreelectronics.crm.ACTION_REPLY_SMS"
    const val ACTION_MARK_READ = "com.bizarreelectronics.crm.ACTION_MARK_READ"

    // RemoteInput result key for direct-reply text.
    const val EXTRA_REPLY_TEXT = "extra_reply_text"

    // Extras forwarded to the receiver so it knows which entity to act on.
    const val EXTRA_NOTIFICATION_ID = "extra_notification_id"
    const val EXTRA_ENTITY_ID = "extra_entity_id"
    const val EXTRA_ENTITY_TYPE = "extra_entity_type"
    const val EXTRA_THREAD_PHONE = "extra_thread_phone"

    // Silent dedup channel for SMS while the thread is open.
    private const val CH_SMS_SILENT = BizarreCrmApp.CH_SMS_SILENT

    // §73.3 — 60-second dedup map: type → last-fire epoch-ms.
    // When the same event type fires again within 60 s we reuse the existing
    // notification ID so Android merges the shade entry instead of stacking.
    // ConcurrentHashMap is safe: onMessageReceived may arrive on concurrent IO
    // threads from the Firebase-managed executor.
    private val lastNotifEpochByType =
        java.util.concurrent.ConcurrentHashMap<String, Long>()
    private val dedupNotifIdByType =
        java.util.concurrent.ConcurrentHashMap<String, Int>()
    private const val DEDUP_WINDOW_MS = 60_000L

    private val notificationIdCounter = AtomicInteger(1_000)

    /**
     * Build and return a notification for the given FCM [data] payload.
     *
     * @return a [Pair] of (notification-id, Notification) ready to pass to
     *         NotificationManagerCompat.notify(id, notification).
     */
    fun handle(context: Context, data: Map<String, String>): Pair<Int, Notification> {
        val type = data["type"] ?: "system"
        val entityId = data["entity_id"]?.toLongOrNull() ?: 0L
        val entityType = data["entity_type"] ?: type
        val title = data["title"]?.takeIf { it.isNotBlank() } ?: "Bizarre CRM"
        val body = data["body"]?.takeIf { it.isNotBlank() } ?: ""
        val threadPhone = data["thread_phone"]?.takeIf { it.isNotBlank() }
        val navigateTo = data["navigate_to"]?.takeIf { it.isNotBlank() }
        // §13 L1579 — optional image URL for BigPictureStyle rich push.
        val imageUrl = data["image_url"]?.takeIf { it.isNotBlank() }
        // Internal hints injected by FcmService — not from server payload.
        val quietOverride = data["_quiet_override"] == "true"
        val badgeCount = data["_badge_count"]?.toIntOrNull() ?: 0

        // Determine whether we should use the silent dedup channel.
        val isSmsActiveThread = type == "sms_inbound" &&
            threadPhone != null &&
            threadPhone == ActiveChatTracker.currentThreadPhone

        val channelId = when {
            isSmsActiveThread -> CH_SMS_SILENT
            type == "sms_inbound" || type == "sms" -> BizarreCrmApp.CH_SMS_INBOUND
            type == "ticket_assigned" -> BizarreCrmApp.CH_TICKET_ASSIGNED
            type == "ticket_updated" || type == "customer_message" -> BizarreCrmApp.CH_TICKET_STATUS
            type == "appointment_reminder" -> BizarreCrmApp.CH_APPOINTMENT_REMINDER
            type.startsWith("sla_") -> BizarreCrmApp.CH_SLA_BREACH
            type == "security_event" || type == "session_revoked" || type == "password_changed" ->
                BizarreCrmApp.CH_SECURITY_EVENT
            type == "payment_received" || type == "invoice_paid" || type == "deposit_received" ->
                BizarreCrmApp.CH_PAYMENT_RECEIVED
            // §51.3 — export-ready push: server sends type=export_ready when the
            // async export job transitions to status=ready.
            type == "export_ready" -> BizarreCrmApp.CH_EXPORT_READY
            type == "mention" || type == "mentioned" -> BizarreCrmApp.CH_MENTION
            type == "low_stock" || type == "inventory_low" -> BizarreCrmApp.CH_LOW_STOCK
            type == "daily_summary" || type == "end_of_day" -> BizarreCrmApp.CH_DAILY_SUMMARY
            type == "backup_report" || type == "backup_failed" || type == "diagnostics" ->
                BizarreCrmApp.CH_BACKUP_REPORT
            // §73 — new per-event matrix channels.
            type == "payment_declined" || type == "card_declined" -> BizarreCrmApp.CH_PAYMENT_DECLINED
            type == "invoice_overdue" -> BizarreCrmApp.CH_INVOICE_OVERDUE
            type == "estimate_approved" -> BizarreCrmApp.CH_ESTIMATE_APPROVED
            type == "shift_starting" -> BizarreCrmApp.CH_SHIFT_STARTING
            type == "timeoff_request" || type == "manager_timeoff" -> BizarreCrmApp.CH_MANAGER_TIMEOFF
            type == "team_mention" -> BizarreCrmApp.CH_TEAM_MENTION
            type == "weekly_digest" -> BizarreCrmApp.CH_WEEKLY_DIGEST
            type == "setup_wizard_incomplete" -> BizarreCrmApp.CH_SETUP_WIZARD
            type == "subscription_renewal" -> BizarreCrmApp.CH_SUBSCRIPTION_RENEWAL
            type == "integration_disconnected" -> BizarreCrmApp.CH_INTEGRATION_DISCONNECTED
            else -> BizarreCrmApp.CH_SYNC
        }

        Timber.d("NotificationController: type=%s channel=%s silentDedup=%s", type, channelId, isSmsActiveThread)

        // §73.3 — 60-second dedup: if the same event type fired within the last
        // 60 s, reuse the existing notification ID so Android replaces (merges)
        // the shade entry rather than stacking a second alert for the same event.
        // The body is updated to show the latest payload; the title gains a "+N more"
        // counter so the user knows there were repeat events.
        val nowMs = System.currentTimeMillis()
        val lastMs = lastNotifEpochByType[type] ?: 0L
        val withinDedupWindow = (nowMs - lastMs) < DEDUP_WINDOW_MS && !isSmsActiveThread
        val id: Int
        val dedupCount: Int
        if (withinDedupWindow) {
            id = dedupNotifIdByType[type] ?: notificationIdCounter.getAndIncrement()
            dedupNotifIdByType[type] = id
            // Count how many times this type has fired in the current window.
            dedupCount = ((lastNotifEpochByType["${type}_count"]?.toInt()) ?: 1) + 1
            lastNotifEpochByType["${type}_count"] = dedupCount.toLong()
        } else {
            id = notificationIdCounter.getAndIncrement()
            dedupNotifIdByType[type] = id
            dedupCount = 1
            lastNotifEpochByType["${type}_count"] = 1L
        }
        lastNotifEpochByType[type] = nowMs

        // §73.5 — Payment rich content: prepend amount + customer name to body
        // when the server provides them so the shade is scannable without opening.
        // Server should send data["amount"] (e.g. "42.50") and data["customer_name"].
        val amount = data["amount"]?.takeIf { it.isNotBlank() }
        val customerName = data["customer_name"]?.takeIf { it.isNotBlank() }
        val deviceModel = data["device_model"]?.takeIf { it.isNotBlank() }
        val ticketStatus = data["ticket_status"]?.takeIf { it.isNotBlank() }

        // §73.5 — Build enriched body: payment events → amount + customer;
        //          ticket events → device model + status appended.
        val enrichedBody = when {
            (type == "payment_received" || type == "payment_declined" || type == "invoice_paid") &&
                    amount != null && customerName != null ->
                "\$$amount — $customerName${if (body.isNotBlank()) "\n$body" else ""}"
            (type == "ticket_assigned" || type == "ticket_updated") &&
                    deviceModel != null ->
                buildString {
                    append(deviceModel)
                    if (ticketStatus != null) append(" · $ticketStatus")
                    if (body.isNotBlank()) append("\n$body")
                }
            else -> body
        }

        // §73.3 — Update title with "+N more" when deduplication is active.
        val displayTitle = if (dedupCount > 1) "$title (+${dedupCount - 1} more)" else title

        // Tap-to-open intent — navigates MainActivity to the relevant screen.
        val tapIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            if (navigateTo != null) {
                putExtra("navigate_to", navigateTo)
                if (entityId > 0) putExtra("entity_id", entityId.toString())
            } else if (threadPhone != null && (type == "sms_inbound" || type == "sms")) {
                putExtra("navigate_to", "sms")
                putExtra("thread_phone", threadPhone)
            }
        }
        val tapPendingIntent = PendingIntent.getActivity(
            context, id, tapIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        // Public (lock-screen) version — hides sensitive content.
        val publicNotification = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Bizarre CRM")
            .setContentText("New notification")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()

        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(displayTitle)
            .setContentText(enrichedBody)
            .setAutoCancel(true)
            .setContentIntent(tapPendingIntent)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPublicVersion(publicNotification)

        val shouldBeSilent = isSmsActiveThread || quietOverride
        if (shouldBeSilent) {
            // Silent dedup or quiet hours — badge updates only, no sound/vibration.
            builder
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setSilent(true)
                .setDefaults(0)
        } else {
            builder.setPriority(NotificationCompat.PRIORITY_HIGH)
        }

        // §73.4 — CATEGORY_ALARM on truly critical channels so the OS can allow
        // these to break through DND when the user opts in via system settings.
        // Only backup_failed + security_event + sla_breach + payment_declined
        // qualify. DO NOT add other channels here — misuse blocks Play Store.
        when (channelId) {
            BizarreCrmApp.CH_BACKUP_REPORT,
            BizarreCrmApp.CH_SECURITY_EVENT,
            BizarreCrmApp.CH_SLA_BREACH,
            BizarreCrmApp.CH_PAYMENT_DECLINED,
            -> builder.setCategory(android.app.Notification.CATEGORY_ALARM)
            else -> { /* IMPORTANCE_DEFAULT — no special category */ }
        }

        // §13 L1579 — Rich push: download image_url and apply BigPictureStyle.
        // Downloads on the calling thread (FcmService is already on a bg thread)
        // with a 5-second timeout. Falls back to standard style on any failure.
        if (imageUrl != null) {
            val bitmap = fetchBitmap(context, imageUrl)
            if (bitmap != null) {
                builder.setStyle(
                    NotificationCompat.BigPictureStyle()
                        .bigPicture(bitmap)
                        .setBigContentTitle(displayTitle)
                        .setSummaryText(enrichedBody),
                )
            } else {
                // Fallback: use BigTextStyle so long body is still readable.
                builder.setStyle(NotificationCompat.BigTextStyle().bigText(enrichedBody))
            }
        } else if (enrichedBody.length > 40) {
            // Expand long text even without an image.
            builder.setStyle(NotificationCompat.BigTextStyle().bigText(enrichedBody))
        }

        // §13.4: stamp badge count so Samsung One UI dot stays accurate.
        if (badgeCount > 0) {
            builder.setNumber(badgeCount)
        }

        // §1.7 L245 — action buttons.
        val extras = Bundle().apply {
            putInt(EXTRA_NOTIFICATION_ID, id)
            putLong(EXTRA_ENTITY_ID, entityId)
            putString(EXTRA_ENTITY_TYPE, entityType)
            if (threadPhone != null) putString(EXTRA_THREAD_PHONE, threadPhone)
        }

        // "Mark as read" — available for all notification types.
        val markReadIntent = receiverIntent(context, ACTION_MARK_READ, extras, id + 10_000)
        builder.addAction(
            NotificationCompat.Action.Builder(
                R.mipmap.ic_launcher,
                "Mark as read",
                markReadIntent,
            ).build()
        )

        // "Reply" with RemoteInput — SMS only.
        if (type == "sms_inbound" || type == "sms") {
            val remoteInput = RemoteInput.Builder(EXTRA_REPLY_TEXT)
                .setLabel("Reply\u2026")
                .build()
            val replyIntent = receiverIntent(context, ACTION_REPLY_SMS, extras, id + 20_000)
            val replyAction = NotificationCompat.Action.Builder(
                R.mipmap.ic_launcher,
                "Reply",
                replyIntent,
            )
                .addRemoteInput(remoteInput)
                .setAllowGeneratedReplies(true)
                .build()
            // Insert Reply before Mark-as-read so it appears first.
            builder.clearActions()
            builder.addAction(replyAction)
            builder.addAction(
                NotificationCompat.Action.Builder(
                    R.mipmap.ic_launcher,
                    "Mark as read",
                    markReadIntent,
                ).build()
            )
        }

        return id to builder.build()
    }

    /**
     * §13 L1579 — Download an image for BigPictureStyle with a 5-second timeout.
     *
     * Uses the existing Coil singleton (same OkHttp client, disk cache, etc.).
     * Returns null on any failure — the caller falls back to standard style.
     * Must be called from a non-Main thread (runBlocking is acceptable inside
     * FcmService.onMessageReceived which runs on a Firebase-managed IO thread).
     */
    private fun fetchBitmap(context: Context, url: String): Bitmap? = runCatching {
        runBlocking {
            withTimeout(5_000L) {
                val loader = ImageLoader(context)
                val request = ImageRequest.Builder(context)
                    .data(url)
                    .build()
                val result = loader.execute(request)
                (result as? SuccessResult)?.image?.toBitmap()
            }
        }
    }.onFailure { e ->
        Timber.w(e, "NotificationController: BigPicture download failed, url=%s", url)
    }.getOrNull()

    private fun receiverIntent(
        context: Context,
        action: String,
        extras: Bundle,
        requestCode: Int,
    ): PendingIntent {
        val intent = Intent(context, NotificationActionReceiver::class.java).apply {
            this.action = action
            putExtras(extras)
        }
        return PendingIntent.getBroadcast(
            context, requestCode, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )
    }
}
