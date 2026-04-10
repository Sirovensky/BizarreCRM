package com.bizarreelectronics.crm.data.repository

import android.util.Log
import com.bizarreelectronics.crm.data.local.db.dao.InvoiceDao
import com.bizarreelectronics.crm.data.local.db.entities.InvoiceEntity
import com.bizarreelectronics.crm.data.remote.api.InvoiceApi
import com.bizarreelectronics.crm.data.remote.dto.InvoiceListItem
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
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

    fun getOutstandingBalance(): Flow<Double?> = invoiceDao.getOutstandingBalance()

    /** Full pull from server — used by SyncManager. */
    suspend fun refreshFromServer() {
        if (!serverMonitor.isEffectivelyOnline.value) return
        try {
            var page = 1
            while (true) {
                val response = invoiceApi.getInvoices(mapOf("pagesize" to "200", "page" to page.toString()))
                val invoices = response.data?.invoices ?: break
                if (invoices.isEmpty()) break
                invoiceDao.insertAll(invoices.map { it.toEntity() })
                val pagination = response.data?.pagination
                if (pagination == null || page >= pagination.totalPages) break
                page++
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
            if (!serverMonitor.isEffectivelyOnline.value) return@launch
            try {
                val response = invoiceApi.getInvoice(id)
                val detail = response.data?.invoice ?: return@launch
                val entity = InvoiceEntity(
                    id = detail.id,
                    orderId = detail.orderId ?: "",
                    ticketId = detail.ticketId,
                    customerId = detail.customerId,
                    status = detail.status ?: "draft",
                    subtotal = detail.subtotal ?: 0.0,
                    discount = detail.discount ?: 0.0,
                    totalTax = detail.totalTax ?: 0.0,
                    total = detail.total ?: 0.0,
                    amountPaid = detail.amountPaid ?: 0.0,
                    amountDue = detail.amountDue ?: 0.0,
                    dueOn = detail.dueOn,
                    notes = null,
                    createdBy = detail.createdBy,
                    createdAt = detail.createdAt ?: "",
                    updatedAt = detail.updatedAt ?: "",
                )
                invoiceDao.insert(entity)
            } catch (e: Exception) {
                Log.d(TAG, "Background invoice detail refresh failed: ${e.message}")
            }
        }
    }

    companion object {
        private const val TAG = "InvoiceRepository"
    }
}

fun InvoiceListItem.toEntity() = InvoiceEntity(
    id = id,
    orderId = orderId ?: "",
    ticketId = ticketId,
    customerId = customerId,
    status = status ?: "draft",
    subtotal = subtotal ?: 0.0,
    discount = discount ?: 0.0,
    totalTax = totalTax ?: 0.0,
    total = total ?: 0.0,
    amountPaid = amountPaid ?: 0.0,
    amountDue = amountDue ?: 0.0,
    dueOn = dueOn,
    notes = null,
    createdBy = null,
    customerName = customerName,
    createdAt = createdAt ?: "",
    updatedAt = "",
)
