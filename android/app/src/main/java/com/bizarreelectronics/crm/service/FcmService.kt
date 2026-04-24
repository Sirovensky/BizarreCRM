package com.bizarreelectronics.crm.service

import android.util.Log
import androidx.core.app.NotificationManagerCompat
import com.bizarreelectronics.crm.BizarreCrmApp
import com.bizarreelectronics.crm.BuildConfig
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

        // §1.7 L244 — Route notification-carrying payloads through NotificationController.
        // Controller parses type, entity_id, navigate_to, title, body, thread_phone and
        // returns a fully-built Notification with action buttons (Reply / Mark as read).
        // Quiet-hours and badge count are applied below after the controller returns.
        val data = buildMap<String, String> {
            // Merge RemoteMessage notification fields into the data map so the
            // controller has a single source of truth regardless of whether the
            // server sent a notification block or a pure data message.
            message.notification?.title?.let { put("title", it) }
            message.notification?.body?.let { put("body", it) }
            putAll(message.data)
            // Validate entity_type against whitelist — reject unknown types to
            // prevent deep-link injection attacks (same guard as old inline code).
            val entityType = message.data["entity_type"]
            val entityId = message.data["entity_id"]
            if (entityType != null && entityType !in ALLOWED_ENTITY_TYPES) {
                remove("entity_type")
                remove("entity_id")
                remove("navigate_to")
                if (BuildConfig.DEBUG) {
                    Log.w("FCM", "Rejected unknown entity_type from FCM: $entityType")
                }
            } else if (entityId != null && entityId.toLongOrNull() == null) {
                // entity_id is present but not a valid Long — strip both.
                remove("entity_id")
                if (BuildConfig.DEBUG) {
                    Log.w("FCM", "Rejected non-numeric entity_id from FCM: $entityId")
                }
            }
        }

        // §13.2 quiet hours: decide silence before building so the controller stamps
        // the right priority from the start. Re-derive channel from data to avoid
        // inspecting the not-yet-built Notification.
        val quietChannelId = when (val t = data["type"] ?: "system") {
            "sms_inbound", "sms" -> BizarreCrmApp.CH_SMS_INBOUND
            "ticket_assigned" -> BizarreCrmApp.CH_TICKET_ASSIGNED
            "ticket_updated", "customer_message" -> BizarreCrmApp.CH_TICKET_STATUS
            "appointment_reminder" -> BizarreCrmApp.CH_APPOINTMENT_REMINDER
            else -> if (t.startsWith("sla_")) BizarreCrmApp.CH_SLA_BREACH else BizarreCrmApp.CH_SYNC
        }
        val silenced = quietHours.shouldSilence(quietChannelId)

        // §13.4: launcher dot count — Samsung One UI + a few skins read setNumber.
        val activeBefore = runCatching {
            (getSystemService(NOTIFICATION_SERVICE) as android.app.NotificationManager)
                .activeNotifications.size
        }.getOrDefault(0)

        // Pass quiet-hours and badge hints to the controller so it builds a single,
        // fully-correct Notification without requiring FcmService to re-wrap it.
        val enriched = data.toMutableMap().apply {
            if (silenced) put("_quiet_override", "true")
            put("_badge_count", (activeBefore + 1).toString())
        }

        val (id, notification) = NotificationController.handle(this, enriched)

        try {
            NotificationManagerCompat.from(this).notify(id, notification)
        } catch (e: SecurityException) {
            if (BuildConfig.DEBUG) {
                Log.w("FCM", "Notification permission not granted", e)
            }
        }
    }
}
