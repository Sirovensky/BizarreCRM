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

    @Inject
    lateinit var sessionRepository: com.bizarreelectronics.crm.data.repository.SessionRepository

    // AND-035: use Dispatchers.Default so the scope does not hold the Main
    // thread dispatcher alive. The observeReconnect collector is pure state
    // logic (no UI writes) — any UI-touching work must dispatch explicitly
    // to Dispatchers.Main inside the coroutine body.
    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setWorkerFactory(workerFactory)
            .build()

    override fun onCreate() {
        System.loadLibrary("sqlcipher")
        super.onCreate()
        createNotificationChannels()
        SyncWorker.schedule(this)
        observeReconnect()
        startWebSocket()
        // §2.11 — confirm session validity + refresh user identity in the
        // background so role/permission UI doesn't render stale until the
        // next time the user pulls a list.
        sessionRepository.bootstrap()
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

    /**
     * §13 notification channels — full granular set. Channel IDs must match
     * the `channel_id` payload coming from the server so per-category mutes
     * in system Settings → Notifications carry through. IDs are namespaced
     * plain strings (never reshuffle — users' per-channel settings key by
     * these IDs forever).
     *
     * Importance levels are chosen per-channel so the user can mute a
     * subset without killing the whole app:
     *   - HIGH: sms_inbound, appointment_reminder, sla_breach, security_event
     *   - DEFAULT: ticket_assigned, ticket_status, payment_received, mention
     *   - LOW: low_stock, daily_summary, sync, backup_report
     */
    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)

        val channels = listOf(
            // — High-importance (heads-up + sound) —
            NotificationChannel(CH_SMS_INBOUND, "SMS — incoming", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "New SMS messages from customers."
            },
            NotificationChannel(CH_APPOINTMENT_REMINDER, "Appointment reminder", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Upcoming appointment reminders."
            },
            NotificationChannel(CH_SLA_BREACH, "SLA breach", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Ticket SLA amber / red alerts."
            },
            NotificationChannel(CH_SECURITY_EVENT, "Security alerts", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Unusual sign-ins, session revokes, password changes."
            },

            // — Default-importance (banner + sound) —
            NotificationChannel(CH_TICKET_ASSIGNED, "Ticket assigned to you", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "You were assigned a ticket."
            },
            NotificationChannel(CH_TICKET_STATUS, "Ticket status changes", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Status updates on tickets you follow."
            },
            NotificationChannel(CH_PAYMENT_RECEIVED, "Payment received", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Invoice payments and deposits."
            },
            NotificationChannel(CH_MENTION, "You were @mentioned", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "You were tagged in a note, message, or chat."
            },

            // — Low-importance (silent) —
            NotificationChannel(CH_LOW_STOCK, "Low-stock alerts", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Inventory items below reorder threshold."
            },
            NotificationChannel(CH_DAILY_SUMMARY, "Daily summary", NotificationManager.IMPORTANCE_LOW).apply {
                description = "End-of-day totals and activity digest."
            },
            NotificationChannel(CH_SYNC, "Background sync", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Data synchronization progress."
            },
            NotificationChannel(CH_BACKUP_REPORT, "Backup & diagnostics", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Backup results, crash reports, diagnostic logs."
            },
        )

        channels.forEach { manager.createNotificationChannel(it) }

        // Legacy channel IDs ("sms", "tickets", "appointments") used by a
        // previous version. They auto-resurrect in settings if we keep
        // posting to them, so we delete them cleanly once the new channels
        // are registered. No-op on fresh installs that never had them.
        listOf("sms", "tickets", "appointments").forEach { legacy ->
            runCatching { manager.deleteNotificationChannel(legacy) }
        }
    }

    companion object {
        const val CH_SMS_INBOUND = "sms_inbound"
        const val CH_APPOINTMENT_REMINDER = "appointment_reminder"
        const val CH_SLA_BREACH = "sla_breach"
        const val CH_SECURITY_EVENT = "security_event"
        const val CH_TICKET_ASSIGNED = "ticket_assigned"
        const val CH_TICKET_STATUS = "ticket_status"
        const val CH_PAYMENT_RECEIVED = "payment_received"
        const val CH_MENTION = "mention"
        const val CH_LOW_STOCK = "low_stock"
        const val CH_DAILY_SUMMARY = "daily_summary"
        const val CH_SYNC = "sync"
        const val CH_BACKUP_REPORT = "backup_report"
    }
}
