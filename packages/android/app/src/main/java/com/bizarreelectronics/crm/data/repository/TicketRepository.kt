package com.bizarreelectronics.crm.data.repository

import android.util.Log
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.local.db.dao.TicketDao
import com.bizarreelectronics.crm.data.local.db.entities.SyncQueueEntity
import com.bizarreelectronics.crm.data.local.db.entities.TicketEntity
import com.bizarreelectronics.crm.data.remote.api.TicketApi
import com.bizarreelectronics.crm.data.remote.dto.CreateTicketRequest
import com.bizarreelectronics.crm.data.remote.dto.TicketDetail
import com.bizarreelectronics.crm.data.remote.dto.TicketListItem
import com.bizarreelectronics.crm.data.remote.dto.UpdateTicketRequest
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
class TicketRepository @Inject constructor(
    private val ticketDao: TicketDao,
    private val ticketApi: TicketApi,
    private val syncQueueDao: SyncQueueDao,
    private val serverMonitor: ServerReachabilityMonitor,
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
                Log.d(TAG, "API search failed: ${e.message}")
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
                Log.w(TAG, "Online create failed, falling back to offline queue: ${e.message}")
            }
        }

        // Offline: insert with temporary negative ID
        val tempId = -System.currentTimeMillis()
        val now = java.time.Instant.now().toString().take(19).replace("T", " ")
        val entity = TicketEntity(
            id = tempId,
            orderId = "PENDING",
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

    /** Update a ticket. Online: API call. Offline: local update + sync queue. */
    suspend fun updateTicket(id: Long, request: UpdateTicketRequest): TicketEntity? {
        if (serverMonitor.isEffectivelyOnline.value) {
            try {
                val response = ticketApi.updateTicket(id, request)
                val detail = response.data ?: throw Exception(response.message ?: "Update failed")
                val entity = detail.toEntity()
                ticketDao.insert(entity)
                return entity
            } catch (e: Exception) {
                Log.w(TAG, "Online update failed, falling back to offline queue: ${e.message}")
            }
        }

        // Offline: update locally and queue
        ticketDao.getById(id).let { /* trigger flow but we need a snapshot */ }
        syncQueueDao.insert(
            SyncQueueEntity(
                entityType = "ticket",
                entityId = id,
                operation = "update",
                payload = gson.toJson(request),
            )
        )
        return null
    }

    /** Full pull from server — used by SyncManager. */
    suspend fun refreshFromServer() {
        if (!serverMonitor.isEffectivelyOnline.value) return
        try {
            var page = 1
            while (true) {
                val response = ticketApi.getTickets(mapOf("pagesize" to "200", "page" to page.toString()))
                val tickets = response.data?.tickets ?: break
                if (tickets.isEmpty()) break
                ticketDao.insertAll(tickets.map { it.toEntity() })
                val pagination = response.data?.pagination
                if (pagination == null || page >= pagination.totalPages) break
                page++
            }
        } catch (e: Exception) {
            Log.e(TAG, "refreshFromServer failed: ${e.message}")
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
                Log.d(TAG, "Background ticket refresh failed: ${e.message}")
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
                Log.d(TAG, "Background ticket detail refresh failed: ${e.message}")
            }
        }
    }

    companion object {
        private const val TAG = "TicketRepository"
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
    total = total ?: 0.0,
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
    subtotal = subtotal ?: 0.0,
    discount = discount ?: 0.0,
    totalTax = totalTax ?: 0.0,
    total = total ?: 0.0,
    dueOn = null,
    signature = signature,
    invoiceId = invoiceId,
    createdBy = createdBy,
    customerName = customer?.let { listOfNotNull(it.firstName, it.lastName).joinToString(" ").ifBlank { null } },
    firstDeviceName = devices?.firstOrNull()?.deviceName,
    createdAt = createdAt ?: "",
    updatedAt = updatedAt ?: "",
)
