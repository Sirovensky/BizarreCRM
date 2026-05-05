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
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import androidx.core.content.getSystemService
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.ui.screens.calls.CallInProgressActivity

/**
 * §42 — Foreground service that displays and manages an active call notification.
 *
 * foregroundServiceType uses two types:
 *   - FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK  (§42 requirement — call audio playback)
 *   - FOREGROUND_SERVICE_TYPE_PHONE_CALL      (API 34+ — telephony usage)
 *
 * On API < 34 we fall through to MEDIA_PLAYBACK only (PHONE_CALL is not available).
 *
 * The manifest declares the matching android:foregroundServiceType and the
 * FOREGROUND_SERVICE_MEDIA_PLAYBACK + FOREGROUND_SERVICE_PHONE_CALL permissions.
 *
 * FCM silent-push (high-priority data) → FcmService → CallNotificationService.start()
 * → vibrates + shows full-screen notification → tapping opens CallInProgressActivity.
 */
class CallNotificationService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val callId = intent?.getLongExtra(EXTRA_CALL_ID, -1L) ?: -1L
        val callerName = intent?.getStringExtra(EXTRA_CALLER_NAME) ?: "Unknown"
        val callerNumber = intent?.getStringExtra(EXTRA_CALLER_NUMBER) ?: ""
        val isIncoming = intent?.getBooleanExtra(EXTRA_IS_INCOMING, false) ?: false

        if (isIncoming) vibrate()

        val notification = buildNotification(callId, callerName, callerNumber, isIncoming)

        when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> {
                // API 34+: declare both mediaPlayback and phoneCall types
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK or
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL,
                )
            }
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q -> {
                // API 29–33: mediaPlayback only (PHONE_CALL type added in 34)
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
                )
            }
            else -> startForeground(NOTIFICATION_ID, notification)
        }

        return START_NOT_STICKY
    }

    // ── Notification ──────────────────────────────────────────────────────────

    private fun buildNotification(
        callId: Long,
        callerName: String,
        callerNumber: String,
        isIncoming: Boolean,
    ): Notification {
        ensureChannel()

        val fullScreenIntent = Intent(this, CallInProgressActivity::class.java).apply {
            putExtra(CallInProgressActivity.EXTRA_CALL_ID, callId)
            putExtra(CallInProgressActivity.EXTRA_CALLER_NAME, callerName)
            putExtra(CallInProgressActivity.EXTRA_CALLER_NUMBER, callerNumber)
            putExtra(CallInProgressActivity.EXTRA_IS_INCOMING, isIncoming)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val pendingFullScreen = PendingIntent.getActivity(
            this,
            callId.toInt().coerceAtLeast(0),
            fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        // Decline / hangup action
        val hangupIntent = Intent(this, CallNotificationService::class.java).apply {
            action = ACTION_HANGUP
            putExtra(EXTRA_CALL_ID, callId)
        }
        val pendingHangup = PendingIntent.getService(
            this, 1, hangupIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val title = if (isIncoming) "Incoming call from $callerName" else "Call with $callerName"
        val text = callerNumber

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setOngoing(true)
            .setFullScreenIntent(pendingFullScreen, /* highPriority= */ isIncoming)
            .setContentIntent(pendingFullScreen)
            .addAction(
                R.mipmap.ic_launcher,
                if (isIncoming) "Decline" else "Hang up",
                pendingHangup,
            )
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService<NotificationManager>() ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Calls",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Incoming and active call notifications"
            setShowBadge(true)
        }
        manager.createNotificationChannel(channel)
    }

    // ── Vibration ─────────────────────────────────────────────────────────────

    private fun vibrate() {
        val pattern = longArrayOf(0, 500, 200, 500, 200, 500)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vm = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
            vm?.defaultVibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } else {
            @Suppress("DEPRECATION")
            val v = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                v?.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                v?.vibrate(pattern, 0)
            }
        }
    }

    // ── Companion ─────────────────────────────────────────────────────────────

    companion object {
        private const val CHANNEL_ID = "call_notification"
        private const val NOTIFICATION_ID = 8531

        const val EXTRA_CALL_ID = "extra_call_id"
        const val EXTRA_CALLER_NAME = "extra_caller_name"
        const val EXTRA_CALLER_NUMBER = "extra_caller_number"
        const val EXTRA_IS_INCOMING = "extra_is_incoming"
        const val ACTION_HANGUP = "com.bizarreelectronics.crm.ACTION_HANGUP"

        fun start(
            context: Context,
            callId: Long,
            callerName: String,
            callerNumber: String,
            isIncoming: Boolean,
        ) {
            val intent = Intent(context, CallNotificationService::class.java).apply {
                putExtra(EXTRA_CALL_ID, callId)
                putExtra(EXTRA_CALLER_NAME, callerName)
                putExtra(EXTRA_CALLER_NUMBER, callerNumber)
                putExtra(EXTRA_IS_INCOMING, isIncoming)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, CallNotificationService::class.java))
        }
    }
}
