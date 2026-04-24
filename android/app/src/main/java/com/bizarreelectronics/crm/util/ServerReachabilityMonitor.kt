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
import java.net.Inet4Address
import java.net.InetAddress
import java.security.SecureRandom
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.TrustManagerFactory
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

    /**
     * Lightweight OkHttp client for health checks — rebuilt when the target host changes.
     * FOLLOW-UP: the client is keyed to the last-seen host so that LAN vs cloud TLS
     * policy (see buildPingClient) is always correct for the current serverUrl.
     */
    @Volatile private var pingClient: OkHttpClient = buildPingClient()
    @Volatile private var pingClientHost: String = ""

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
        // No URL yet (e.g. user hasn't logged in / URL not committed yet).
        // Treat as "unknown" (optimistic true) rather than a server failure so the
        // ping loop does not accumulate consecutive-failure counts and flip
        // isEffectivelyOnline to false before the user has a chance to submit a ticket.
        // The next ping after serverUrl is populated will give a real result.
        if (serverUrl.isNullOrBlank()) return true

        // GET /api/v1/info is a lightweight endpoint that returns {lan_ip, port, server_url}
        // without requiring auth. It's the same endpoint the desktop setup wizard uses.
        val url = "${serverUrl.trimEnd('/')}/api/v1/info"

        // FOLLOW-UP: rebuild the ping client when the target host changes so the
        // LAN vs cloud TLS policy in buildPingClient is always applied correctly.
        val host = serverUrl.removePrefix("https://").removePrefix("http://")
            .split("/").first().split(":").first()
        if (host != pingClientHost) {
            pingClient = buildPingClient(host)
            pingClientHost = host
        }

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

// FOLLOW-UP: LAN-host predicate for the ping client — mirrors LoginViewModel.isLanHost
// and AuthInterceptor.isLanHost so the three call-sites stay consistent.
private val PING_LOOPBACK_HOSTS: Set<String> = setOf(
    "localhost", "10.0.2.2", "10.0.3.2", "127.0.0.1", "::1",
)

private fun isPingLanHost(hostname: String?): Boolean {
    if (hostname.isNullOrBlank()) return false
    val h = hostname.lowercase()
    if (h in PING_LOOPBACK_HOSTS) return true
    return try {
        val addr: InetAddress = InetAddress.getByName(h)
        if (addr !is Inet4Address) false
        else {
            val b = addr.address
            val b0 = b[0].toInt() and 0xff
            val b1 = b[1].toInt() and 0xff
            b0 == 10 || (b0 == 172 && b1 in 16..31) || (b0 == 192 && b1 == 168)
        }
    } catch (_: Exception) { false }
}

/**
 * Build a bare OkHttp client for health checks.
 * Short timeouts, no auth interceptors.
 *
 * FOLLOW-UP (trust-all fix): DEBUG now uses the same hostname-restricted TLS
 * policy as LoginViewModel.buildProbeTlsClient and AuthInterceptor.buildLogoutClient:
 * self-signed certs are accepted only for LAN/loopback hosts; cloud or public
 * hostnames always go through the platform CA + default hostname verifier even in
 * debug builds so credentials are never sent over an unverified chain.
 */
private fun buildPingClient(targetHost: String = ""): OkHttpClient {
    val builder = OkHttpClient.Builder()
        .connectTimeout(5, TimeUnit.SECONDS)
        .readTimeout(5, TimeUnit.SECONDS)
        .writeTimeout(5, TimeUnit.SECONDS)
        .callTimeout(6, TimeUnit.SECONDS)
        .retryOnConnectionFailure(false)

    if (BuildConfig.DEBUG && isPingLanHost(targetHost)) {
        try {
            val tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
            tmf.init(null as java.security.KeyStore?)
            val platformTm = tmf.trustManagers.filterIsInstance<X509TrustManager>().first()

            val lanTrustAll = object : X509TrustManager {
                override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) =
                    platformTm.checkClientTrusted(chain, authType)
                override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {
                    try { platformTm.checkServerTrusted(chain, authType) }
                    catch (_: CertificateException) { /* accept self-signed on LAN */ }
                }
                override fun getAcceptedIssuers(): Array<X509Certificate> = platformTm.acceptedIssuers
            }
            val sslCtx = SSLContext.getInstance("TLS")
            sslCtx.init(null, arrayOf<TrustManager>(lanTrustAll), SecureRandom())
            builder.sslSocketFactory(sslCtx.socketFactory, lanTrustAll)
            builder.hostnameVerifier { hn, session ->
                isPingLanHost(hn) || HttpsURLConnection.getDefaultHostnameVerifier().verify(hn, session)
            }
        } catch (_: Exception) { /* fall through to platform defaults */ }
    }
    // else: no custom TLS → OkHttp uses platform defaults (correct for release / cloud)
    return builder.build()
}
