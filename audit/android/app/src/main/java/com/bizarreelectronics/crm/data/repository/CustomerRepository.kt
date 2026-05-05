package com.bizarreelectronics.crm.data.repository

import android.util.Log
import androidx.paging.ExperimentalPagingApi
import androidx.paging.Pager
import androidx.paging.PagingConfig
import androidx.paging.PagingData
import com.bizarreelectronics.crm.data.local.db.dao.CustomerDao
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.local.db.dao.SyncStateDao
import com.bizarreelectronics.crm.data.local.db.entities.CustomerEntity
import com.bizarreelectronics.crm.data.local.db.entities.SyncQueueEntity
import com.bizarreelectronics.crm.data.local.prefs.OfflineIdGenerator
import com.bizarreelectronics.crm.data.remote.api.CustomerApi
import com.bizarreelectronics.crm.data.remote.dto.CreateCustomerRequest
import com.bizarreelectronics.crm.data.remote.dto.CustomerDetail
import com.bizarreelectronics.crm.data.remote.dto.CustomerListItem
import com.bizarreelectronics.crm.data.remote.dto.UpdateCustomerRequest
import com.bizarreelectronics.crm.data.sync.CustomerRemoteMediator
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import com.google.gson.Gson
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch
import java.io.IOException
import java.net.SocketTimeoutException
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class CustomerRepository @Inject constructor(
    private val customerDao: CustomerDao,
    private val customerApi: CustomerApi,
    private val syncQueueDao: SyncQueueDao,
    private val syncStateDao: SyncStateDao,
    private val serverMonitor: ServerReachabilityMonitor,
    private val offlineIdGenerator: OfflineIdGenerator,
    private val gson: Gson,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    // -----------------------------------------------------------------------
    // Paging3 — cursor-based paged stream (plan:L874)
    // -----------------------------------------------------------------------

    /**
     * Returns a cold [Flow]<[PagingData]<[CustomerEntity]>> backed by Room and
     * [CustomerRemoteMediator]. Sort is applied at the DB layer via the matching
     * PagingSource variant; filterKey gates the remote fetch.
     *
     * @param sort      One of "recent" | "az" | "za" — selects the PagingSource.
     * @param filterKey Optional filter tag (e.g. "tier:VIP").
     */
    @OptIn(ExperimentalPagingApi::class)
    fun customersPaged(
        sort: String = "recent",
        filterKey: String = "",
    ): Flow<PagingData<CustomerEntity>> {
        val mediator = CustomerRemoteMediator(
            customerDao = customerDao,
            syncStateDao = syncStateDao,
            customerApi = customerApi,
            filterKey = filterKey,
        )
        val pagingSourceFactory: () -> androidx.paging.PagingSource<Int, CustomerEntity> = when (sort) {
            "az" -> { { customerDao.pagingSourceAZ() } }
            "za" -> { { customerDao.pagingSourceZA() } }
            else -> { { customerDao.pagingSource() } }
        }
        return Pager(
            config = PagingConfig(
                pageSize = CustomerRemoteMediator.PAGE_SIZE,
                enablePlaceholders = false,
                prefetchDistance = 10,
            ),
            remoteMediator = mediator,
            pagingSourceFactory = pagingSourceFactory,
        ).flow
    }

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
            fetchSearchResultsWithRetry(query)
        }
        return customerDao.search(query)
    }

    /**
     * Performs the search API call with one retry on transient network errors only
     * (AP7). Non-network failures — bad status codes, JSON parse errors, cancellation —
     * are logged and surfaced once; retrying those would just burn the user's battery.
     *
     * Uses defensive null-handling on the response (AP1) so that any future shape
     * change on the server (e.g. migration to a wrapped list) cannot crash the app with
     * an NPE during typeahead search.
     */
    private suspend fun fetchSearchResultsWithRetry(query: String, attempt: Int = 0) {
        try {
            val response = customerApi.searchCustomers(query)
            // AP1: defensively unwrap. Current API returns ApiResponse<List<CustomerListItem>>
            // directly, but we treat null/empty as a no-op rather than crashing.
            val customers = response.data ?: return
            if (customers.isEmpty()) return
            customerDao.insertAll(customers.map { it.toEntity() })
        } catch (e: Exception) {
            val retryable = e is IOException || e is SocketTimeoutException
            if (retryable && attempt < MAX_SEARCH_RETRIES) {
                Log.d(TAG, "API customer search transient failure [${e.javaClass.simpleName}] attempt=$attempt, retrying: ${e.message}")
                fetchSearchResultsWithRetry(query, attempt + 1)
            } else {
                // Non-retryable (or retries exhausted) — log class + message and return.
                Log.w(TAG, "API customer search failed [${e.javaClass.simpleName}]: ${e.message}")
            }
        }
    }

    fun getCount(): Flow<Int> = customerDao.getCount()

    /**
     * Create a customer. Online: API call. Offline: local insert + sync queue.
     *
     * An idempotency key is attached to the request body before dispatch so that a
     * retry of the same logical create (for example after a transient network error)
     * does not produce duplicate rows on the server. The key is persisted to the sync
     * queue payload so subsequent retries continue to reuse it. See AP5.
     */
    suspend fun createCustomer(request: CreateCustomerRequest): Long {
        val idempotentRequest = request.copy(
            clientRequestId = request.clientRequestId ?: offlineIdGenerator.newIdempotencyKey(),
        )

        if (serverMonitor.isEffectivelyOnline.value) {
            try {
                val response = customerApi.createCustomer(idempotentRequest)
                val detail = response.data ?: throw Exception(response.message ?: "Create failed")
                val entity = detail.toEntity()
                customerDao.insert(entity)
                return entity.id
            } catch (e: Exception) {
                Log.w(TAG, "Online customer create failed [${e.javaClass.simpleName}], falling back to offline queue: ${e.message}")
            }
        }

        val tempId = offlineIdGenerator.nextTempId()
        val now = java.time.Instant.now().toString().take(19).replace("T", " ")
        val entity = CustomerEntity(
            id = tempId,
            firstName = idempotentRequest.firstName,
            lastName = idempotentRequest.lastName,
            email = idempotentRequest.email,
            phone = idempotentRequest.phone,
            mobile = idempotentRequest.mobile,
            organization = idempotentRequest.organization,
            address1 = idempotentRequest.address1,
            address2 = idempotentRequest.address2,
            city = idempotentRequest.city,
            state = idempotentRequest.state,
            country = idempotentRequest.country,
            postcode = idempotentRequest.postcode,
            type = idempotentRequest.type,
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
                payload = gson.toJson(idempotentRequest),
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
                Log.w(TAG, "Online customer update failed [${e.javaClass.simpleName}], falling back to offline queue: ${e.message}")
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

    /**
     * Full pull from server — used by SyncManager. Walks paginated results up to a
     * hard safety cap (AP4). Without the cap, a misbehaving server or a loop in the
     * totalPages count could trap the client in an infinite refresh.
     */
    suspend fun refreshFromServer() {
        if (!serverMonitor.isEffectivelyOnline.value) return
        try {
            var page = 1
            while (page <= MAX_PAGINATION_PAGES) {
                val response = customerApi.getCustomers(mapOf("pagesize" to "500", "page" to page.toString()))
                val customers = response.data?.customers ?: break
                if (customers.isEmpty()) break
                customerDao.insertAll(customers.map { it.toEntity() })
                val pagination = response.data?.pagination
                if (pagination == null || page >= pagination.totalPages) break
                page++
            }
            if (page > MAX_PAGINATION_PAGES) {
                Log.w(TAG, "Customer pagination hit safety cap of $MAX_PAGINATION_PAGES pages — aborting refresh")
            }
        } catch (e: Exception) {
            Log.e(TAG, "customer refreshFromServer failed [${e.javaClass.simpleName}]: ${e.message}")
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
                Log.d(TAG, "Background customer refresh failed [${e.javaClass.simpleName}]: ${e.message}")
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
                Log.d(TAG, "Background customer detail refresh failed [${e.javaClass.simpleName}]: ${e.message}")
            }
        }
    }

    companion object {
        private const val TAG = "CustomerRepository"

        /**
         * Hard safety cap on pagination loops (AP4). If the server ever reports a
         * bogus `totalPages` we refuse to walk the list forever.
         */
        private const val MAX_PAGINATION_PAGES = 1000

        /**
         * How many times to retry a transient network failure during typeahead search
         * (AP7). One retry balances resilience against flakey mobile data with not
         * burning the user's battery on a server that is actually down.
         */
        private const val MAX_SEARCH_RETRIES = 1
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
    // AP6: TCPA/CAN-SPAM compliance — opt-in must NEVER default to true when the
    // server omits the field. Unknown = not opted in.
    emailOptIn = emailOptIn == 1,
    smsOptIn = smsOptIn == 1,
    comments = comments,
    tags = customerTags,
    referredBy = referredBy,
    source = source,
    createdAt = createdAt ?: "",
    updatedAt = updatedAt ?: "",
)
