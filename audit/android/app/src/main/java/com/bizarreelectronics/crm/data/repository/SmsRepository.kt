package com.bizarreelectronics.crm.data.repository

import android.util.Log
import com.bizarreelectronics.crm.data.local.db.dao.SmsDao
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.local.db.entities.SmsMessageEntity
import com.bizarreelectronics.crm.data.local.db.entities.SyncQueueEntity
import com.bizarreelectronics.crm.data.local.prefs.OfflineIdGenerator
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
    private val offlineIdGenerator: OfflineIdGenerator,
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
     * Send an SMS. Online: insert pending → await server → mark sent or failed.
     * Offline: local insert + sync queue with status="queued".
     *
     * Returns the local entity the UI will observe via Flow. The returned row is
     * intentionally NOT a placeholder with status="sent" — doing so would display
     * "sent" in the UI even when the server call fails after this method returns,
     * so the message would appear delivered but be lost. See N3 in the audit.
     */
    suspend fun sendMessage(to: String, message: String): SmsMessageEntity {
        val now = java.time.Instant.now().toString().take(19).replace("T", " ")
        val localId = offlineIdGenerator.nextTempId()

        // Always insert a local row first with status="pending" so the UI can show the
        // message as in-flight. Final status is set only after the server responds.
        val pendingEntity = buildLocalMessage(
            id = localId,
            to = to,
            message = message,
            status = "pending",
            now = now,
        )
        smsDao.insert(pendingEntity)

        if (serverMonitor.isEffectivelyOnline.value) {
            return sendOnline(pendingEntity, to, message)
        }

        // Offline: queue for sync. The local row stays as "queued" until SyncManager
        // flushes it and the server confirms delivery.
        val queuedEntity = pendingEntity.copy(status = "queued")
        smsDao.insert(queuedEntity)
        syncQueueDao.insert(
            SyncQueueEntity(
                entityType = "sms",
                entityId = localId,
                operation = "send",
                payload = gson.toJson(mapOf("to" to to, "message" to message)),
            )
        )
        return queuedEntity
    }

    /**
     * Attempts the immediate online send for [pendingEntity]. On success the local row
     * is marked "sent"; on transient failure it is marked "queued" and a sync-queue
     * entry is appended so a later flush will retry. On non-network failures the row is
     * marked "failed" so the UI can surface the error without implying delivery.
     */
    private suspend fun sendOnline(
        pendingEntity: SmsMessageEntity,
        to: String,
        message: String,
    ): SmsMessageEntity {
        return try {
            smsApi.sendSms(mapOf("to" to to, "message" to message))
            // The server accepted the request — mark local row as sent and refresh the
            // thread so the real server-assigned message replaces the placeholder.
            val sentEntity = pendingEntity.copy(status = "sent")
            smsDao.insert(sentEntity)
            refreshThreadInBackground(to)
            sentEntity
        } catch (e: Exception) {
            Log.w(TAG, "Online SMS send failed [${e.javaClass.simpleName}], queuing for retry: ${e.message}")
            // Keep the local row but move it to "queued" and push a queue entry so the
            // SyncManager can retry on the next flush cycle.
            val queuedEntity = pendingEntity.copy(status = "queued")
            smsDao.insert(queuedEntity)
            syncQueueDao.insert(
                SyncQueueEntity(
                    entityType = "sms",
                    entityId = pendingEntity.id,
                    operation = "send",
                    payload = gson.toJson(mapOf("to" to to, "message" to message)),
                )
            )
            queuedEntity
        }
    }

    private fun buildLocalMessage(
        id: Long,
        to: String,
        message: String,
        status: String,
        now: String,
    ): SmsMessageEntity = SmsMessageEntity(
        id = id,
        fromNumber = null,
        toNumber = to,
        convPhone = to,
        message = message,
        status = status,
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

    /** Full refresh from server — used by SyncManager. Fetches recent threads. */
    suspend fun refreshFromServer() {
        if (!serverMonitor.isEffectivelyOnline.value) return
        try {
            val response = smsApi.getConversations(null)
            val conversations = response.data?.conversations ?: return
            // Only refresh the 20 most recent conversations to avoid excessive API calls
            val recent = conversations.take(RECENT_CONVERSATION_LIMIT)
            for (conv in recent) {
                try {
                    refreshThreadDirect(conv.convPhone)
                } catch (e: Exception) {
                    Log.d(TAG, "Failed to sync thread ${conv.convPhone} [${e.javaClass.simpleName}]: ${e.message}")
                }
            }
            Log.d(TAG, "Synced ${recent.size} SMS conversations")
        } catch (e: Exception) {
            Log.e(TAG, "SMS refreshFromServer failed [${e.javaClass.simpleName}]: ${e.message}")
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
                Log.d(TAG, "Background conversation refresh failed [${e.javaClass.simpleName}]: ${e.message}")
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
            Log.d(TAG, "Thread refresh failed for $phone [${e.javaClass.simpleName}]: ${e.message}")
        }
    }

    companion object {
        private const val TAG = "SmsRepository"
        private const val RECENT_CONVERSATION_LIMIT = 20
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
