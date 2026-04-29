package com.bizarreelectronics.crm.data.repository

import android.util.Log
import androidx.paging.ExperimentalPagingApi
import androidx.paging.Pager
import androidx.paging.PagingConfig
import androidx.paging.PagingData
import com.bizarreelectronics.crm.data.local.db.dao.InvoiceDao
import com.bizarreelectronics.crm.data.local.db.dao.SyncStateDao
import com.bizarreelectronics.crm.data.local.db.entities.InvoiceEntity
import com.bizarreelectronics.crm.data.remote.api.InvoiceApi
import com.bizarreelectronics.crm.data.remote.dto.InvoiceListItem
import com.bizarreelectronics.crm.data.sync.InvoiceRemoteMediator
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import com.bizarreelectronics.crm.util.toCentsOrZero
import com.bizarreelectronics.crm.util.toDollars
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class InvoiceRepository @Inject constructor(
    private val invoiceDao: InvoiceDao,
    private val syncStateDao: SyncStateDao,
    private val invoiceApi: InvoiceApi,
    private val serverMonitor: ServerReachabilityMonitor,
) {

    // ── Paging3 (§7.1) ──────────────────────────────────────────────────────

    /**
     * Returns a [Flow] of [PagingData] for the invoices list backed by
     * [InvoiceRemoteMediator] and Room. The Pager survives configuration
     * changes when cached in a ViewModel via [cachedIn(viewModelScope)].
     *
     * [filterKey] encodes the active filter as `"status:<value>"` or blank for
     * all invoices. Each distinct key gets its own [SyncStateEntity] row so
     * switching tabs doesn't corrupt the shared cursor.
     */
    @OptIn(ExperimentalPagingApi::class)
    fun invoicesPaged(filterKey: String = ""): Flow<PagingData<InvoiceEntity>> {
        val mediator = InvoiceRemoteMediator(
            invoiceDao = invoiceDao,
            syncStateDao = syncStateDao,
            invoiceApi = invoiceApi,
            filterKey = filterKey,
            pageSize = InvoiceRemoteMediator.PAGE_SIZE,
        )
        val statusValue = if (filterKey.startsWith("status:")) {
            filterKey.removePrefix("status:")
        } else {
            null
        }
        return Pager(
            config = PagingConfig(
                pageSize = InvoiceRemoteMediator.PAGE_SIZE,
                enablePlaceholders = false,
            ),
            remoteMediator = mediator,
            pagingSourceFactory = {
                if (statusValue != null) {
                    invoiceDao.pagingSourceByStatus(statusValue)
                } else {
                    invoiceDao.pagingSource()
                }
            },
        ).flow
    }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    fun getInvoices(): Flow<List<InvoiceEntity>> {
        refreshInvoicesInBackground()
        return invoiceDao.getAll()
    }

    fun getInvoice(id: Long): Flow<InvoiceEntity?> {
        refreshInvoiceDetailInBackground(id)
        return invoiceDao.getById(id)
    }

    fun getByCustomerId(customerId: Long): Flow<List<InvoiceEntity>> = invoiceDao.getByCustomerId(customerId)

    fun getByStatus(status: String): Flow<List<InvoiceEntity>> = invoiceDao.getByStatus(status)

    /**
     * Outstanding balance, converted from the DAO's Long cents back to Double
     * dollars for compatibility with existing UI observers. Consumers that want
     * exact-cent precision should migrate to [getOutstandingBalanceCents].
     */
    fun getOutstandingBalance(): Flow<Double?> =
        invoiceDao.getOutstandingBalance().map { cents -> cents?.toDollars() }

    /** Outstanding balance in **cents** — preferred over [getOutstandingBalance]. */
    fun getOutstandingBalanceCents(): Flow<Long?> = invoiceDao.getOutstandingBalance()

    // ── Cursor-based paging (§7.1) ────────────────────────────────────────────

    /**
     * Returns a single page of invoices for offline-first cursor paging.
     *
     * Online: calls [InvoiceApi.getInvoicePage] with [cursor]; inserts results into
     * Room then returns the list plus the next cursor token.
     * Offline: falls back to [InvoiceDao.getPage] keyset query so the list still scrolls.
     *
     * @return [Pair] of (items, nextCursor). nextCursor is null when no more pages exist.
     */
    suspend fun loadInvoicesPage(
        cursor: String?,
        limit: Int = 50,
        filters: Map<String, String> = emptyMap(),
    ): Pair<List<InvoiceEntity>, String?> {
        if (serverMonitor.isEffectivelyOnline.value) {
            try {
                val response = invoiceApi.getInvoicePage(cursor, limit, filters)
                val page = response.data
                if (page != null && page.invoices.isNotEmpty()) {
                    invoiceDao.insertAll(page.invoices.map { it.toEntity() })
                    return Pair(page.invoices.map { it.toEntity() }, page.cursor)
                }
                // Server returned empty or null data — treat as end of list.
                return Pair(emptyList(), null)
            } catch (e: Exception) {
                Log.d(TAG, "Cursor page fetch failed, falling back to Room: ${e.message}")
            }
        }

        // Offline fallback: keyset pagination from local Room cache.
        val beforeCreatedAt = cursor ?: ""
        val rows = invoiceDao.getPage(beforeCreatedAt, limit)
        // Derive the next cursor from the last row's created_at; null when fewer than
        // [limit] rows returned (end of local cache).
        val nextCursor = if (rows.size >= limit) rows.last().createdAt else null
        return Pair(rows, nextCursor)
    }

    /**
     * Full pull from server — used by SyncManager.
     *
     * @audit-fixed: Section 33 / D8 — was an unbounded `while (true)` loop.
     * Mirrors the AP4 cap that TicketRepository / CustomerRepository already
     * enforce. A misbehaving server reporting a bogus `totalPages` could trap
     * the client in an infinite refresh that drains battery and burns API quota.
     */
    suspend fun refreshFromServer() {
        if (!serverMonitor.isEffectivelyOnline.value) return
        try {
            var page = 1
            while (page <= MAX_PAGINATION_PAGES) {
                val response = invoiceApi.getInvoices(mapOf("pagesize" to "200", "page" to page.toString()))
                val invoices = response.data?.invoices ?: break
                if (invoices.isEmpty()) break
                invoiceDao.insertAll(invoices.map { it.toEntity() })
                val pagination = response.data?.pagination
                if (pagination == null || page >= pagination.totalPages) break
                page++
            }
            if (page > MAX_PAGINATION_PAGES) {
                Log.w(TAG, "Invoice pagination hit safety cap of $MAX_PAGINATION_PAGES pages — aborting refresh")
            }
        } catch (e: Exception) {
            Log.e(TAG, "refreshFromServer failed: ${e.message}")
        }
    }

    private fun refreshInvoicesInBackground() {
        scope.launch {
            if (!serverMonitor.isEffectivelyOnline.value) return@launch
            try {
                val response = invoiceApi.getInvoices(mapOf("pagesize" to "200"))
                val invoices = response.data?.invoices ?: return@launch
                invoiceDao.insertAll(invoices.map { it.toEntity() })
            } catch (e: Exception) {
                Log.d(TAG, "Background invoice refresh failed: ${e.message}")
            }
        }
    }

    private fun refreshInvoiceDetailInBackground(id: Long) {
        scope.launch {
            runCatching { refreshInvoiceDetail(id) }
                .onFailure { Log.d(TAG, "Background invoice detail refresh failed: ${it.message}") }
        }
    }

    /**
     * AND-20260414-M8: public suspend variant of the detail refresh so callers
     * (e.g. InvoiceDetailViewModel after a payment or void) can explicitly
     * re-sync the cached `InvoiceEntity` and observe the result on the Room
     * Flow. Previously the same work was only available via the private
     * background-scope version, which fire-and-forget and decoupled the UI
     * from the sync completion.
     *
     * No-ops when offline — callers should surface a user-visible message.
     */
    suspend fun refreshInvoiceDetail(id: Long) {
        if (!serverMonitor.isEffectivelyOnline.value) return
        val response = invoiceApi.getInvoice(id)
        val detail = response.data?.invoice ?: return
        val entity = InvoiceEntity(
            id = detail.id,
            orderId = detail.orderId ?: "",
            ticketId = detail.ticketId,
            customerId = detail.customerId,
            status = detail.status ?: "draft",
            subtotal = detail.subtotal.toCentsOrZero(),
            discount = detail.discount.toCentsOrZero(),
            totalTax = detail.totalTax.toCentsOrZero(),
            total = detail.total.toCentsOrZero(),
            amountPaid = detail.amountPaid.toCentsOrZero(),
            amountDue = detail.amountDue.toCentsOrZero(),
            dueOn = detail.dueOn,
            notes = null,
            createdBy = detail.createdBy,
            createdAt = detail.createdAt ?: "",
            updatedAt = detail.updatedAt ?: "",
        )
        invoiceDao.insert(entity)
    }

    companion object {
        private const val TAG = "InvoiceRepository"

        /**
         * @audit-fixed: D8 — Hard safety cap on pagination loops.
         */
        private const val MAX_PAGINATION_PAGES = 1000
    }
}

fun InvoiceListItem.toEntity() = InvoiceEntity(
    id = id,
    orderId = orderId ?: "",
    ticketId = ticketId,
    customerId = customerId,
    status = status ?: "draft",
    subtotal = subtotal.toCentsOrZero(),
    discount = discount.toCentsOrZero(),
    totalTax = totalTax.toCentsOrZero(),
    total = total.toCentsOrZero(),
    amountPaid = amountPaid.toCentsOrZero(),
    amountDue = amountDue.toCentsOrZero(),
    dueOn = dueOn,
    notes = null,
    createdBy = null,
    customerName = customerName,
    createdAt = createdAt ?: "",
    updatedAt = "",
)
