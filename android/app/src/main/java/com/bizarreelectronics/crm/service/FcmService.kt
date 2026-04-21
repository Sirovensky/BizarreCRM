package com.bizarreelectronics.crm.service

import android.app.PendingIntent
import android.content.Intent
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.bizarreelectronics.crm.BizarreCrmApp
import com.bizarreelectronics.crm.BuildConfig
import com.bizarreelectronics.crm.MainActivity
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.AuthApi
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicInteger
import javax.inject.Inject

@AndroidEntryPoint
class FcmService : FirebaseMessagingService() {

    @Inject lateinit var appPreferences: AppPreferences
    @Inject lateinit var authPreferences: AuthPreferences
    @Inject lateinit var authApi: AuthApi
    @Inject lateinit var quietHours: com.bizarreelectronics.crm.util.QuietHours
    @Inject lateinit var breadcrumbs: com.bizarreelectronics.crm.util.Breadcrumbs

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    companion object {
        private val notificationIdCounter = AtomicInteger(0)

        /**
         * Whitelist of entity types that can be passed via push notifications.
         * Prevents deep-link injection — a malicious FCM payload cannot navigate
         * to arbitrary routes by setting entity_type to something unexpected.
         */
        private val ALLOWED_ENTITY_TYPES = setOf(
            "ticket", "customer", "invoice", "inventory", "lead",
            "estimate", "expense", "appointment", "sms", "notification",
        )
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        // Never log the raw FCM token — it's a long-lived credential that,
        // combined with our FCM sender key, can let an attacker push to this
        // device. Gate all FCM diagnostics behind BuildConfig.DEBUG and
        // redact the token even then.
        if (BuildConfig.DEBUG) {
            Log.d("FCM", "New FCM token received (len=${token.length})")
        }
        appPreferences.fcmToken = token
        appPreferences.fcmTokenRegistered = false
        // Attempt to register with server if logged in
        if (authPreferences.isLoggedIn) {
            serviceScope.launch {
                try {
                    authApi.registerDeviceToken(mapOf("token" to token, "platform" to "android"))
                    appPreferences.fcmTokenRegistered = true
                    if (BuildConfig.DEBUG) {
                        Log.d("FCM", "FCM token registered with server")
                    }
                } catch (e: Exception) {
                    if (BuildConfig.DEBUG) {
                        Log.w("FCM", "Failed to register FCM token, will retry on next app launch", e)
                    }
                }
            }
        }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)

        val type = message.data["type"] ?: "system"
        breadcrumbs.log(
            com.bizarreelectronics.crm.util.Breadcrumbs.CAT_PUSH,
            "type=$type entity=${message.data["entity_type"]} id=${message.data["entity_id"]}",
        )

        // §13.2 / §21.3 — silent push: kick a one-shot delta sync via
        // WorkManager and skip posting any notification. The server uses
        // type=silent_sync (or sync=true in data) to nudge clients without
        // showing an alert. Must complete within 10s of FCM dispatch to
        // avoid Android killing the worker — handled by SyncWorker.syncNow
        // which schedules a OneTimeWorkRequest with EXPEDITED quota.
        val isSilent = type == "silent_sync" ||
            message.data["sync"]?.equals("true", ignoreCase = true) == true ||
            (message.notification == null && message.data["body"].isNullOrBlank())
        if (isSilent) {
            com.bizarreelectronics.crm.data.sync.SyncWorker.syncNow(this)
            return
        }

        val title = message.notification?.title ?: message.data["title"] ?: "Bizarre CRM"
        val body = message.notification?.body ?: message.data["body"] ?: ""
        val entityType = message.data["entity_type"]
        val entityId = message.data["entity_id"]

        // §13.2: route to the granular channels declared in
        // [BizarreCrmApp.createNotificationChannels]. New event types map to
        // the closest fit; unknown types fall through to CH_SYNC so the user
        // can still silence via Settings rather than being stuck with a
        // default-importance surprise.
        val channelId = when (type) {
            "sms_received", "sms" -> BizarreCrmApp.CH_SMS_INBOUND
            "ticket_assigned" -> BizarreCrmApp.CH_TICKET_ASSIGNED
            "ticket_updated", "customer_message" -> BizarreCrmApp.CH_TICKET_STATUS
            "appointment_reminder" -> BizarreCrmApp.CH_APPOINTMENT_REMINDER
            "sla_breach", "sla_amber", "sla_red" -> BizarreCrmApp.CH_SLA_BREACH
            "security_event", "session_revoked", "password_changed" -> BizarreCrmApp.CH_SECURITY_EVENT
            "payment_received", "invoice_paid", "deposit_received" -> BizarreCrmApp.CH_PAYMENT_RECEIVED
            "mention", "mentioned" -> BizarreCrmApp.CH_MENTION
            "low_stock", "inventory_low" -> BizarreCrmApp.CH_LOW_STOCK
            "daily_summary", "end_of_day" -> BizarreCrmApp.CH_DAILY_SUMMARY
            "backup_report", "backup_failed", "diagnostics" -> BizarreCrmApp.CH_BACKUP_REPORT
            else -> BizarreCrmApp.CH_SYNC
        }

        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            // Deep link data — validate entityType against whitelist to prevent injection.
            // entityId must also be a valid number.
            if (entityType != null && entityType in ALLOWED_ENTITY_TYPES &&
                entityId != null && entityId.toLongOrNull() != null
            ) {
                putExtra("navigate_to", entityType)
                putExtra("entity_id", entityId)
            } else if (entityType != null && BuildConfig.DEBUG) {
                Log.w("FCM", "Rejected unknown entity_type from FCM: $entityType")
            }
        }

        // AUDIT-AND-027: consume a single id from the counter and reuse it for
        // both the PendingIntent requestCode AND notify(). The old code called
        // .get() for PendingIntent and .getAndIncrement() for notify() — two
        // separate reads from the AtomicInteger — so a concurrent FCM message
        // received between those two calls could cause the PendingIntent to
        // point at the wrong notification slot or overwrite a sibling notification.
        val id = notificationIdCounter.getAndIncrement()

        val pendingIntent = PendingIntent.getActivity(
            this, id, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        // M1 fix: don't leak customer names, ticket numbers, or SMS bodies to
        // the lock screen. VISIBILITY_PRIVATE shows a generic "Bizarre CRM"
        // line on the lock screen and the full content only after unlock.
        // We also set a public alternate so the lock screen has something
        // sensible to render.
        val publicNotification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Bizarre CRM")
            .setContentText("New notification")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()

        // §13.2 quiet hours: silence non-critical channels during the user's
        // configured window. We keep the notification visible (still posts +
        // increments badge) but drop priority + clear sound/vibration so it
        // doesn't wake them. SLA breaches + security alerts ignore this and
        // keep priority HIGH per QuietHours.shouldSilence's allowlist.
        val silenced = quietHours.shouldSilence(channelId)
        // §13.4: launcher dot count — Samsung One UI + a few skins read
        // setNumber as the badge integer. Pass total active app
        // notifications + 1 (this one) so the dot stays accurate.
        val activeBefore = runCatching {
            (getSystemService(NOTIFICATION_SERVICE) as android.app.NotificationManager)
                .activeNotifications.size
        }.getOrDefault(0)
        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(if (silenced) NotificationCompat.PRIORITY_LOW else NotificationCompat.PRIORITY_HIGH)
            .apply {
                if (silenced) {
                    setSilent(true)
                    setDefaults(0)
                }
            }
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setNumber(activeBefore + 1)
            // M1 fix: keep the full payload off the lock screen.
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPublicVersion(publicNotification)
            .build()

        try {
            NotificationManagerCompat.from(this).notify(id, notification)
        } catch (e: SecurityException) {
            if (BuildConfig.DEBUG) {
                Log.w("FCM", "Notification permission not granted", e)
            }
        }
    }
}
