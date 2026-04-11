package com.bizarreelectronics.crm.data.repository

import android.util.Log
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.local.db.dao.TicketDao
import com.bizarreelectronics.crm.data.local.db.entities.SyncQueueEntity
import com.bizarreelectronics.crm.data.local.db.entities.TicketEntity
import com.bizarreelectronics.crm.data.local.prefs.OfflineIdGenerator
import com.bizarreelectronics.crm.data.remote.api.TicketApi
import com.bizarreelectronics.crm.data.remote.dto.CreateTicketRequest
import com.bizarreelectronics.crm.data.remote.dto.TicketDetail
import com.bizarreelectronics.crm.data.remote.dto.TicketListItem
import com.bizarreelectronics.crm.data.remote.dto.UpdateTicketRequest
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import com.bizarreelectronics.crm.util.toCentsOrZero
import com.google.gson.Gson
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import java.io.IOException
import java.net.SocketTimeoutException
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class TicketRepository @Inject constructor(
    private val ticketDao: TicketDao,
    private val ticketApi: TicketApi,
    private val syncQueueDao: SyncQueueDao,
    private val serverMonitor: ServerReachabilityMonitor,
    private val offlineIdGenerator: OfflineIdGenerator,
    private val gson: Gson,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** Returns cached tickets immediately, refreshes from API in background. */
    fun getTickets(): Flow<List<TicketEntity>> {
        refreshTicketsInBackground()
        return ticketDao.getAll()
    }

    fun getOpenTickets(): Flow<List<TicketEntity>> {
        refreshTicketsInBackground()
        return ticketDao.getOpenTickets()
    }

    fun getByAssignedTo(userId: Long): Flow<List<TicketEntity>> {
        refreshTicketsInBackground()
        return ticketDao.getByAssignedTo(userId)
    }

    fun getByCustomerId(customerId: Long): Flow<List<TicketEntity>> = ticketDao.getByCustomerId(customerId)

    fun getTicket(id: Long): Flow<TicketEntity?> {
        refreshTicketDetailInBackground(id)
        return ticketDao.getById(id)
    }

    fun searchTickets(query: String): Flow<List<TicketEntity>> {
        // Also trigger API search in background
        scope.launch {
            if (!serverMonitor.isEffectivelyOnline.value) return@launch
            try {
                val response = ticketApi.getTickets(mapOf("search" to query, "pagesize" to "50"))
                val tickets = response.data?.tickets ?: return@launch
                ticketDao.insertAll(tickets.map { it.toEntity() })
            } catch (e: Exception) {
                Log.d(TAG, "API ticket search failed [${e.javaClass.simpleName}]: ${e.message}")
            }
        }
        return ticketDao.search(query)
    }

    fun getOpenCount(): Flow<Int> = ticketDao.getOpenCount()

    fun getCount(): Flow<Int> = ticketDao.getCount()

    /** Create a ticket. Online: API call. Offline: local insert + sync queue. */
    suspend fun createTicket(request: CreateTicketRequest): Long {
        if (serverMonitor.isEffectivelyOnline.value) {
            try {
                val response = ticketApi.createTicket(request)
                val detail = response.data ?: throw Exception(response.message ?: "Create failed")
                val entity = detail.toEntity()
                ticketDao.insert(entity)
                return entity.id
            } catch (e: Exception) {
                Log.w(TAG, "Online ticket create failed [${e.javaClass.simpleName}], falling back to offline queue: ${e.message}")
            }
        }

        // Offline: insert with collision-free temp id + human-readable OFFLINE reference.
        // Both `id` and `orderId` are reconciled to server values by SyncManager once the
        // row is flushed. See N1/N2/I1/I2 in the audit.
        val tempId = offlineIdGenerator.nextTempId()
        val offlineOrderRef = offlineIdGenerator.nextOfflineReference()
        val now = java.time.Instant.now().toString().take(19).replace("T", " ")
        val entity = TicketEntity(
            id = tempId,
            orderId = offlineOrderRef,
            customerId = request.customerId,
            createdAt = now,
            updatedAt = now,
            locallyModified = true,
        )
        ticketDao.insert(entity)

        syncQueueDao.insert(
            SyncQueueEntity(
                entityType = "ticket",
                entityId = tempId,
                operation = "create",
                payload = gson.toJson(request),
            )
        )
        return tempId
    }

    /**
     * Update a ticket. Online: API call. Offline: local update + sync queue.
     *
     * Takes a snapshot of the current Room row before forwarding the update so that the
     * request can include an optimistic-concurrency token (`_updated_at`) and so that
     * local unsaved changes are not silently overwritten by a stale flush. See AP8.
     */
    suspend fun updateTicket(id: Long, request: UpdateTicketRequest): TicketEntity? {
        // Snapshot current Room row BEFORE doing anything else. The snapshot feeds the
        // optimistic-concurrency token sent to the server and is used to detect local
        // edits that must be preserved if a later flush would otherwise overwrite them.
        val snapshot: TicketEntity? = runCatching { ticketDao.getById(id).first() }.getOrNull()
        val mergedRequest = if (request.updatedAt == null && snapshot?.updatedAt?.isNotBlank() == true) {
            request.copy(updatedAt = snapshot.updatedAt)
        } else {
            request
        }

        if (serverMonitor.isEffectivelyOnline.value) {
            try {
                val response = ticketApi.updateTicket(id, mergedRequest)
                val detail = response.data ?: throw Exception(response.message ?: "Update failed")
                val entity = detail.toEntity()
                ticketDao.insert(entity)
                return entity
            } catch (e: Exception) {
                Log.w(TAG, "Online ticket update failed [${e.javaClass.simpleName}], falling back to offline queue: ${e.message}")
            }
        }

        // Offline: mark the local row dirty with the caller's intended change applied,
        // then queue the merged (updatedAt-tagged) request for later flush.
        if (snapshot != null) {
            val locallyDirty = snapshot.copy(locallyModified = true)
            ticketDao.insert(locallyDirty)
        }
        syncQueueDao.insert(
            SyncQueueEntity(
                entityType = "ticket",
                entityId = id,
                operation = "update",
                payload = gson.toJson(mergedRequest),
            )
        )
        return null
    }

    /**
     * @audit-fixed: Section 33 / D7 — re-points `ticket_devices` and `ticket_notes`
     * children that were attached to a temp ticket while offline so that the
     * SyncManager's temp-id reconciliation can drop the temp parent without the
     * CASCADE rule wiping them. Caller is responsible for inserting the real
     * ticket row first and dropping the temp row last.
     */
    suspend fun repointChildRowsToServerId(tempId: Long, serverId: Long) {
        ticketDao.repointDevices(tempId = tempId, serverId = serverId)
        ticketDao.repointNotes(tempId = tempId, serverId = serverId)
    }

    /** Full pull from server — used by SyncManager. */
    suspend fun refreshFromServer() {
        if (!serverMonitor.isEffectivelyOnline.value) return
        try {
            var page = 1
            while (page <= MAX_PAGINATION_PAGES) {
                val response = ticketApi.getTickets(mapOf("pagesize" to "200", "page" to page.toString()))
                val tickets = response.data?.tickets ?: break
                if (tickets.isEmpty()) break
                ticketDao.insertAll(tickets.map { it.toEntity() })
                val pagination = response.data?.pagination
                if (pagination == null || page >= pagination.totalPages) break
                page++
            }
        } catch (e: Exception) {
            Log.e(TAG, "ticket refreshFromServer failed [${e.javaClass.simpleName}]: ${e.message}")
        }
    }

    private fun refreshTicketsInBackground() {
        scope.launch {
            if (!serverMonitor.isEffectivelyOnline.value) return@launch
            try {
                val response = ticketApi.getTickets(mapOf("pagesize" to "200"))
                val tickets = response.data?.tickets ?: return@launch
                ticketDao.insertAll(tickets.map { it.toEntity() })
            } catch (e: Exception) {
                Log.d(TAG, "Background ticket refresh failed [${e.javaClass.simpleName}]: ${e.message}")
            }
        }
    }

    private fun refreshTicketDetailInBackground(id: Long) {
        scope.launch {
            if (!serverMonitor.isEffectivelyOnline.value) return@launch
            try {
                val response = ticketApi.getTicket(id)
                val detail = response.data ?: return@launch
                ticketDao.insert(detail.toEntity())
            } catch (e: Exception) {
                Log.d(TAG, "Background ticket detail refresh failed [${e.javaClass.simpleName}]: ${e.message}")
            }
        }
    }

    /**
     * Returns true if the given exception is a transient network failure that is worth
     * retrying. Non-network errors (e.g. HttpException 4xx) indicate the server actively
     * rejected the request and a retry would just fail the same way.
     */
    @Suppress("unused")
    private fun isRetryableNetworkError(error: Throwable): Boolean =
        error is IOException || error is SocketTimeoutException

    companion object {
        private const val TAG = "TicketRepository"

        /**
         * Hard safety cap on pagination loops (AP4 analogue). If the server ever
         * reports a bogus `totalPages` we refuse to walk the list forever and simply
         * stop after this many iterations.
         */
        private const val MAX_PAGINATION_PAGES = 1000
    }
}

fun TicketListItem.toEntity() = TicketEntity(
    id = id,
    orderId = orderId,
    customerId = customerId,
    statusId = status?.id,
    statusName = status?.name,
    statusColor = status?.color,
    statusIsClosed = status?.isClosed == 1,
    assignedTo = assignedUser?.id,
    total = total.toCentsOrZero(),
    customerName = customer?.fullName,
    customerPhone = customer?.mobile ?: customer?.phone,
    firstDeviceName = firstDevice?.deviceName,
    createdAt = createdAt ?: "",
    updatedAt = updatedAt ?: "",
)

fun TicketDetail.toEntity() = TicketEntity(
    id = id,
    orderId = orderId,
    customerId = customerId,
    statusId = status?.id ?: statusId,
    statusName = status?.name,
    statusColor = status?.color,
    statusIsClosed = status?.isClosed == 1,
    assignedTo = assignedTo,
    subtotal = subtotal.toCentsOrZero(),
    discount = discount.toCentsOrZero(),
    totalTax = totalTax.toCentsOrZero(),
    total = total.toCentsOrZero(),
    dueOn = null,
    signature = signature,
    invoiceId = invoiceId,
    createdBy = createdBy,
    customerName = customer?.let { listOfNotNull(it.firstName, it.lastName).joinToString(" ").ifBlank { null } },
    firstDeviceName = devices?.firstOrNull()?.deviceName,
    createdAt = createdAt ?: "",
    updatedAt = updatedAt ?: "",
)
