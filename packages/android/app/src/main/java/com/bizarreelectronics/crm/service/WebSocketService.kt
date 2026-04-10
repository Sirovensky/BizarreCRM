package com.bizarreelectronics.crm.service

import android.util.Log
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import okhttp3.*
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import javax.inject.Inject
import javax.inject.Singleton

data class WsEvent(val type: String, val data: String)

@Singleton
class WebSocketService @Inject constructor(
    private val authPreferences: AuthPreferences,
    private val okHttpClient: OkHttpClient,
) {
    private var webSocket: WebSocket? = null
    private var reconnectJob: Job? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    private val _events = MutableSharedFlow<WsEvent>(replay = 0, extraBufferCapacity = 64)
    val events = _events.asSharedFlow()

    var isConnected: Boolean = false
        private set

    fun connect() {
        val token = authPreferences.accessToken ?: return
        val serverUrl = authPreferences.serverUrl ?: return

        // Safely build the WebSocket URL — parse the HTTP URL, convert scheme,
        // and append /ws. This prevents injection attacks via malformed server URLs
        // (e.g. "https://wss://evil.com/wss" would previously become wss://wss://evil.com).
        val wsUrl = try {
            val httpUrl = serverUrl.toHttpUrlOrNull() ?: run {
                Log.w("WebSocket", "Invalid server URL for WebSocket")
                return
            }
            val scheme = if (httpUrl.isHttps) "wss" else "ws"
            val defaultPort = if (httpUrl.isHttps) 443 else 80
            val portPart = if (httpUrl.port != defaultPort) ":${httpUrl.port}" else ""
            "$scheme://${httpUrl.host}$portPart/ws"
        } catch (e: Exception) {
            Log.w("WebSocket", "Failed to build WebSocket URL: ${e.message}")
            return
        }

        val request = Request.Builder()
            .url(wsUrl)
            .addHeader("Authorization", "Bearer $token")
            .build()

        webSocket = okHttpClient.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                Log.d("WebSocket", "Connected")
                isConnected = true
                // Server expects JSON: { type: "auth", token: "..." }
                val authMsg = com.google.gson.Gson().toJson(mapOf("type" to "auth", "token" to token))
                webSocket.send(authMsg)
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                try {
                    val gson = com.google.gson.Gson()
                    val json = gson.fromJson(text, Map::class.java)
                    val type = json["type"]?.toString() ?: "unknown"
                    scope.launch {
                        _events.emit(WsEvent(type, text))
                    }
                } catch (e: Exception) {
                    Log.w("WebSocket", "Failed to parse message: $text", e)
                }
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                Log.d("WebSocket", "Closing: $code $reason")
                isConnected = false
                webSocket.close(1000, null)
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                Log.w("WebSocket", "Connection failed", t)
                isConnected = false
                scheduleReconnect()
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                Log.d("WebSocket", "Closed: $code")
                isConnected = false
                if (code != 1000) scheduleReconnect()
            }
        })
    }

    fun disconnect() {
        reconnectJob?.cancel()
        webSocket?.close(1000, "App closing")
        webSocket = null
        isConnected = false
    }

    private fun scheduleReconnect() {
        reconnectJob?.cancel()
        reconnectJob = scope.launch {
            var delay = 1000L
            repeat(10) {
                delay(delay)
                if (!isConnected && authPreferences.isLoggedIn) {
                    Log.d("WebSocket", "Reconnecting (attempt ${it + 1})...")
                    connect()
                    delay = (delay * 2).coerceAtMost(30_000L) // Exponential backoff, max 30s
                }
            }
        }
    }
}
