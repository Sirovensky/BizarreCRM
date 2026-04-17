package com.bizarreelectronics.crm.data.repository

import android.util.Log
import com.bizarreelectronics.crm.data.local.db.dao.InvoiceDao
import com.bizarreelectronics.crm.data.local.db.entities.InvoiceEntity
import com.bizarreelectronics.crm.data.remote.api.InvoiceApi
import com.bizarreelectronics.crm.data.remote.dto.InvoiceListItem
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
    private val invoiceApi: InvoiceApi,
    private val serverMonitor: ServerReachabilityMonitor,
) {
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
