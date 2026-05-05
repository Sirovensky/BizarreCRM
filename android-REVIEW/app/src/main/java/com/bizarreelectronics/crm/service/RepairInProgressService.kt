package com.bizarreelectronics.crm.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.getSystemService
import com.bizarreelectronics.crm.MainActivity
import com.bizarreelectronics.crm.R

/**
 * Android's answer to iOS Live Activities: a foreground service with a
 * rich pinned notification that stays on the lock screen while a repair is
 * in progress. Technicians can glance at their pocket and see which ticket
 * they are working on without unlocking the device.
 *
 * Start the service when a ticket enters the "in_repair" status:
 *     RepairInProgressService.start(context, ticketId, "iPhone 14 screen")
 * Stop it when the repair ends (or when the ticket closes):
 *     RepairInProgressService.stop(context)
 *
 * Foreground-service type is DATA_SYNC because we do not fit any of the
 * stricter Android 14 categories (not media-playback, not location, not
 * phone-call) and this is the closest legitimate match for "long-running
 * work the user initiated." It is already declared in AndroidManifest.xml.
 */
class RepairInProgressService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val ticketId = intent?.getLongExtra(EXTRA_TICKET_ID, -1L) ?: -1L
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Repair in progress"
        val subtitle = intent?.getStringExtra(EXTRA_SUBTITLE) ?: "Tap to view ticket"

        val notification = buildNotification(ticketId, title, subtitle)

        // Android 14 (UPSIDE_DOWN_CAKE, SDK 34) requires startForeground to
        // declare the service type explicitly. Omitting this will crash on
        // newer devices even though the manifest already declares it.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        // AND-034: START_NOT_STICKY — the pinned-repair notification is
        // re-launched by the app when the user re-opens a ticket, not by the
        // OS on arbitrary restart. START_STICKY would cause the service to
        // restart with a null intent after being killed, producing a broken
        // "Repair in progress" notification with no ticket context.
        return START_NOT_STICKY
    }

    private fun buildNotification(
        ticketId: Long,
        title: String,
        subtitle: String,
    ): Notification {
        ensureChannel()

        val tapIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            if (ticketId > 0L) putExtra(EXTRA_TICKET_ID, ticketId)
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            ticketId.toInt().coerceAtLeast(0),
            tapIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(subtitle)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setStyle(NotificationCompat.BigTextStyle().bigText(subtitle))
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService<NotificationManager>() ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Repair in progress",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Pinned notification while a repair is in progress"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    companion object {
        private const val CHANNEL_ID = "repair_in_progress"
        private const val NOTIFICATION_ID = 7421

        const val EXTRA_TICKET_ID = "extra_ticket_id"
        const val EXTRA_TITLE = "extra_title"
        const val EXTRA_SUBTITLE = "extra_subtitle"

        fun start(context: Context, ticketId: Long, title: String, subtitle: String) {
            val intent = Intent(context, RepairInProgressService::class.java).apply {
                putExtra(EXTRA_TICKET_ID, ticketId)
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_SUBTITLE, subtitle)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, RepairInProgressService::class.java))
        }
    }
}
