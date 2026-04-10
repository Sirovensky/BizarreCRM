package com.bizarreelectronics.crm.data.repository

import android.util.Log
import com.bizarreelectronics.crm.data.local.db.dao.CustomerDao
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.local.db.entities.CustomerEntity
import com.bizarreelectronics.crm.data.local.db.entities.SyncQueueEntity
import com.bizarreelectronics.crm.data.remote.api.CustomerApi
import com.bizarreelectronics.crm.data.remote.dto.CreateCustomerRequest
import com.bizarreelectronics.crm.data.remote.dto.CustomerDetail
import com.bizarreelectronics.crm.data.remote.dto.CustomerListItem
import com.bizarreelectronics.crm.data.remote.dto.UpdateCustomerRequest
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
class CustomerRepository @Inject constructor(
    private val customerDao: CustomerDao,
    private val customerApi: CustomerApi,
    private val syncQueueDao: SyncQueueDao,
    private val serverMonitor: ServerReachabilityMonitor,
    private val gson: Gson,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** Returns cached customers immediately, refreshes from API in background. */
    fun getCustomers(): Flow<List<CustomerEntity>> {
        refreshCustomersInBackground()
        return customerDao.getAll()
    }

    fun getCustomer(id: Long): Flow<CustomerEntity?> {
        refreshCustomerDetailInBackground(id)
        return customerDao.getById(id)
    }

    fun searchCustomers(query: String): Flow<List<CustomerEntity>> {
        scope.launch {
            if (!serverMonitor.isEffectivelyOnline.value) return@launch
            try {
                val response = customerApi.searchCustomers(query)
                val customers = response.data ?: return@launch
                customerDao.insertAll(customers.map { it.toEntity() })
            } catch (e: Exception) {
                Log.d(TAG, "API customer search failed: ${e.message}")
            }
        }
        return customerDao.search(query)
    }

    fun getCount(): Flow<Int> = customerDao.getCount()

    /** Create a customer. Online: API call. Offline: local insert + sync queue. */
    suspend fun createCustomer(request: CreateCustomerRequest): Long {
        if (serverMonitor.isEffectivelyOnline.value) {
            try {
                val response = customerApi.createCustomer(request)
                val detail = response.data ?: throw Exception(response.message ?: "Create failed")
                val entity = detail.toEntity()
                customerDao.insert(entity)
                return entity.id
            } catch (e: Exception) {
                Log.w(TAG, "Online create failed, falling back to offline queue: ${e.message}")
            }
        }

        val tempId = -System.currentTimeMillis()
        val now = java.time.Instant.now().toString().take(19).replace("T", " ")
        val entity = CustomerEntity(
            id = tempId,
            firstName = request.firstName,
            lastName = request.lastName,
            email = request.email,
            phone = request.phone,
            mobile = request.mobile,
            organization = request.organization,
            address1 = request.address1,
            address2 = request.address2,
            city = request.city,
            state = request.state,
            country = request.country,
            postcode = request.postcode,
            type = request.type,
            createdAt = now,
            updatedAt = now,
            locallyModified = true,
        )
        customerDao.insert(entity)

        syncQueueDao.insert(
            SyncQueueEntity(
                entityType = "customer",
                entityId = tempId,
                operation = "create",
                payload = gson.toJson(request),
            )
        )
        return tempId
    }

    /** Update a customer. Online: API call. Offline: local update + sync queue. */
    suspend fun updateCustomer(id: Long, request: UpdateCustomerRequest): CustomerEntity? {
        if (serverMonitor.isEffectivelyOnline.value) {
            try {
                val response = customerApi.updateCustomer(id, request)
                val detail = response.data ?: throw Exception(response.message ?: "Update failed")
                val entity = detail.toEntity()
                customerDao.insert(entity)
                return entity
            } catch (e: Exception) {
                Log.w(TAG, "Online update failed, falling back to offline queue: ${e.message}")
            }
        }

        syncQueueDao.insert(
            SyncQueueEntity(
                entityType = "customer",
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
                val response = customerApi.getCustomers(mapOf("pagesize" to "500", "page" to page.toString()))
                val customers = response.data?.customers ?: break
                if (customers.isEmpty()) break
                customerDao.insertAll(customers.map { it.toEntity() })
                val pagination = response.data?.pagination
                if (pagination == null || page >= pagination.totalPages) break
                page++
            }
        } catch (e: Exception) {
            Log.e(TAG, "refreshFromServer failed: ${e.message}")
        }
    }

    private fun refreshCustomersInBackground() {
        scope.launch {
            if (!serverMonitor.isEffectivelyOnline.value) return@launch
            try {
                val response = customerApi.getCustomers(mapOf("pagesize" to "500"))
                val customers = response.data?.customers ?: return@launch
                customerDao.insertAll(customers.map { it.toEntity() })
            } catch (e: Exception) {
                Log.d(TAG, "Background customer refresh failed: ${e.message}")
            }
        }
    }

    private fun refreshCustomerDetailInBackground(id: Long) {
        scope.launch {
            if (!serverMonitor.isEffectivelyOnline.value) return@launch
            try {
                val response = customerApi.getCustomer(id)
                val detail = response.data ?: return@launch
                customerDao.insert(detail.toEntity())
            } catch (e: Exception) {
                Log.d(TAG, "Background customer detail refresh failed: ${e.message}")
            }
        }
    }

    companion object {
        private const val TAG = "CustomerRepository"
    }
}

fun CustomerListItem.toEntity() = CustomerEntity(
    id = id,
    firstName = firstName,
    lastName = lastName,
    email = email,
    phone = phone,
    mobile = mobile,
    organization = organization,
    createdAt = createdAt ?: "",
    updatedAt = createdAt ?: "", // CustomerListItem doesn't have updatedAt
)

fun CustomerDetail.toEntity() = CustomerEntity(
    id = id,
    firstName = firstName,
    lastName = lastName,
    title = title,
    email = email,
    phone = phone,
    mobile = mobile,
    organization = organization,
    address1 = address1,
    address2 = address2,
    city = city,
    state = state,
    postcode = postcode,
    country = country,
    type = type,
    groupId = customerGroupId,
    groupName = customerGroupName,
    emailOptIn = (emailOptIn ?: 1) == 1,
    smsOptIn = (smsOptIn ?: 1) == 1,
    comments = comments,
    tags = customerTags,
    referredBy = referredBy,
    source = source,
    createdAt = createdAt ?: "",
    updatedAt = updatedAt ?: "",
)
