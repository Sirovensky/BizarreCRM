package com.bizarreelectronics.crm.data.sync

import android.util.Log
import androidx.paging.ExperimentalPagingApi
import androidx.paging.LoadType
import androidx.paging.PagingState
import androidx.paging.RemoteMediator
import com.bizarreelectronics.crm.data.local.db.dao.CustomerDao
import com.bizarreelectronics.crm.data.local.db.dao.SyncStateDao
import com.bizarreelectronics.crm.data.local.db.entities.CustomerEntity
import com.bizarreelectronics.crm.data.local.db.entities.SyncStateEntity
import com.bizarreelectronics.crm.data.remote.api.CustomerApi
import com.bizarreelectronics.crm.data.repository.toEntity

/**
 * Paging3 [RemoteMediator] for the customers list (plan:L874).
 *
 * Mirrors [TicketRemoteMediator] exactly — same REFRESH/APPEND/PREPEND
 * contract, same staleness threshold, same SyncStateDao bookkeeping.
 *
 * @param customerDao   DAO for local customer storage.
 * @param syncStateDao  DAO for cursor / exhaustion bookkeeping.
 * @param customerApi   Retrofit interface for the server customer endpoint.
 * @param filterKey     Optional filter tag stored in [SyncStateEntity.filterKey].
 * @param pageSize      Number of items per page (matches [PagingConfig.pageSize]).
 */
@OptIn(ExperimentalPagingApi::class)
class CustomerRemoteMediator(
    private val customerDao: CustomerDao,
    private val syncStateDao: SyncStateDao,
    private val customerApi: CustomerApi,
    private val filterKey: String = "",
    private val pageSize: Int = PAGE_SIZE,
) : RemoteMediator<Int, CustomerEntity>() {

    override suspend fun initialize(): InitializeAction {
        val syncState = syncStateDao.get(ENTITY, filterKey)
        val lastUpdatedAt = syncState?.lastUpdatedAt ?: 0L
        val stale = System.currentTimeMillis() - lastUpdatedAt > STALE_THRESHOLD_MS
        return if (stale) {
            Log.d(TAG, "initialize: stale=$stale → LAUNCH_INITIAL_REFRESH")
            InitializeAction.LAUNCH_INITIAL_REFRESH
        } else {
            Log.d(TAG, "initialize: stale=$stale → SKIP_INITIAL_REFRESH")
            InitializeAction.SKIP_INITIAL_REFRESH
        }
    }

    override suspend fun load(
        loadType: LoadType,
        state: PagingState<Int, CustomerEntity>,
    ): MediatorResult {
        return try {
            when (loadType) {
                LoadType.PREPEND -> MediatorResult.Success(endOfPaginationReached = true)
                LoadType.REFRESH -> loadRefresh(state)
                LoadType.APPEND -> loadAppend(state)
            }
        } catch (e: Exception) {
            Log.e(TAG, "load($loadType) error [${e.javaClass.simpleName}]: ${e.message}")
            MediatorResult.Error(e)
        }
    }

    private suspend fun loadRefresh(state: PagingState<Int, CustomerEntity>): MediatorResult {
        Log.d(TAG, "loadRefresh: fetching first page")
        val response = customerApi.getCustomerPage(
            cursor = null,
            limit = state.config.pageSize,
            filters = filterParams(),
        )
        val page = response.data
            ?: return MediatorResult.Error(Exception("Null data on REFRESH"))

        val now = System.currentTimeMillis()
        val entities = page.customers.map { it.toEntity() }
        customerDao.insertAll(entities)

        val exhausted = page.serverExhausted || page.cursor == null
        val existing = syncStateDao.get(ENTITY, filterKey) ?: SyncStateEntity(ENTITY, filterKey)
        syncStateDao.upsert(
            existing.copy(
                cursor = page.cursor,
                oldestCachedAt = now,
                serverExhaustedAt = if (exhausted) now else null,
                lastUpdatedAt = now,
            ),
        )

        Log.d(TAG, "loadRefresh: upserted ${entities.size} customers, exhausted=$exhausted cursor=${page.cursor}")
        return MediatorResult.Success(endOfPaginationReached = exhausted)
    }

    private suspend fun loadAppend(state: PagingState<Int, CustomerEntity>): MediatorResult {
        val syncState = syncStateDao.get(ENTITY, filterKey)

        if (syncState?.serverExhaustedAt != null) {
            Log.d(TAG, "loadAppend: serverExhausted → endOfPaginationReached=true")
            return MediatorResult.Success(endOfPaginationReached = true)
        }

        val cursor = syncState?.cursor
        Log.d(TAG, "loadAppend: fetching page after cursor=$cursor")

        val response = customerApi.getCustomerPage(
            cursor = cursor,
            limit = state.config.pageSize,
            filters = filterParams(),
        )
        val page = response.data
            ?: return MediatorResult.Error(Exception("Null data on APPEND"))

        val now = System.currentTimeMillis()
        val entities = page.customers.map { it.toEntity() }
        customerDao.insertAll(entities)

        val exhausted = page.serverExhausted || page.cursor == null
        val updated = (syncState ?: SyncStateEntity(ENTITY, filterKey)).copy(
            cursor = page.cursor,
            serverExhaustedAt = if (exhausted) now else null,
            lastUpdatedAt = now,
        )
        syncStateDao.upsert(updated)

        Log.d(TAG, "loadAppend: upserted ${entities.size} customers, exhausted=$exhausted cursor=${page.cursor}")
        return MediatorResult.Success(endOfPaginationReached = exhausted)
    }

    private fun filterParams(): Map<String, String> {
        if (filterKey.isBlank()) return emptyMap()
        return when {
            filterKey.startsWith("tag:") -> mapOf("tag" to filterKey.removePrefix("tag:"))
            filterKey.startsWith("tier:") -> mapOf("ltv_tier" to filterKey.removePrefix("tier:"))
            filterKey.startsWith("city:") -> mapOf("city" to filterKey.removePrefix("city:"))
            filterKey == "balance" -> mapOf("has_balance" to "1")
            filterKey == "open_tickets" -> mapOf("has_open_tickets" to "1")
            else -> emptyMap()
        }
    }

    companion object {
        private const val TAG = "CustomerRemoteMediator"
        private const val ENTITY = "customers"
        const val PAGE_SIZE = 50
        const val STALE_THRESHOLD_MS = 15L * 60L * 1_000L
    }
}
