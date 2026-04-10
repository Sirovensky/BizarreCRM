package com.bizarreelectronics.crm.service

import android.util.Log
import com.bizarreelectronics.crm.data.local.db.dao.SmsDao
import com.bizarreelectronics.crm.data.local.db.entities.SmsMessageEntity
import com.bizarreelectronics.crm.data.repository.TicketRepository
import com.google.gson.Gson
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Listens to WebSocket events and updates Room so the UI is always in sync.
 * Handles real-time SMS received/sent, ticket updates, etc.
 */
@Singleton
class WebSocketEventHandler @Inject constructor(
    private val webSocketService: WebSocketService,
    private val smsDao: SmsDao,
    private val gson: Gson,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** Start listening to WebSocket events. Call once from Application.onCreate(). */
    fun startListening() {
        scope.launch {
            webSocketService.events.collect { event ->
                try {
                    handleEvent(event)
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to handle WS event '${event.type}': ${e.message}")
                }
            }
        }
    }

    @Suppress("UNCHECKED_CAST")
    private suspend fun handleEvent(event: WsEvent) {
        when (event.type) {
            "sms:received", "sms:sent" -> {
                // Parse the SMS message from the event data and cache it in Room
                val json = gson.fromJson(event.data, Map::class.java) as? Map<String, Any> ?: return
                val data = json["data"] as? Map<String, Any> ?: return

                val id = (data["id"] as? Number)?.toLong() ?: return
                val entity = SmsMessageEntity(
                    id = id,
                    fromNumber = data["from_number"] as? String,
                    toNumber = data["to_number"] as? String,
                    convPhone = data["conv_phone"] as? String ?: return,
                    message = data["message"] as? String ?: "",
                    status = data["status"] as? String ?: "delivered",
                    direction = data["direction"] as? String ?: if (event.type == "sms:received") "inbound" else "outbound",
                    error = null,
                    provider = null,
                    providerMessageId = data["provider_message_id"] as? String,
                    entityType = null,
                    entityId = null,
                    userId = (data["user_id"] as? Number)?.toLong(),
                    senderName = data["sender_name"] as? String,
                    mediaUrls = null,
                    mediaTypes = null,
                    mediaLocalPaths = null,
                    deliveredAt = data["delivered_at"] as? String,
                    createdAt = data["created_at"] as? String ?: "",
                    updatedAt = data["updated_at"] as? String,
                )
                smsDao.insert(entity)
                Log.d(TAG, "Cached ${event.type} message #$id for ${entity.convPhone}")
            }

            "ticket:created", "ticket:updated", "ticket:status_changed" -> {
                // These are handled by the periodic sync + pull-to-refresh.
                // For now just log; a future enhancement could do a targeted Room update.
                Log.d(TAG, "WS event: ${event.type}")
            }

            "notification:new" -> {
                Log.d(TAG, "New notification via WS")
            }

            else -> {
                Log.v(TAG, "Unhandled WS event: ${event.type}")
            }
        }
    }

    companion object {
        private const val TAG = "WsEventHandler"
    }
}
