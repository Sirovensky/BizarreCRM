package com.bizarreelectronics.crm

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.util.Log
import androidx.hilt.work.HiltWorkerFactory
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import androidx.work.Configuration
import coil3.SingletonImageLoader
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.sync.SyncWorker
import com.bizarreelectronics.crm.service.WebSocketEventHandler
import com.bizarreelectronics.crm.service.WebSocketService
import com.bizarreelectronics.crm.util.RedactorTree
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import com.bizarreelectronics.crm.util.SessionTimeout
import dagger.hilt.android.HiltAndroidApp
import timber.log.Timber
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

    @Inject
    lateinit var crashReporter: com.bizarreelectronics.crm.util.CrashReporter

    @Inject
    lateinit var sessionTimeout: SessionTimeout

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
        // §1 L228 / §28 L64 — plant Timber with a RedactorTree so all
        // Timber calls are sanitised before reaching Logcat or the delegate
        // tree. RedactorTree strips sensitive key-value pairs and then
        // delegates PII sweeps (tokens, email, phone, IMEI) to LogRedactor.
        // Must be planted BEFORE crashReporter.install() so that any
        // Timber usage during crash-reporter wiring is also covered.
        val baseTree: Timber.Tree = if (BuildConfig.DEBUG) Timber.DebugTree()
        else Timber.DebugTree() // TODO: replace with CrashReporterTree once a
        // dedicated Timber-based release tree exists (currently CrashReporter
        // operates as an UncaughtExceptionHandler, not a Timber.Tree).
        Timber.plant(RedactorTree(baseTree))
        // §32.3 — wire the uncaught-exception handler before anything else
        // so init-path crashes are still captured.
        crashReporter.install()
        createNotificationChannels()
        SyncWorker.schedule(this)
        observeReconnect()
        startWebSocket()
        // §2.11 — confirm session validity + refresh user identity in the
        // background so role/permission UI doesn't render stale until the
        // next time the user pulls a list.
        sessionRepository.bootstrap()
        // §1.6 — process foreground/background hooks. ON_START fires whenever
        // the user comes back to the app from another task; we use it to
        // re-validate the session + kick a delta sync so screens never linger
        // on stale data after a long background pause.
        //
        // OEM task-killer invariant (plan §1.6 line 240):
        // Application termination is rarely predictable on Android — OEM
        // "killers" (Samsung, Xiaomi, Huawei RAM managers) can destroy the
        // process at any point without calling onDestroy. DO NOT rely on
        // a terminate/destroy callback to flush state. Instead, persist
        // every meaningful field change immediately to Room/DataStore at the
        // call-site of the change. Lifecycle observer onStop is the last
        // reliable signal before the user can no longer see the app; use it
        // to schedule background work and seal security-sensitive surfaces,
        // but never as the sole persistence gate.
        ProcessLifecycleOwner.get().lifecycle.addObserver(
            object : DefaultLifecycleObserver {
                override fun onStart(owner: LifecycleOwner) {
                    if (authPreferences.isLoggedIn) {
                        sessionRepository.bootstrap()
                        SyncWorker.syncNow(this@BizarreCrmApp)
                        if (!webSocketService.isConnected) {
                            webSocketService.connect()
                        }
                    }
                    // §2.16 — resume the session-timeout ticker on foreground.
                    sessionTimeout.onAppForeground()
                }

                override fun onStop(owner: LifecycleOwner) {
                    // §1.6 line 239 — app moved to background.

                    // Delta-sync: ensure the periodic WorkManager job is
                    // registered (KEEP policy means an existing enqueue is
                    // left untouched, so this is idempotent with the onCreate
                    // call above — it re-registers only if the system cleared
                    // the schedule, e.g. after a force-stop recovery).
                    SyncWorker.schedule(this@BizarreCrmApp)

                    // §1.6 L239 — Clipboard seal: clear the clipboard if it
                    // holds a value placed by ClipboardUtil.copySensitive().
                    // Detection is marker-based (ClipDescription label / extras)
                    // — never content-based — so user-copied text is never
                    // touched. No-op when no sensitive clip is active.
                    com.bizarreelectronics.crm.util.ClipboardUtil
                        .clearSensitiveIfPresent(this@BizarreCrmApp)

                    // Draft persistence: no draft system exists yet.
                    // TODO: flush unsaved form drafts to DataStore here once
                    //   the draft subsystem ships (plan §1.6 lines 260–266).

                    // FLAG_SECURE: window flags must be set at the Activity
                    // level, not here. An Application observer has no window
                    // reference. TODO: integrate via MainActivity once the
                    //   screen-capture privacy setting is wired (plan §1.6).

                    // §2.16 — background time counts toward inactivity window.
                    sessionTimeout.onAppBackground()
                }
            },
        )
    }

    /**
     * §1.6 line 241 — Memory-pressure callback invoked by the OS when it needs
     * the app to release non-critical memory. Only caches are evicted; active
     * session data and Room entities are never freed here.
     *
     * Level thresholds (ascending severity):
     *   TRIM_MEMORY_UI_HIDDEN (20)     — UI no longer visible; moderate trim.
     *   TRIM_MEMORY_RUNNING_LOW (10)   — system running low; shed caches now.
     *   TRIM_MEMORY_RUNNING_CRITICAL (12) — critical; every byte counts.
     *   TRIM_MEMORY_BACKGROUND (40)    — process in LRU list; free aggressively.
     *   TRIM_MEMORY_MODERATE (60)      — middle of LRU; free more.
     *   TRIM_MEMORY_COMPLETE (80)      — about to be killed; free everything.
     *
     * We act on RUNNING_LOW (10) or any more-severe level. At RUNNING_CRITICAL
     * and above the Coil memory cache is also pruned to its minimum.
     *
     * INVARIANT: never free active data (Room cursor results, in-flight network
     * payloads, authenticated session tokens). Only discard reconstructible
     * caches — image bitmaps already decoded from the server.
     */
    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        if (level >= TRIM_MEMORY_RUNNING_LOW) {
            // Clear the Coil in-memory bitmap cache. Coil 3 uses
            // SingletonImageLoader as the global accessor. The disk cache is
            // left intact — network traffic is more expensive than disk reads.
            val memCache = SingletonImageLoader.get(this).memoryCache
            if (memCache != null) {
                memCache.clear()
                Log.d(TAG, "onTrimMemory(level=$level): Coil memory cache cleared")
            }
        }
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
                setShowBadge(true)
            },
            NotificationChannel(CH_APPOINTMENT_REMINDER, "Appointment reminder", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Upcoming appointment reminders."
                setShowBadge(true)
            },
            NotificationChannel(CH_SLA_BREACH, "SLA breach", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Ticket SLA amber / red alerts."
                setShowBadge(true)
            },
            NotificationChannel(CH_SECURITY_EVENT, "Security alerts", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Unusual sign-ins, session revokes, password changes."
                setShowBadge(true)
            },

            // — Default-importance (banner + sound) —
            NotificationChannel(CH_TICKET_ASSIGNED, "Ticket assigned to you", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "You were assigned a ticket."
                setShowBadge(true)
            },
            NotificationChannel(CH_TICKET_STATUS, "Ticket status changes", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Status updates on tickets you follow."
                setShowBadge(true)
            },
            NotificationChannel(CH_PAYMENT_RECEIVED, "Payment received", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Invoice payments and deposits."
                setShowBadge(true)
            },
            NotificationChannel(CH_MENTION, "You were @mentioned", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "You were tagged in a note, message, or chat."
                setShowBadge(true)
            },

            // — Low-importance (silent) — no launcher dot for these; the
            // user opted into low-importance by definition, no point
            // pulling them back via the dot.
            NotificationChannel(CH_LOW_STOCK, "Low-stock alerts", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Inventory items below reorder threshold."
                setShowBadge(false)
            },
            NotificationChannel(CH_DAILY_SUMMARY, "Daily summary", NotificationManager.IMPORTANCE_LOW).apply {
                description = "End-of-day totals and activity digest."
                setShowBadge(false)
            },
            NotificationChannel(CH_SYNC, "Background sync", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Data synchronization progress."
                setShowBadge(false)
            },
            NotificationChannel(CH_BACKUP_REPORT, "Backup & diagnostics", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Backup results, crash reports, diagnostic logs."
                setShowBadge(false)
            },

            // §1.7 L245 — silent SMS dedup: badge only, no sound/vibration.
            // Created here alongside all other channels so the user sees it in
            // Settings → Notifications → Bizarre CRM → SMS (silent dedup).
            NotificationChannel(CH_SMS_SILENT, "SMS — silent (conversation open)", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Badge-only update when a new SMS arrives for a thread you are currently viewing."
                setShowBadge(true)
                setSound(null, null)
                enableVibration(false)
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
        private const val TAG = "BizarreCrmApp"

        // ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW = 10. Declared here as a
        // named constant so the onTrimMemory body reads without a magic number.
        // Using the ComponentCallbacks2 interface constant would require
        // implementing the interface explicitly; the named alias is cleaner.
        private const val TRIM_MEMORY_RUNNING_LOW = 10

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

        // §1.7 L245 — silent dedup channel for SMS while the thread is open.
        // IMPORTANCE_LOW: updates the shade badge without sound or vibration.
        const val CH_SMS_SILENT = "sms_silent"
    }
}
