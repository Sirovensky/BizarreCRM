package com.bizarreelectronics.crm.service

import android.app.PendingIntent
import android.content.Intent
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
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
        Log.d("FCM", "New FCM token received")
        appPreferences.fcmToken = token
        appPreferences.fcmTokenRegistered = false
        // Attempt to register with server if logged in
        if (authPreferences.isLoggedIn) {
            serviceScope.launch {
                try {
                    authApi.registerDeviceToken(mapOf("token" to token, "platform" to "android"))
                    appPreferences.fcmTokenRegistered = true
                    Log.d("FCM", "FCM token registered with server")
                } catch (e: Exception) {
                    Log.w("FCM", "Failed to register FCM token, will retry on next app launch", e)
                }
            }
        }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)

        val title = message.notification?.title ?: message.data["title"] ?: "Bizarre CRM"
        val body = message.notification?.body ?: message.data["body"] ?: ""
        val type = message.data["type"] ?: "system"
        val entityType = message.data["entity_type"]
        val entityId = message.data["entity_id"]

        val channelId = when (type) {
            "sms_received", "sms" -> "sms"
            "ticket_assigned", "ticket_updated", "customer_message" -> "tickets"
            "appointment_reminder" -> "appointments"
            else -> "sync"
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
            } else if (entityType != null) {
                Log.w("FCM", "Rejected unknown entity_type from FCM: $entityType")
            }
        }

        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        try {
            NotificationManagerCompat.from(this).notify(notificationIdCounter.getAndIncrement(), notification)
        } catch (e: SecurityException) {
            Log.w("FCM", "Notification permission not granted", e)
        }
    }
}
