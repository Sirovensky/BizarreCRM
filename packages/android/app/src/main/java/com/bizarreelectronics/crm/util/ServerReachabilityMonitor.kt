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
 * Monitors whether the configured CRM server is reachable.
 *
 * Combines Android connectivity state from [NetworkMonitor] with an active server
 * health check (pings `{serverUrl}/api/v1/info` every 30 seconds) to determine
 * if the app can actually communicate with the backend.
 *
 * Works for both the public server (bizarrecrm.com) and customer local LAN instances.
 */
@Singleton
class ServerReachabilityMonitor @Inject constructor(
    private val authPreferences: AuthPreferences,
    private val networkMonitor: NetworkMonitor,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var pingJob: Job? = null

    private val _isServerReachable = MutableStateFlow(true) // Optimistic default
    val isServerReachable: StateFlow<Boolean> = _isServerReachable

    /**
     * True only when the device has internet AND the server responded to a health check.
     * Collect this in the UI to drive the offline banner.
     */
    val isEffectivelyOnline: StateFlow<Boolean> = combine(
        networkMonitor.isOnline,
        _isServerReachable,
    ) { hasInternet, serverReachable ->
        hasInternet && serverReachable
    }.distinctUntilChanged().stateIn(scope, SharingStarted.Eagerly, true)

    /** Lightweight OkHttp client for health checks only — no auth, short timeouts. */
    private val pingClient: OkHttpClient = buildPingClient()

    init {
        scope.launch {
            networkMonitor.isOnline.collect { online ->
                if (online) {
                    startPinging()
                } else {
                    stopPinging()
                    _isServerReachable.value = false
                }
            }
        }
    }

    /** Force an immediate reachability check. Returns true if server responded. */
    suspend fun checkNow(): Boolean {
        val reachable = pingServer()
        _isServerReachable.value = reachable
        return reachable
    }

    private fun startPinging() {
        // Don't start a second loop
        if (pingJob?.isActive == true) return

        pingJob = scope.launch {
            // Immediate first check
            _isServerReachable.value = pingServer()

            // Then every 30 seconds
            while (true) {
                delay(PING_INTERVAL_MS)
                _isServerReachable.value = pingServer()
            }
        }
    }

    private fun stopPinging() {
        pingJob?.cancel()
        pingJob = null
    }

    private fun pingServer(): Boolean {
        val serverUrl = authPreferences.serverUrl
        if (serverUrl.isNullOrBlank()) return false

        val url = "${serverUrl.trimEnd('/')}/api/v1/info"
        return try {
            val request = Request.Builder().url(url).get().build()
            val response = pingClient.newCall(request).execute()
            val success = response.isSuccessful
            response.close()
            if (!success) {
                Log.d(TAG, "Server ping failed: HTTP ${response.code}")
            }
            success
        } catch (e: Exception) {
            Log.d(TAG, "Server unreachable: ${e.message}")
            false
        }
    }

    companion object {
        private const val TAG = "ServerReachability"
        private const val PING_INTERVAL_MS = 30_000L
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
