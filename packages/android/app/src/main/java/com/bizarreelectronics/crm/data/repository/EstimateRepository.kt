package com.bizarreelectronics.crm.data.repository

import android.util.Log
import com.bizarreelectronics.crm.data.local.db.dao.EstimateDao
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.local.db.entities.EstimateEntity
import com.bizarreelectronics.crm.data.local.db.entities.SyncQueueEntity
import com.bizarreelectronics.crm.data.remote.api.EstimateApi
import com.bizarreelectronics.crm.data.remote.dto.CreateEstimateRequest
import com.bizarreelectronics.crm.data.remote.dto.EstimateDetail
import com.bizarreelectronics.crm.data.remote.dto.EstimateListItem
import com.bizarreelectronics.crm.data.remote.dto.UpdateEstimateRequest
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
class EstimateRepository @Inject constructor(
    private val estimateDao: EstimateDao,
    private val estimateApi: EstimateApi,
    private val syncQueueDao: SyncQueueDao,
    private val serverMonitor: ServerReachabilityMonitor,
    private val gson: Gson,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** Returns cached estimates immediately, refreshes from API in background. */
    fun getEstimates(): Flow<List<EstimateEntity>> {
        refreshEstimatesInBackground()
        return estimateDao.getAll()
    }

    fun getEstimate(id: Long): Flow<EstimateEntity?> {
        refreshEstimateDetailInBackground(id)
        return estimateDao.getById(id)
    }

    fun searchEstimates(query: String): Flow<List<EstimateEntity>> {
        // Also trigger API search in background
        scope.launch {
            if (!serverMonitor.isEffectivelyOnline.value) return@launch
            try {
                val response = estimateApi.getEstimates(mapOf("search" to query, "pagesize" to "50"))
                val estimates = response.data?.estimates ?: return@launch
                estimateDao.insertAll(estimates.map { it.toEntity() })
            } catch (e: Exception) {
                Log.d(TAG, "API search failed: ${e.message}")
            }
        }
        return estimateDao.search(query)
    }

    /** Create an estimate. Online: API call. Offline: local insert + sync queue. */
    suspend fun createEstimate(request: CreateEstimateRequest): Long {
        if (serverMonitor.isEffectivelyOnline.value) {
            try {
                val response = estimateApi.createEstimate(request)
                val detail = response.data ?: throw Exception(response.message ?: "Create failed")
                val entity = detail.toEntity()
                estimateDao.insert(entity)
                return entity.id
            } catch (e: Exception) {
                Log.w(TAG, "Online create failed, falling back to offline queue: ${e.message}")
            }
        }

        // Offline: insert with temporary negative ID
        val tempId = -System.currentTimeMillis()
        val now = java.time.Instant.now().toString().take(19).replace("T", " ")
        val entity = EstimateEntity(
            id = tempId,
            orderId = "PENDING",
            customerId = request.customerId,
            status = "draft",
            discount = request.discount ?: 0.0,
            notes = request.notes,
            validUntil = request.validUntil,
            createdAt = now,
            updatedAt = now,
            locallyModified = true,
        )
        estimateDao.insert(entity)

        syncQueueDao.insert(
            SyncQueueEntity(
                entityType = "estimate",
                entityId = tempId,
                operation = "create",
                payload = gson.toJson(request),
            )
        )
        return tempId
    }

    /** Update an estimate. Online: API call. Offline: local update + sync queue. */
    suspend fun updateEstimate(id: Long, request: UpdateEstimateRequest): EstimateEntity? {
        if (serverMonitor.isEffectivelyOnline.value) {
            try {
                val response = estimateApi.updateEstimate(id, request)
                val detail = response.data ?: throw Exception(response.message ?: "Update failed")
                val entity = detail.toEntity()
                estimateDao.insert(entity)
                return entity
            } catch (e: Exception) {
                Log.w(TAG, "Online update failed, falling back to offline queue: ${e.message}")
            }
        }

        // Offline: update locally and queue
        estimateDao.getById(id).let { /* trigger flow but we need a snapshot */ }
        syncQueueDao.insert(
            SyncQueueEntity(
                entityType = "estimate",
                entityId = id,
                operation = "update",
                payload = gson.toJson(request),
            )
        )
        return null
    }

    /** Convert an estimate to a ticket. Online only — throws on offline. */
    suspend fun convertEstimate(id: Long): Long? {
        if (!serverMonitor.isEffectivelyOnline.value) {
            throw IllegalStateException("Cannot convert estimate while offline")
        }
        val response = estimateApi.convertToTicket(id)
        val data = response.data ?: throw Exception(response.message ?: "Convert failed")
        val ticketId = (data["ticketId"] as? Number)?.toLong()
        // Refresh the estimate so its status updates locally
        refreshEstimateDetailInBackground(id)
        return ticketId
    }

    /** Send an estimate to the customer. Online only — throws on offline. */
    suspend fun sendEstimate(id: Long, method: String) {
        if (!serverMonitor.isEffectivelyOnline.value) {
            throw IllegalStateException("Cannot send estimate while offline")
        }
        val response = estimateApi.sendEstimate(id, mapOf("method" to method))
        if (response.data == null && response.message != null) {
            throw Exception(response.message)
        }
        // Refresh the estimate so sent_at updates locally
        refreshEstimateDetailInBackground(id)
    }

    /** Full pull from server — used by SyncManager. */
    suspend fun refreshFromServer() {
        if (!serverMonitor.isEffectivelyOnline.value) return
        try {
            var page = 1
            while (true) {
                val response = estimateApi.getEstimates(mapOf("pagesize" to "200", "page" to page.toString()))
                val estimates = response.data?.estimates ?: break
                if (estimates.isEmpty()) break
                estimateDao.insertAll(estimates.map { it.toEntity() })
                val pagination = response.data?.pagination
                if (pagination == null || page >= pagination.totalPages) break
                page++
            }
        } catch (e: Exception) {
            Log.e(TAG, "refreshFromServer failed: ${e.message}")
        }
    }

    private fun refreshEstimatesInBackground() {
        scope.launch {
            if (!serverMonitor.isEffectivelyOnline.value) return@launch
            try {
                val response = estimateApi.getEstimates(mapOf("pagesize" to "200"))
                val estimates = response.data?.estimates ?: return@launch
                estimateDao.insertAll(estimates.map { it.toEntity() })
            } catch (e: Exception) {
                Log.d(TAG, "Background estimate refresh failed: ${e.message}")
            }
        }
    }

    private fun refreshEstimateDetailInBackground(id: Long) {
        scope.launch {
            if (!serverMonitor.isEffectivelyOnline.value) return@launch
            try {
                val response = estimateApi.getEstimate(id)
                val detail = response.data ?: return@launch
                estimateDao.insert(detail.toEntity())
            } catch (e: Exception) {
                Log.d(TAG, "Background estimate detail refresh failed: ${e.message}")
            }
        }
    }

    companion object {
        private const val TAG = "EstimateRepository"
    }
}

fun EstimateListItem.toEntity() = EstimateEntity(
    id = id,
    orderId = orderId ?: "",
    customerId = customerId,
    customerName = listOfNotNull(customerFirstName, customerLastName).joinToString(" ").ifBlank { null },
    status = status ?: "draft",
    total = total ?: 0.0,
    validUntil = validUntil,
    createdAt = createdAt ?: "",
    updatedAt = createdAt ?: "",
)

fun EstimateDetail.toEntity() = EstimateEntity(
    id = id,
    orderId = orderId ?: "",
    customerId = customerId,
    customerName = listOfNotNull(customerFirstName, customerLastName).joinToString(" ").ifBlank { null },
    status = status ?: "draft",
    discount = discount ?: 0.0,
    notes = notes,
    validUntil = validUntil,
    subtotal = subtotal ?: 0.0,
    totalTax = totalTax ?: 0.0,
    total = total ?: 0.0,
    convertedTicketId = convertedTicketId,
    isDeleted = isDeleted == true,
    createdAt = createdAt ?: "",
    updatedAt = updatedAt ?: "",
)
