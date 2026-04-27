package com.bizarreelectronics.crm.service

import android.annotation.SuppressLint
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
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.getSystemService
import com.bizarreelectronics.crm.MainActivity
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.data.repository.DispatchRepository
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Foreground service that sends periodic GPS pings to the server while a tech
 * is travelling to a job (status = en_route).
 *
 * Usage:
 *   LocationTrackingService.start(context, jobId)   // begin pinging
 *   LocationTrackingService.stop(context)            // stop pinging
 *
 * Foreground service type is LOCATION (declared in AndroidManifest).
 * ACCESS_FINE_LOCATION is already declared in the manifest.
 *
 * The service pings once every [PING_INTERVAL_MS] ms using FusedLocationProvider.
 * Pings are best-effort: if the server is offline or the transition is no longer
 * valid, the repository swallows the error silently.
 *
 * NOTE: GPS without a physical device cannot be tested in the emulator without
 * manually setting mock coordinates in Android Studio's Extended Controls.
 * The service will function correctly but location data will be (0.0, 0.0) or
 * whatever the emulator reports unless mock coordinates are set.
 *
 * NOTE: FOREGROUND_SERVICE_LOCATION permission and android:foregroundServiceType="location"
 * are required for API 34+ and must be added to AndroidManifest.xml before this
 * service can start on Android 14+ devices. See companion START method note below.
 */
@AndroidEntryPoint
class LocationTrackingService : Service() {

    @Inject
    lateinit var repository: DispatchRepository

    private lateinit var fusedLocationClient: FusedLocationProviderClient
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private var activeJobId: Long = -1L
    private var locationCallback: LocationCallback? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        activeJobId = intent?.getLongExtra(EXTRA_JOB_ID, -1L) ?: -1L
        val customerName = intent?.getStringExtra(EXTRA_CUSTOMER_NAME) ?: "Job"

        if (activeJobId <= 0L) {
            Log.w(TAG, "onStartCommand: invalid job ID — stopping service")
            stopSelf()
            return START_NOT_STICKY
        }

        val notification = buildNotification(customerName)

        // Android 14+ requires explicit foregroundServiceType in startForeground.
        // FOREGROUND_SERVICE_TYPE_LOCATION is the correct type for GPS tracking.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        startLocationUpdates()

        // START_NOT_STICKY: the service is only meaningful while a job is active.
        // If the OS kills it, the tech will need to re-open the app to resume tracking.
        return START_NOT_STICKY
    }

    @SuppressLint("MissingPermission")
    private fun startLocationUpdates() {
        locationCallback?.let { fusedLocationClient.removeLocationUpdates(it) }

        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, PING_INTERVAL_MS)
            .setMinUpdateIntervalMillis(MIN_UPDATE_INTERVAL_MS)
            .build()

        locationCallback = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                val location = result.lastLocation ?: return
                val jobId = activeJobId
                if (jobId <= 0L) return

                serviceScope.launch {
                    repository.pingLocation(
                        jobId = jobId,
                        lat = location.latitude,
                        lng = location.longitude,
                    )
                }
            }
        }

        try {
            fusedLocationClient.requestLocationUpdates(
                request,
                locationCallback!!,
                Looper.getMainLooper(),
            )
            Log.i(TAG, "Location updates started for job $activeJobId")
        } catch (e: SecurityException) {
            // ACCESS_FINE_LOCATION not granted at runtime — service cannot track.
            // The caller should check permission before starting the service.
            Log.e(TAG, "Missing location permission — stopping service: ${e.message}")
            stopSelf()
        }
    }

    override fun onDestroy() {
        Log.i(TAG, "onDestroy — stopping location updates for job $activeJobId")
        locationCallback?.let { fusedLocationClient.removeLocationUpdates(it) }
        serviceScope.cancel()
        super.onDestroy()
    }

    private fun buildNotification(customerName: String): Notification {
        ensureChannel()
        val tapIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Navigating to job")
            .setContentText(customerName)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(tapIntent)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_NAVIGATION)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService<NotificationManager>() ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Field service navigation",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Active while navigating to a field-service job"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    companion object {
        private const val TAG = "LocationTrackingService"
        private const val CHANNEL_ID = "field_service_location"
        private const val NOTIFICATION_ID = 7501
        private const val PING_INTERVAL_MS = 60_000L      // 1 minute between pings
        private const val MIN_UPDATE_INTERVAL_MS = 30_000L // fastest possible update

        const val EXTRA_JOB_ID = "extra_job_id"
        const val EXTRA_CUSTOMER_NAME = "extra_customer_name"

        /**
         * Starts the location tracking foreground service.
         *
         * NOTE: Caller must ensure ACCESS_FINE_LOCATION is granted at runtime
         * before calling this method, and that the following are in AndroidManifest.xml:
         *   <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
         *   <service android:foregroundServiceType="location" ... />
         *
         * Without those, the service will crash on Android 14+ or log a SecurityException
         * on older versions. See AndroidManifest additions required in the task notes.
         */
        fun start(context: Context, jobId: Long, customerName: String) {
            val intent = Intent(context, LocationTrackingService::class.java).apply {
                putExtra(EXTRA_JOB_ID, jobId)
                putExtra(EXTRA_CUSTOMER_NAME, customerName)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, LocationTrackingService::class.java))
        }
    }
}
