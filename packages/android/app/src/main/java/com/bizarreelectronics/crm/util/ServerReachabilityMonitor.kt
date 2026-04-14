package com.bizarreelectronics.crm.util

import android.util.Log
import com.bizarreelectronics.crm.BuildConfig
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import okhttp3.Request
import java.security.SecureRandom
import java.security.cert.X509Certificate
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

/**
 * Source of truth for whether the app can talk to the configured CRM server.
 *
 * Design goals:
 *   1. The CRM server IS the online/offline test. We do NOT rely on third-party
 *      probes like Google's captive portal check — so Google being down, or the
 *      user's network blocking gstatic.com, will NEVER cause a false offline.
 *   2. Works identically for the configured cloud host and customer-hosted LAN/VPN
 *      instances, because the ping target is whatever `AuthPreferences.serverUrl`
 *      says it is. If the server lives at 192.168.1.50 and the user VPNs in,
 *      we ping through the VPN.
 *   3. Learns from real API traffic — when the OkHttp interceptor sees a
 *      successful response, it calls [reportSuccess]; when it catches a
 *      network exception, it calls [reportFailure]. This means the banner
 *      reacts instantly instead of waiting for the next 30s heartbeat.
 *   4. Recovers quickly. When in the offline state we ping every 5 seconds
 *      instead of 30, so users get "back online" feedback almost immediately
 *      once the server comes back.
 *   5. Tolerates transient failures. We require two consecutive failed pings
 *      before flipping to offline, to avoid flapping on a single dropped packet.
 */
@Singleton
class ServerReachabilityMonitor @Inject constructor(
    private val authPreferences: AuthPreferences,
    private val networkMonitor: NetworkMonitor,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var pingJob: Job? = null

    /** True until we have evidence otherwise (optimistic default). */
    private val _isServerReachable = MutableStateFlow(true)
    val isServerReachable: StateFlow<Boolean> = _isServerReachable

    /** Tracks consecutive failures so a single dropped packet doesn't flip us. */
    @Volatile private var consecutiveFailures: Int = 0

    /** Last server URL we pinged, so we can detect user switching servers. */
    @Volatile private var lastPingedUrl: String? = null

    /**
     * True only when the device has ANY network AND the configured server
     * responded to a recent health check. Collect this in the UI to drive
     * the offline banner.
     *
     * Note: `NetworkMonitor.isOnline` here just means "there's a network
     * interface we could try" — it does NOT depend on Google's captive
     * portal check (see NetworkMonitor docs).
     */
    val isEffectivelyOnline: StateFlow<Boolean> = combine(
        networkMonitor.isOnline,
        _isServerReachable,
    ) { hasInterface, serverReachable ->
        hasInterface && serverReachable
    }.distinctUntilChanged().stateIn(scope, SharingStarted.Eagerly, true)

    /** Lightweight OkHttp client for health checks only — no auth, short timeouts. */
    private val pingClient: OkHttpClient = buildPingClient()

    init {
        // Re-evaluate whenever the network interface changes.
        scope.launch {
            networkMonitor.isOnline.collect { hasInterface ->
                if (hasInterface) {
                    startPinging()
                } else {
                    stopPinging()
                    // No interface at all → definitely unreachable, and reset counter
                    // so we re-ping immediately when an interface comes back.
                    _isServerReachable.value = false
                    consecutiveFailures = 0
                }
            }
        }
    }

    /** Force an immediate reachability check. Returns true if server responded. */
    suspend fun checkNow(): Boolean {
        val reachable = pingServer()
        updateState(reachable)
        return reachable
    }

    /**
     * Called by the OkHttp interceptor when a real API request succeeds.
     * This is our fastest signal — if real traffic is flowing we know we're online.
     */
    fun reportSuccess() {
        consecutiveFailures = 0
        if (!_isServerReachable.value) {
            _isServerReachable.value = true
        }
    }

    /**
     * Called by the OkHttp interceptor when a real API request fails with a
     * network-level exception (not a 4xx/5xx, which still means the server
     * was reachable). One failure isn't enough to flip us — we require two
     * consecutive to avoid flapping.
     */
    fun reportFailure() {
        consecutiveFailures++
        if (consecutiveFailures >= FAILURES_BEFORE_OFFLINE && _isServerReachable.value) {
            _isServerReachable.value = false
            // Kick off an aggressive recovery loop so we flip back as soon as possible
            startPinging()
        }
    }

    private fun startPinging() {
        // If we're already pinging AND the URL hasn't changed, don't restart.
        val currentUrl = authPreferences.serverUrl
        if (pingJob?.isActive == true && lastPingedUrl == currentUrl) return

        // Server URL changed (e.g. user switched from cloud to LAN) → restart
        stopPinging()
        lastPingedUrl = currentUrl

        pingJob = scope.launch {
            // Immediate first check so the UI reacts fast
            updateState(pingServer())

            while (true) {
                // Ping more frequently while we're offline so we recover fast
                val interval = if (_isServerReachable.value) {
                    ONLINE_PING_INTERVAL_MS
                } else {
                    OFFLINE_PING_INTERVAL_MS
                }
                delay(interval)

                // If the user changed servers, restart the loop with the new URL
                if (authPreferences.serverUrl != lastPingedUrl) {
                    lastPingedUrl = authPreferences.serverUrl
                    consecutiveFailures = 0
                }

                updateState(pingServer())
            }
        }
    }

    private fun stopPinging() {
        pingJob?.cancel()
        pingJob = null
    }

    private fun updateState(reachable: Boolean) {
        if (reachable) {
            consecutiveFailures = 0
            if (!_isServerReachable.value) _isServerReachable.value = true
        } else {
            consecutiveFailures++
            if (consecutiveFailures >= FAILURES_BEFORE_OFFLINE && _isServerReachable.value) {
                _isServerReachable.value = false
            }
        }
    }

    private fun pingServer(): Boolean {
        val serverUrl = authPreferences.serverUrl
        if (serverUrl.isNullOrBlank()) return false

        // GET /api/v1/info is a lightweight endpoint that returns {lan_ip, port, server_url}
        // without requiring auth. It's the same endpoint the desktop setup wizard uses.
        val url = "${serverUrl.trimEnd('/')}/api/v1/info"
        return try {
            val request = Request.Builder()
                .url(url)
                .get()
                .header("User-Agent", "BizarreCRM-Android/Health")
                .build()
            val response = pingClient.newCall(request).execute()
            // Any 2xx means the server is up. Even a 401/403 means the server
            // is reachable — it's just refusing us, which is also "online".
            val reachable = response.code in 200..499
            response.close()
            if (!reachable) {
                Log.d(TAG, "Server ping returned ${response.code} (treated as unreachable)")
            }
            reachable
        } catch (e: Exception) {
            Log.d(TAG, "Server ping failed: ${e.javaClass.simpleName}: ${e.message}")
            false
        }
    }

    companion object {
        private const val TAG = "ServerReachability"
        private const val ONLINE_PING_INTERVAL_MS = 30_000L  // 30s when healthy
        private const val OFFLINE_PING_INTERVAL_MS = 5_000L  // 5s while recovering
        private const val FAILURES_BEFORE_OFFLINE = 2        // 2 consecutive fails → offline
    }
}

/**
 * Build a bare OkHttp client for health checks.
 * Short timeouts, no auth interceptors, SSL bypass in debug (for self-signed LAN certs).
 */
private fun buildPingClient(): OkHttpClient {
    val builder = OkHttpClient.Builder()
        .connectTimeout(5, TimeUnit.SECONDS)
        .readTimeout(5, TimeUnit.SECONDS)
        .writeTimeout(5, TimeUnit.SECONDS)
        .retryOnConnectionFailure(false)

    if (BuildConfig.DEBUG) {
        val trustAllCerts = arrayOf<TrustManager>(object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) {}
            override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {}
            override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()
        })
        val sslContext = SSLContext.getInstance("TLS")
        sslContext.init(null, trustAllCerts, SecureRandom())
        builder.sslSocketFactory(sslContext.socketFactory, trustAllCerts[0] as X509TrustManager)
        builder.hostnameVerifier { _, _ -> true }
    }

    return builder.build()
}
