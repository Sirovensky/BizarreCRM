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

        val id = notificationIdCounter.getAndIncrement()

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
            type == "mention" || type == "mentioned" -> BizarreCrmApp.CH_MENTION
            type == "low_stock" || type == "inventory_low" -> BizarreCrmApp.CH_LOW_STOCK
            type == "daily_summary" || type == "end_of_day" -> BizarreCrmApp.CH_DAILY_SUMMARY
            type == "backup_report" || type == "backup_failed" || type == "diagnostics" ->
                BizarreCrmApp.CH_BACKUP_REPORT
            else -> BizarreCrmApp.CH_SYNC
        }

        Timber.d("NotificationController: type=%s channel=%s silentDedup=%s", type, channelId, isSmsActiveThread)

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
            .setContentTitle(title)
            .setContentText(body)
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

        // §13 L1579 — Rich push: download image_url and apply BigPictureStyle.
        // Downloads on the calling thread (FcmService is already on a bg thread)
        // with a 5-second timeout. Falls back to standard style on any failure.
        if (imageUrl != null) {
            val bitmap = fetchBitmap(context, imageUrl)
            if (bitmap != null) {
                builder.setStyle(
                    NotificationCompat.BigPictureStyle()
                        .bigPicture(bitmap)
                        .setBigContentTitle(title)
                        .setSummaryText(body),
                )
            } else {
                // Fallback: use BigTextStyle so long body is still readable.
                builder.setStyle(NotificationCompat.BigTextStyle().bigText(body))
            }
        } else if (body.length > 40) {
            // Expand long text even without an image.
            builder.setStyle(NotificationCompat.BigTextStyle().bigText(body))
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
