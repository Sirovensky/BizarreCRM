package com.bizarreelectronics.crm.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.widget.Toast
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.RemoteInput
import com.bizarreelectronics.crm.data.local.db.entities.SyncQueueEntity
import com.bizarreelectronics.crm.service.NotificationController.ACTION_MARK_READ
import com.bizarreelectronics.crm.service.NotificationController.ACTION_REPLY_SMS
import com.bizarreelectronics.crm.service.NotificationController.EXTRA_ENTITY_ID
import com.bizarreelectronics.crm.service.NotificationController.EXTRA_ENTITY_TYPE
import com.bizarreelectronics.crm.service.NotificationController.EXTRA_NOTIFICATION_ID
import com.bizarreelectronics.crm.service.NotificationController.EXTRA_REPLY_TEXT
import com.bizarreelectronics.crm.service.NotificationController.EXTRA_THREAD_PHONE
import com.google.gson.Gson
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject

/**
 * §1.7 L245 — Handles notification action button taps fired from
 * [NotificationController]-built notifications.
 *
 * Supported actions:
 *  - [ACTION_REPLY_SMS]  — extract reply text via [RemoteInput], enqueue SMS
 *    send in the offline sync queue, cancel the notification, toast confirmation.
 *  - [ACTION_MARK_READ]  — enqueue a PATCH notifications/:id/read in sync queue,
 *    cancel the notification.
 *
 * All IO (DB inserts) runs on a [CoroutineScope] backed by SupervisorJob +
 * Dispatchers.IO so the receiver returns immediately without calling
 * goAsync(). Toast must be dispatched to Main.
 *
 * Malformed intents (missing extras, empty reply text) are logged and
 * silently no-op — the notification is left in the shade so the user retains
 * visibility into the event.
 */
@AndroidEntryPoint
class NotificationActionReceiver : BroadcastReceiver() {

    @Inject
    lateinit var syncQueueDao: com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao

    @Inject
    lateinit var gson: Gson

    // Receiver scope — SupervisorJob prevents one failed coroutine killing siblings.
    private val receiverScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onReceive(context: Context, intent: Intent?) {
        if (intent == null) {
            Timber.w("NotificationActionReceiver: null intent — ignoring")
            return
        }

        val notificationId = intent.getIntExtra(EXTRA_NOTIFICATION_ID, -1)
        val entityId = intent.getLongExtra(EXTRA_ENTITY_ID, -1L)
        val entityType = intent.getStringExtra(EXTRA_ENTITY_TYPE)

        when (intent.action) {
            ACTION_REPLY_SMS -> handleReplySms(context, intent, notificationId, entityId)
            ACTION_MARK_READ -> handleMarkRead(context, intent, notificationId, entityId, entityType)
            else -> Timber.w("NotificationActionReceiver: unknown action=%s", intent.action)
        }
    }

    // ─── ACTION_REPLY_SMS ────────────────────────────────────────────────────────

    private fun handleReplySms(
        context: Context,
        intent: Intent,
        notificationId: Int,
        entityId: Long,
    ) {
        val threadPhone = intent.getStringExtra(EXTRA_THREAD_PHONE)
        if (threadPhone.isNullOrBlank()) {
            Timber.w("NotificationActionReceiver/reply: missing thread_phone extra")
            return
        }

        val replyBundle = RemoteInput.getResultsFromIntent(intent)
        val replyText = replyBundle?.getCharSequence(EXTRA_REPLY_TEXT)?.toString()?.trim()
        if (replyText.isNullOrBlank()) {
            Timber.w("NotificationActionReceiver/reply: empty reply text — ignoring")
            return
        }

        Timber.d("NotificationActionReceiver/reply: queuing SMS send phone=%s len=%d", threadPhone, replyText.length)

        receiverScope.launch {
            try {
                val payload = gson.toJson(mapOf("to" to threadPhone, "body" to replyText))
                syncQueueDao.insert(
                    SyncQueueEntity(
                        entityType = "sms",
                        entityId = entityId.takeIf { it > 0 } ?: 0L,
                        operation = "send",
                        payload = payload,
                    )
                )
                cancelNotification(context, notificationId)
                showToastOnMain(context, "Reply sent")
            } catch (e: Exception) {
                Timber.e(e, "NotificationActionReceiver/reply: failed to enqueue SMS send")
            }
        }
    }

    // ─── ACTION_MARK_READ ────────────────────────────────────────────────────────

    private fun handleMarkRead(
        context: Context,
        intent: Intent,
        notificationId: Int,
        entityId: Long,
        entityType: String?,
    ) {
        if (entityId <= 0) {
            Timber.w("NotificationActionReceiver/markRead: invalid entity_id=%d — ignoring", entityId)
            return
        }

        Timber.d("NotificationActionReceiver/markRead: queuing PATCH notifications/%d/read", entityId)

        receiverScope.launch {
            try {
                val payload = gson.toJson(mapOf("id" to entityId))
                syncQueueDao.insert(
                    SyncQueueEntity(
                        entityType = entityType ?: "notification",
                        entityId = entityId,
                        operation = "mark_read",
                        payload = payload,
                    )
                )
                cancelNotification(context, notificationId)
            } catch (e: Exception) {
                Timber.e(e, "NotificationActionReceiver/markRead: failed to enqueue mark-read")
            }
        }
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────────

    private fun cancelNotification(context: Context, id: Int) {
        if (id < 0) return
        try {
            NotificationManagerCompat.from(context).cancel(id)
        } catch (e: Exception) {
            Timber.w(e, "NotificationActionReceiver: failed to cancel notification id=%d", id)
        }
    }

    private fun showToastOnMain(context: Context, message: String) {
        // Toast must run on the Main thread. Post via Handler to avoid
        // "Can't create handler inside thread that has not called Looper.prepare()".
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            Toast.makeText(context.applicationContext, message, Toast.LENGTH_SHORT).show()
        }
    }
}
