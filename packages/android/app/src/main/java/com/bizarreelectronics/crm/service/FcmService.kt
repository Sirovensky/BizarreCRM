package com.bizarreelectronics.crm.service

import android.app.PendingIntent
import android.content.Intent
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.bizarreelectronics.crm.MainActivity
import com.bizarreelectronics.crm.R
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import dagger.hilt.android.AndroidEntryPoint
import java.util.concurrent.atomic.AtomicInteger

@AndroidEntryPoint
class FcmService : FirebaseMessagingService() {

    companion object {
        private val notificationIdCounter = AtomicInteger(0)
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d("FCM", "New FCM token received")
        // TODO: Send token to server via POST /auth/register-device
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
            // Deep link data
            if (entityType != null && entityId != null) {
                putExtra("navigate_to", entityType)
                putExtra("entity_id", entityId)
            }
        }

        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.ic_dialog_info) // TODO: replace with app icon
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
