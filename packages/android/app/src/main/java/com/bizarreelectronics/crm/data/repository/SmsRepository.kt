package com.bizarreelectronics.crm.data.repository

import android.util.Log
import com.bizarreelectronics.crm.data.local.db.dao.SmsDao
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.local.db.entities.SmsMessageEntity
import com.bizarreelectronics.crm.data.local.db.entities.SyncQueueEntity
import com.bizarreelectronics.crm.data.remote.api.SmsApi
import com.bizarreelectronics.crm.data.remote.dto.SmsConversationItem
import com.bizarreelectronics.crm.data.remote.dto.SmsMessageItem
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import com.google.gson.Gson
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SmsRepository @Inject constructor(
    private val smsDao: SmsDao,
    private val smsApi: SmsApi,
    private val syncQueueDao: SyncQueueDao,
    private val serverMonitor: ServerReachabilityMonitor,
    private val gson: Gson,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** Returns cached conversations from Room, refreshes in background. */
    fun getConversations(): Flow<List<SmsMessageEntity>> {
        refreshConversationsInBackground()
        return smsDao.getConversations()
    }

    /** Returns cached messages for a phone, refreshes in background. */
    fun getThread(phone: String): Flow<List<SmsMessageEntity>> {
        refreshThreadInBackground(phone)
        return smsDao.getByConvPhone(phone)
    }

    /**
     * Send an SMS. Online: API call + cache. Offline: local insert + sync queue.
     * Returns the message entity (with temp ID if offline).
     */
    suspend fun sendMessage(to: String, message: String): SmsMessageEntity {
        val now = java.time.Instant.now().toString().take(19).replace("T", " ")

        if (serverMonitor.isEffectivelyOnline.value) {
            try {
                smsApi.sendSms(mapOf("to" to to, "message" to message))
                // Refresh thread to get the server-assigned message
                refreshThreadInBackground(to)
                // Return a placeholder — the Flow will update with the real message
                return SmsMessageEntity(
                    id = -System.currentTimeMillis(),
                    fromNumber = null,
                    toNumber = to,
                    convPhone = to,
                    message = message,
                    status = "sent",
                    direction = "outbound",
                    error = null,
                    provider = null,
                    providerMessageId = null,
                    entityType = null,
                    entityId = null,
                    userId = null,
                    senderName = null,
                    mediaUrls = null,
                    mediaTypes = null,
                    mediaLocalPaths = null,
                    deliveredAt = null,
                    createdAt = now,
                    updatedAt = now,
                )
            } catch (e: Exception) {
                Log.w(TAG, "Online SMS send failed, falling back to offline queue: ${e.message}")
            }
        }

        // Offline: insert locally and queue for sync
        val tempId = -System.currentTimeMillis()
        val entity = SmsMessageEntity(
            id = tempId,
            fromNumber = null,
            toNumber = to,
            convPhone = to,
            message = message,
            status = "queued",
            direction = "outbound",
            error = null,
            provider = null,
            providerMessageId = null,
            entityType = null,
            entityId = null,
            userId = null,
            senderName = null,
            mediaUrls = null,
            mediaTypes = null,
            mediaLocalPaths = null,
            deliveredAt = null,
            createdAt = now,
            updatedAt = now,
        )
        smsDao.insert(entity)

        syncQueueDao.insert(
            SyncQueueEntity(
                entityType = "sms",
                entityId = tempId,
                operation = "send",
                payload = gson.toJson(mapOf("to" to to, "message" to message)),
            )
        )
        return entity
    }

    /** Mark conversation as read. Non-critical — fire and forget. */
    fun markRead(phone: String) {
        scope.launch {
            if (!serverMonitor.isEffectivelyOnline.value) return@launch
            try {
                smsApi.markRead(phone)
            } catch (_: Exception) {}
        }
    }

    fun toggleFlag(phone: String) {
        scope.launch {
            if (!serverMonitor.isEffectivelyOnline.value) return@launch
            try {
                smsApi.toggleFlag(phone)
            } catch (_: Exception) {}
        }
    }

    fun togglePin(phone: String) {
        scope.launch {
            if (!serverMonitor.isEffectivelyOnline.value) return@launch
            try {
                smsApi.togglePin(phone)
            } catch (_: Exception) {}
        }
    }

    /** Full refresh from server — used by SyncManager. */
    suspend fun refreshFromServer() {
        if (!serverMonitor.isEffectivelyOnline.value) return
        try {
            val response = smsApi.getConversations(null)
            val conversations = response.data?.conversations ?: return
            for (conv in conversations) {
                refreshThreadDirect(conv.convPhone)
            }
        } catch (e: Exception) {
            Log.e(TAG, "SMS refreshFromServer failed: ${e.message}")
        }
    }

    private fun refreshConversationsInBackground() {
        scope.launch {
            if (!serverMonitor.isEffectivelyOnline.value) return@launch
            try {
                val response = smsApi.getConversations(null)
                val conversations = response.data?.conversations ?: return@launch
                // Cache the latest message from each conversation
                for (conv in conversations) {
                    refreshThreadDirect(conv.convPhone)
                }
            } catch (e: Exception) {
                Log.d(TAG, "Background conversation refresh failed: ${e.message}")
            }
        }
    }

    private fun refreshThreadInBackground(phone: String) {
        scope.launch {
            if (!serverMonitor.isEffectivelyOnline.value) return@launch
            refreshThreadDirect(phone)
        }
    }

    private suspend fun refreshThreadDirect(phone: String) {
        try {
            val response = smsApi.getThread(phone)
            val messages = response.data?.messages ?: return
            smsDao.insertAll(messages.map { it.toEntity(phone) })
        } catch (e: Exception) {
            Log.d(TAG, "Thread refresh failed for $phone: ${e.message}")
        }
    }

    companion object {
        private const val TAG = "SmsRepository"
    }
}

fun SmsMessageItem.toEntity(convPhone: String) = SmsMessageEntity(
    id = id,
    fromNumber = fromNumber,
    toNumber = toNumber,
    convPhone = this.convPhone ?: convPhone,
    message = message ?: "",
    status = status ?: "unknown",
    direction = direction ?: "unknown",
    error = null,
    provider = null,
    providerMessageId = null,
    entityType = null,
    entityId = null,
    userId = null,
    senderName = null,
    messageType = messageType ?: "sms",
    mediaUrls = null,
    mediaTypes = null,
    mediaLocalPaths = null,
    deliveredAt = null,
    createdAt = createdAt ?: "",
    updatedAt = null,
)
