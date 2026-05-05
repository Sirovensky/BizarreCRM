package com.bizarreelectronics.crm.service

import android.util.Log
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.sync.SyncWorker
import com.google.gson.Gson
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import okhttp3.*
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import javax.inject.Inject
import javax.inject.Singleton

data class WsEvent(val type: String, val data: String)

/**
 * Manages the persistent WebSocket connection to the CRM server.
 *
 * ## Heartbeat (§21.8)
 *
 * A ping frame is sent every [HEARTBEAT_INTERVAL_MS] (20 s). The server must
 * respond with a pong (OkHttp handles this automatically via its own ping/pong
 * frame handling). If no frame of any kind is received within [DEAD_INTERVAL_MS]
 * (45 s) the connection is considered dead and [scheduleReconnect] is called.
 *
 * OkHttp's [OkHttpClient.pingIntervalMillis] handles the low-level TCP keepalive
 * independently of our application-level heartbeat JSON messages. The two layers
 * complement each other: OkHttp pings keep the TCP socket alive through NAT
 * tables; our application ping lets the server know the client is still present
 * and reachable through any intermediate proxy.
 *
 * ## Fallback polling (§21.8)
 *
 * When the WebSocket connection cannot be established after [MAX_RECONNECT_ATTEMPTS]
 * retries (e.g. a corporate firewall or proxy strips Upgrade headers), we fall back
 * to kicking [SyncWorker.syncNow] every [POLLING_INTERVAL_MS] (30 s). This ensures
 * data stays fresh even in hostile network environments where WebSocket is blocked.
 * The polling loop stops as soon as a WebSocket connection succeeds.
 *
 * ## Reconnect (§21.8)
 *
 * Exponential back-off (1 s → 30 s cap, 10 attempts) before giving up and
 * entering polling mode.
 */
@Singleton
class WebSocketService @Inject constructor(
    private val authPreferences: AuthPreferences,
    private val okHttpClient: OkHttpClient,
    private val gson: Gson,
) {
    private var webSocket: WebSocket? = null
    private var reconnectJob: Job? = null
    private var heartbeatJob: Job? = null
    private var fallbackPollingJob: Job? = null

    // AUDIT-AND-024: hold SupervisorJob separately so close() can cancel it,
    // releasing all coroutines launched on this scope (reconnectJob, event emits).
    private val job = SupervisorJob()
    private val scope = CoroutineScope(Dispatchers.IO + job)

    private val _events = MutableSharedFlow<WsEvent>(replay = 0, extraBufferCapacity = 64)
    val events = _events.asSharedFlow()

    /** Tracks whether the fallback polling loop is currently active. */
    private val _isFallbackPolling = MutableStateFlow(false)
    val isFallbackPolling = _isFallbackPolling.asStateFlow()

    var isConnected: Boolean = false
        private set

    /**
     * Monotonic timestamp of the last frame (message OR pong) received from the server.
     * Updated from the OkHttp callback thread; read from the heartbeat coroutine.
     * Volatile is sufficient — no compound read-modify-write needed here.
     */
    @Volatile
    private var lastFrameReceivedMs: Long = 0L

    /** Application-context holder for [SyncWorker] fallback scheduling (no Activity needed). */
    private var appContext: android.content.Context? = null

    fun init(context: android.content.Context) {
        appContext = context.applicationContext
    }

    fun connect() {
        val token = authPreferences.accessToken ?: return
        val serverUrl = authPreferences.serverUrl ?: return

        // Safely build the WebSocket URL — parse the HTTP URL, convert scheme,
        // and append /ws. This prevents injection attacks via malformed server URLs
        // (e.g. "https://wss://evil.com/wss" would previously become wss://wss://evil.com).
        val wsUrl = try {
            val httpUrl = serverUrl.toHttpUrlOrNull() ?: run {
                Log.w(TAG, "Invalid server URL for WebSocket")
                return
            }
            val scheme = if (httpUrl.isHttps) "wss" else "ws"
            val defaultPort = if (httpUrl.isHttps) 443 else 80
            val portPart = if (httpUrl.port != defaultPort) ":${httpUrl.port}" else ""
            "$scheme://${httpUrl.host}$portPart/ws"
        } catch (e: Exception) {
            Log.w(TAG, "Failed to build WebSocket URL: ${e.message}")
            return
        }

        val request = Request.Builder()
            .url(wsUrl)
            .addHeader("Authorization", "Bearer $token")
            .build()

        webSocket = okHttpClient.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                Log.d(TAG, "Connected")
                isConnected = true
                lastFrameReceivedMs = System.currentTimeMillis()
                // Stop fallback polling now that we have a real connection.
                stopFallbackPolling()
                // Server expects JSON: { type: "auth", token: "..." }
                val authMsg = gson.toJson(mapOf("type" to "auth", "token" to token))
                webSocket.send(authMsg)
                // Start the application-level heartbeat loop.
                startHeartbeat(webSocket)
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                lastFrameReceivedMs = System.currentTimeMillis()
                try {
                    val json = gson.fromJson(text, Map::class.java)
                    val type = json["type"]?.toString() ?: "unknown"
                    // §21.8 — pong response from our own ping; reset dead timer, no event.
                    if (type == "pong") return
                    scope.launch {
                        _events.emit(WsEvent(type, text))
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to parse message: $text", e)
                }
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                Log.d(TAG, "Closing: $code $reason")
                isConnected = false
                stopHeartbeat()
                webSocket.close(1000, null)
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                Log.w(TAG, "Connection failed: ${t.message}")
                isConnected = false
                stopHeartbeat()
                scheduleReconnect()
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                Log.d(TAG, "Closed: $code")
                isConnected = false
                stopHeartbeat()
                if (code != 1000) scheduleReconnect()
            }
        })
    }

    fun disconnect() {
        reconnectJob?.cancel()
        stopHeartbeat()
        stopFallbackPolling()
        webSocket?.close(1000, "App closing")
        webSocket = null
        isConnected = false
    }

    /**
     * AUDIT-AND-024: cancel the SupervisorJob so all coroutines on [scope]
     * (reconnect loop, event emitters, heartbeat, fallback polling) are released.
     * Call this from the logout path so the singleton does not keep running after
     * the user signs out.
     */
    fun close() {
        disconnect()
        job.cancel()
    }

    // ── Heartbeat ─────────────────────────────────────────────────────────────

    /**
     * §21.8 — Send an application-level ping every [HEARTBEAT_INTERVAL_MS] (20 s).
     * If no frame of any kind arrives within [DEAD_INTERVAL_MS] (45 s) the socket
     * is considered dead and we trigger a reconnect.
     *
     * Note: OkHttp's own TCP-level pingInterval (set in [NetworkModule]) keeps the
     * socket alive in NAT tables. This application ping is complementary — it lets
     * the server know the client is reachable through any HTTP proxy or load balancer
     * that doesn't forward TCP pings.
     */
    private fun startHeartbeat(ws: WebSocket) {
        heartbeatJob?.cancel()
        heartbeatJob = scope.launch {
            while (isActive) {
                delay(HEARTBEAT_INTERVAL_MS)
                if (!isConnected) break

                // §21.8 — Check dead-connection: if the last frame arrived more than
                // DEAD_INTERVAL_MS ago, the server is unreachable (or the network died
                // silently). Close and reconnect instead of hanging indefinitely.
                val sinceLastFrame = System.currentTimeMillis() - lastFrameReceivedMs
                if (lastFrameReceivedMs > 0 && sinceLastFrame > DEAD_INTERVAL_MS) {
                    Log.w(TAG, "No frame received for ${sinceLastFrame}ms (>${DEAD_INTERVAL_MS}ms) — dead connection detected, reconnecting")
                    ws.cancel() // Force-close without a clean handshake
                    isConnected = false
                    scheduleReconnect()
                    break
                }

                // Send application-level ping. The server echoes { "type": "pong" }.
                val pingMsg = gson.toJson(mapOf("type" to "ping", "ts" to System.currentTimeMillis()))
                val sent = ws.send(pingMsg)
                if (!sent) {
                    Log.w(TAG, "Heartbeat ping send failed — socket may be closed")
                    break
                }
            }
        }
    }

    private fun stopHeartbeat() {
        heartbeatJob?.cancel()
        heartbeatJob = null
    }

    // ── Fallback polling ──────────────────────────────────────────────────────

    /**
     * §21.8 — Start a 30-second polling loop via [SyncWorker] when WebSocket
     * is unavailable (e.g. firewall, reverse proxy without Upgrade support).
     * The loop runs until [stopFallbackPolling] is called (which happens when
     * a WebSocket connection succeeds).
     */
    private fun startFallbackPolling() {
        val ctx = appContext ?: return
        if (_isFallbackPolling.value) return
        Log.i(TAG, "WebSocket unavailable after $MAX_RECONNECT_ATTEMPTS attempts — starting 30s fallback polling")
        _isFallbackPolling.value = true
        fallbackPollingJob?.cancel()
        fallbackPollingJob = scope.launch {
            while (isActive && !isConnected) {
                SyncWorker.syncNow(ctx)
                delay(POLLING_INTERVAL_MS)
            }
        }
    }

    private fun stopFallbackPolling() {
        if (_isFallbackPolling.value) {
            Log.i(TAG, "WebSocket connected — stopping fallback polling")
        }
        fallbackPollingJob?.cancel()
        fallbackPollingJob = null
        _isFallbackPolling.value = false
    }

    // ── Reconnect ─────────────────────────────────────────────────────────────

    private fun scheduleReconnect() {
        reconnectJob?.cancel()
        reconnectJob = scope.launch {
            var delay = 1_000L
            for (attempt in 1..MAX_RECONNECT_ATTEMPTS) {
                delay(delay)
                if (!isConnected && authPreferences.isLoggedIn) {
                    Log.d(TAG, "Reconnecting (attempt $attempt / $MAX_RECONNECT_ATTEMPTS)…")
                    connect()
                    delay = (delay * 2).coerceAtMost(30_000L) // Exponential backoff, max 30s
                }
                if (isConnected) return@launch
            }
            // All reconnect attempts exhausted — fall back to polling.
            if (!isConnected) startFallbackPolling()
        }
    }

    companion object {
        private const val TAG = "WebSocket"

        /** §21.8 — Application ping interval: 20 seconds. */
        private const val HEARTBEAT_INTERVAL_MS = 20_000L

        /** §21.8 — Dead-connection threshold: 45 seconds without any frame. */
        private const val DEAD_INTERVAL_MS = 45_000L

        /** §21.8 — Fallback polling interval when WebSocket is unavailable: 30 seconds. */
        private const val POLLING_INTERVAL_MS = 30_000L

        /**
         * §21.8 — After this many failed reconnect attempts, give up on WebSocket
         * and fall back to [POLLING_INTERVAL_MS] polling. 10 attempts with
         * exponential back-off maxing at 30 s ≈ ~5 minutes of retrying before
         * declaring the WebSocket path unavailable.
         */
        private const val MAX_RECONNECT_ATTEMPTS = 10
    }
}
