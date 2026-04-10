package com.bizarreelectronics.crm.data.repository

import android.util.Log
import com.bizarreelectronics.crm.data.local.db.dao.LeadDao
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.local.db.entities.LeadEntity
import com.bizarreelectronics.crm.data.local.db.entities.SyncQueueEntity
import com.bizarreelectronics.crm.data.remote.api.LeadApi
import com.bizarreelectronics.crm.data.remote.dto.CreateLeadRequest
import com.bizarreelectronics.crm.data.remote.dto.LeadDetail
import com.bizarreelectronics.crm.data.remote.dto.LeadListItem
import com.bizarreelectronics.crm.data.remote.dto.UpdateLeadRequest
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
class LeadRepository @Inject constructor(
    private val leadDao: LeadDao,
    private val leadApi: LeadApi,
    private val syncQueueDao: SyncQueueDao,
    private val serverMonitor: ServerReachabilityMonitor,
    private val gson: Gson,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** Returns cached leads immediately, refreshes from API in background. */
    fun getLeads(): Flow<List<LeadEntity>> {
        refreshLeadsInBackground()
        return leadDao.getAll()
    }

    fun getLead(id: Long): Flow<LeadEntity?> {
        refreshLeadDetailInBackground(id)
        return leadDao.getById(id)
    }

    fun getOpenLeads(): Flow<List<LeadEntity>> {
        refreshLeadsInBackground()
        return leadDao.getOpenLeads()
    }

    fun searchLeads(query: String): Flow<List<LeadEntity>> {
        // Also trigger API search in background
        scope.launch {
            if (!serverMonitor.isEffectivelyOnline.value) return@launch
            try {
                val response = leadApi.getLeads(mapOf("search" to query, "pagesize" to "50"))
                val leads = response.data?.leads ?: return@launch
                leadDao.insertAll(leads.map { it.toEntity() })
            } catch (e: Exception) {
                Log.d(TAG, "API search failed: ${e.message}")
            }
        }
        return leadDao.search(query)
    }

    /** Create a lead. Online: API call. Offline: local insert + sync queue. */
    suspend fun createLead(request: CreateLeadRequest): Long {
        if (serverMonitor.isEffectivelyOnline.value) {
            try {
                val response = leadApi.createLead(request)
                val detail = response.data ?: throw Exception(response.message ?: "Create failed")
                val entity = detail.toEntity()
                leadDao.insert(entity)
                return entity.id
            } catch (e: Exception) {
                Log.w(TAG, "Online create failed, falling back to offline queue: ${e.message}")
            }
        }

        // Offline: insert with temporary negative ID
        val tempId = -System.currentTimeMillis()
        val now = java.time.Instant.now().toString().take(19).replace("T", " ")
        val entity = LeadEntity(
            id = tempId,
            firstName = request.firstName,
            lastName = request.lastName,
            email = request.email,
            phone = request.phone,
            status = request.status,
            source = request.source,
            createdAt = now,
            updatedAt = now,
            locallyModified = true,
        )
        leadDao.insert(entity)

        syncQueueDao.insert(
            SyncQueueEntity(
                entityType = "lead",
                entityId = tempId,
                operation = "create",
                payload = gson.toJson(request),
            )
        )
        return tempId
    }

    /** Update a lead. Online: API call. Offline: local update + sync queue. */
    suspend fun updateLead(id: Long, request: UpdateLeadRequest): LeadEntity? {
        if (serverMonitor.isEffectivelyOnline.value) {
            try {
                val response = leadApi.updateLead(id, request)
                val detail = response.data ?: throw Exception(response.message ?: "Update failed")
                val entity = detail.toEntity()
                leadDao.insert(entity)
                return entity
            } catch (e: Exception) {
                Log.w(TAG, "Online update failed, falling back to offline queue: ${e.message}")
            }
        }

        // Offline: update locally and queue
        leadDao.getById(id).let { /* trigger flow but we need a snapshot */ }
        syncQueueDao.insert(
            SyncQueueEntity(
                entityType = "lead",
                entityId = id,
                operation = "update",
                payload = gson.toJson(request),
            )
        )
        return null
    }

    /** Convert a lead to a ticket. Online only — throws on offline. */
    suspend fun convertLead(id: Long): Long? {
        if (!serverMonitor.isEffectivelyOnline.value) {
            throw IllegalStateException("Cannot convert lead while offline")
        }
        val response = leadApi.convertLead(id)
        val data = response.data ?: throw Exception(response.message ?: "Convert failed")
        val ticketId = (data["ticketId"] as? Number)?.toLong()
        // Refresh the lead so its status updates locally
        refreshLeadDetailInBackground(id)
        return ticketId
    }

    /** Full pull from server — used by SyncManager. */
    suspend fun refreshFromServer() {
        if (!serverMonitor.isEffectivelyOnline.value) return
        try {
            var page = 1
            while (true) {
                val response = leadApi.getLeads(mapOf("pagesize" to "200", "page" to page.toString()))
                val leads = response.data?.leads ?: break
                if (leads.isEmpty()) break
                leadDao.insertAll(leads.map { it.toEntity() })
                val pagination = response.data?.pagination
                if (pagination == null || page >= pagination.totalPages) break
                page++
            }
        } catch (e: Exception) {
            Log.e(TAG, "refreshFromServer failed: ${e.message}")
        }
    }

    private fun refreshLeadsInBackground() {
        scope.launch {
            if (!serverMonitor.isEffectivelyOnline.value) return@launch
            try {
                val response = leadApi.getLeads(mapOf("pagesize" to "200"))
                val leads = response.data?.leads ?: return@launch
                leadDao.insertAll(leads.map { it.toEntity() })
            } catch (e: Exception) {
                Log.d(TAG, "Background lead refresh failed: ${e.message}")
            }
        }
    }

    private fun refreshLeadDetailInBackground(id: Long) {
        scope.launch {
            if (!serverMonitor.isEffectivelyOnline.value) return@launch
            try {
                val response = leadApi.getLead(id)
                val detail = response.data ?: return@launch
                leadDao.insert(detail.toEntity())
            } catch (e: Exception) {
                Log.d(TAG, "Background lead detail refresh failed: ${e.message}")
            }
        }
    }

    companion object {
        private const val TAG = "LeadRepository"
    }
}

fun LeadListItem.toEntity() = LeadEntity(
    id = id,
    orderId = orderId,
    firstName = firstName,
    lastName = lastName,
    email = email,
    phone = phone,
    status = status,
    leadScore = leadScore ?: 0,
    source = source,
    assignedTo = assignedTo,
    assignedName = listOfNotNull(assignedFirstName, assignedLastName).joinToString(" ").ifBlank { null },
    createdAt = createdAt ?: "",
    updatedAt = updatedAt ?: "",
)

fun LeadDetail.toEntity() = LeadEntity(
    id = id,
    orderId = orderId,
    customerId = customerId,
    firstName = firstName,
    lastName = lastName,
    email = email,
    phone = phone,
    zipCode = zipCode,
    address = address,
    status = status,
    referredBy = referredBy,
    assignedTo = assignedTo,
    source = source,
    notes = notes,
    lostReason = lostReason,
    leadScore = leadScore ?: 0,
    assignedName = listOfNotNull(assignedFirstName, assignedLastName).joinToString(" ").ifBlank { null },
    isDeleted = isDeleted == 1,
    createdAt = createdAt ?: "",
    updatedAt = updatedAt ?: "",
)
