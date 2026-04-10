package com.bizarreelectronics.crm

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import androidx.hilt.work.HiltWorkerFactory
import androidx.work.Configuration
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.sync.SyncWorker
import com.bizarreelectronics.crm.service.WebSocketEventHandler
import com.bizarreelectronics.crm.service.WebSocketService
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import dagger.hilt.android.HiltAndroidApp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltAndroidApp
class BizarreCrmApp : Application(), Configuration.Provider {

    @Inject
    lateinit var workerFactory: HiltWorkerFactory

    @Inject
    lateinit var serverReachabilityMonitor: ServerReachabilityMonitor

    @Inject
    lateinit var webSocketService: WebSocketService

    @Inject
    lateinit var webSocketEventHandler: WebSocketEventHandler

    @Inject
    lateinit var authPreferences: AuthPreferences

    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setWorkerFactory(workerFactory)
            .build()

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
        SyncWorker.schedule(this)
        observeReconnect()
        startWebSocket()
    }

    /** Connect WebSocket for real-time SMS and ticket updates. */
    private fun startWebSocket() {
        if (authPreferences.isLoggedIn && !authPreferences.serverUrl.isNullOrBlank()) {
            webSocketService.connect()
            webSocketEventHandler.startListening()
        }
    }

    /**
     * Watch for server reconnection (false → true transition on isEffectivelyOnline)
     * and trigger an immediate sync to push queued changes and pull fresh data.
     */
    private fun observeReconnect() {
        appScope.launch {
            var wasOffline = false
            serverReachabilityMonitor.isEffectivelyOnline
                .collect { online ->
                    if (online && wasOffline) {
                        SyncWorker.syncNow(this@BizarreCrmApp)
                        // Reconnect WebSocket after coming back online
                        if (!webSocketService.isConnected && authPreferences.isLoggedIn) {
                            webSocketService.connect()
                        }
                    }
                    wasOffline = !online
                }
        }
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)

            val channels = listOf(
                NotificationChannel("sms", "SMS Messages", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "New SMS messages from customers"
                },
                NotificationChannel("tickets", "Ticket Updates", NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = "Ticket status changes and assignments"
                },
                NotificationChannel("appointments", "Appointments", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "Upcoming appointment reminders"
                },
                NotificationChannel("sync", "Background Sync", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Data synchronization status"
                },
            )

            channels.forEach { manager.createNotificationChannel(it) }
        }
    }
}
