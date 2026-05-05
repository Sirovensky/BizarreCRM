package com.bizarreelectronics.crm.data.sync

import android.util.Log
import androidx.paging.ExperimentalPagingApi
import androidx.paging.LoadType
import androidx.paging.PagingState
import androidx.paging.RemoteMediator
import com.bizarreelectronics.crm.data.local.db.dao.InvoiceDao
import com.bizarreelectronics.crm.data.local.db.dao.SyncStateDao
import com.bizarreelectronics.crm.data.local.db.entities.InvoiceEntity
import com.bizarreelectronics.crm.data.local.db.entities.SyncStateEntity
import com.bizarreelectronics.crm.data.remote.api.InvoiceApi
import com.bizarreelectronics.crm.data.repository.toEntity

/**
 * Paging3 [RemoteMediator] for the invoices list (§7.1).
 *
 * ## Responsibilities
 *
 * - **REFRESH**: called on first load or explicit pull-to-refresh. Fetches the
 *   first page from `GET /invoices?cursor=null&limit=N`, upserts results into
 *   Room, and resets the [SyncStateEntity] cursor + exhaustion state.
 *
 * - **APPEND**: reads [SyncStateEntity.cursor] stored after the previous page,
 *   fetches the next page, upserts results, and marks
 *   [SyncStateEntity.serverExhaustedAt] when the server confirms no more pages.
 *
 * - **PREPEND**: always a no-op — newest-first list; prepend is handled by
 *   Room invalidation on upsert.
 *
 * ## initialize()
 *
 * Returns [InitializeAction.LAUNCH_INITIAL_REFRESH] when the cached data is
 * older than [STALE_THRESHOLD_MS] (15 minutes). Otherwise returns
 * [InitializeAction.SKIP_INITIAL_REFRESH] so the list renders from Room
 * instantly without a network round-trip.
 *
 * ## Cursor fallback
 *
 * The server may not yet support cursor params on `GET /invoices`. In that case
 * the response carries [InvoicePageResponse.cursor] == null, which is treated
 * as end-of-pagination. The list still renders from Room correctly.
 *
 * ## Filter key encoding
 *
 * [filterKey] encodes the active status-tab selection as `"status:<value>"`.
 * The blank key means "all invoices". Each distinct filter key has its own
 * [SyncStateEntity] row so switching tabs doesn't corrupt the shared cursor.
 *
 * @param invoiceDao   DAO for local invoice storage.
 * @param syncStateDao DAO for cursor / exhaustion bookkeeping.
 * @param invoiceApi   Retrofit interface for the server invoice endpoints.
 * @param filterKey    Optional filter tag stored in [SyncStateEntity.filterKey].
 * @param pageSize     Number of items per page (matches [PagingConfig.pageSize]).
 */
@OptIn(ExperimentalPagingApi::class)
class InvoiceRemoteMediator(
    private val invoiceDao: InvoiceDao,
    private val syncStateDao: SyncStateDao,
    private val invoiceApi: InvoiceApi,
    private val filterKey: String = "",
    private val pageSize: Int = PAGE_SIZE,
) : RemoteMediator<Int, InvoiceEntity>() {

    // -----------------------------------------------------------------------
    // initialize — decide whether to trigger an immediate remote refresh
    // -----------------------------------------------------------------------

    override suspend fun initialize(): InitializeAction {
        val syncState = syncStateDao.get(ENTITY, filterKey)
        val lastUpdatedAt = syncState?.lastUpdatedAt ?: 0L
        val stale = System.currentTimeMillis() - lastUpdatedAt > STALE_THRESHOLD_MS
        return if (stale) {
            Log.d(TAG, "initialize: stale=$stale → LAUNCH_INITIAL_REFRESH (lastUpdatedAt=$lastUpdatedAt)")
            InitializeAction.LAUNCH_INITIAL_REFRESH
        } else {
            Log.d(TAG, "initialize: stale=$stale → SKIP_INITIAL_REFRESH")
            InitializeAction.SKIP_INITIAL_REFRESH
        }
    }

    // -----------------------------------------------------------------------
    // load — the core RemoteMediator contract
    // -----------------------------------------------------------------------

    override suspend fun load(
        loadType: LoadType,
        state: PagingState<Int, InvoiceEntity>,
    ): MediatorResult {
        return try {
            when (loadType) {
                LoadType.PREPEND -> {
                    // Newest-first list — prepend is always a no-op.
                    MediatorResult.Success(endOfPaginationReached = true)
                }

                LoadType.REFRESH -> loadRefresh(state)

                LoadType.APPEND -> loadAppend(state)
            }
        } catch (e: Exception) {
            Log.e(TAG, "load($loadType) error [${e.javaClass.simpleName}]: ${e.message}")
            MediatorResult.Error(e)
        }
    }

    // -----------------------------------------------------------------------
    // REFRESH — fetch first page, reset oldest cursor
    // -----------------------------------------------------------------------

    private suspend fun loadRefresh(state: PagingState<Int, InvoiceEntity>): MediatorResult {
        Log.d(TAG, "loadRefresh: fetching first page")
        val response = invoiceApi.getInvoicePage(
            cursor = null, // always start from the beginning on refresh
            limit = state.config.pageSize,
            filters = filterParams(),
        )
        val page = response.data
            ?: return MediatorResult.Error(Exception("Null data on REFRESH"))

        val now = System.currentTimeMillis()
        val entities = page.invoices.map { it.toEntity() }
        invoiceDao.insertAll(entities)

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

        Log.d(TAG, "loadRefresh: upserted ${entities.size} invoices, exhausted=$exhausted cursor=${page.cursor}")
        return MediatorResult.Success(endOfPaginationReached = exhausted)
    }

    // -----------------------------------------------------------------------
    // APPEND — fetch next page using stored cursor
    // -----------------------------------------------------------------------

    private suspend fun loadAppend(state: PagingState<Int, InvoiceEntity>): MediatorResult {
        val syncState = syncStateDao.get(ENTITY, filterKey)

        // If the server previously confirmed exhaustion, stop early.
        if (syncState?.serverExhaustedAt != null) {
            Log.d(TAG, "loadAppend: serverExhausted → endOfPaginationReached=true")
            return MediatorResult.Success(endOfPaginationReached = true)
        }

        val cursor = syncState?.cursor
        Log.d(TAG, "loadAppend: fetching page after cursor=$cursor")

        val response = invoiceApi.getInvoicePage(
            cursor = cursor,
            limit = state.config.pageSize,
            filters = filterParams(),
        )
        val page = response.data
            ?: return MediatorResult.Error(Exception("Null data on APPEND"))

        val now = System.currentTimeMillis()
        val entities = page.invoices.map { it.toEntity() }
        invoiceDao.insertAll(entities)

        val exhausted = page.serverExhausted || page.cursor == null
        val updated = (syncState ?: SyncStateEntity(ENTITY, filterKey)).copy(
            cursor = page.cursor,
            serverExhaustedAt = if (exhausted) now else null,
            lastUpdatedAt = now,
        )
        syncStateDao.upsert(updated)

        Log.d(TAG, "loadAppend: upserted ${entities.size} invoices, exhausted=$exhausted cursor=${page.cursor}")
        return MediatorResult.Success(endOfPaginationReached = exhausted)
    }

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------

    /** Build Retrofit query map from the active [filterKey]. */
    private fun filterParams(): Map<String, String> {
        if (filterKey.isBlank()) return emptyMap()
        return when {
            filterKey.startsWith("status:") ->
                mapOf("status" to filterKey.removePrefix("status:"))
            else -> emptyMap()
        }
    }

    companion object {
        private const val TAG = "InvoiceRemoteMediator"
        private const val ENTITY = "invoices"
        const val PAGE_SIZE = 50

        /** Staleness threshold: 15 minutes in milliseconds. */
        const val STALE_THRESHOLD_MS = 15L * 60L * 1_000L
    }
}
