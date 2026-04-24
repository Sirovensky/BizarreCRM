package com.bizarreelectronics.crm

import android.app.Application
import android.util.Log
import androidx.hilt.work.HiltWorkerFactory
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import androidx.work.Configuration
import coil3.SingletonImageLoader
import com.bizarreelectronics.crm.data.drafts.DraftStore
import com.bizarreelectronics.crm.service.NotificationChannelBootstrap
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.sync.SyncWorker
import com.bizarreelectronics.crm.service.WebSocketEventHandler
import com.bizarreelectronics.crm.service.WebSocketService
import com.bizarreelectronics.crm.util.FcmTokenRefresher
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

    @Inject
    lateinit var fcmTokenRefresher: FcmTokenRefresher

    @Inject
    lateinit var draftStore: DraftStore

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
        // §13 L1591 — channel creation is now in NotificationChannelBootstrap
        // so it can be tested and reused independently of Application lifecycle.
        NotificationChannelBootstrap.registerAll(this)
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
                        // §1.7 line 238 — refresh FCM push token if > 24 h stale.
                        // Runs on appScope (Dispatchers.Default → IO inside the helper)
                        // so the lifecycle callback returns immediately.
                        appScope.launch { fcmTokenRefresher.refreshIfStale() }
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

                    // §1.7 line 239 — flush any buffered draft writes before the
                    // process may be killed by the OEM task manager. DraftStore
                    // is currently write-through so this is a no-op; the call-site
                    // is wired now so no BizarreCrmApp change is needed when
                    // buffering is introduced (plan §1.6 lines 260-266).
                    appScope.launch { draftStore.flushPending() }

                    // FLAG_SECURE: wired reactively in MainActivity via
                    // AppPreferences.screenCapturePreventionFlow (plan §1.7 L239).

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
