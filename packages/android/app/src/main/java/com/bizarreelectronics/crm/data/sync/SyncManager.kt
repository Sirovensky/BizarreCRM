package com.bizarreelectronics.crm.data.sync

import android.util.Log
import com.bizarreelectronics.crm.data.local.db.dao.*
import com.bizarreelectronics.crm.data.local.db.entities.*
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.remote.api.CustomerApi
import com.bizarreelectronics.crm.data.remote.api.InventoryApi
import com.bizarreelectronics.crm.data.remote.api.InvoiceApi
import com.bizarreelectronics.crm.data.remote.api.NotificationApi
import com.bizarreelectronics.crm.data.remote.api.TicketApi
import com.bizarreelectronics.crm.data.remote.dto.AdjustStockRequest
import com.bizarreelectronics.crm.data.remote.dto.CreateCustomerRequest
import com.bizarreelectronics.crm.data.remote.dto.CreateTicketRequest
import com.bizarreelectronics.crm.data.remote.dto.RecordPaymentRequest
import com.bizarreelectronics.crm.data.remote.dto.UpdateCustomerRequest
import com.bizarreelectronics.crm.data.remote.dto.UpdateTicketRequest
import com.bizarreelectronics.crm.data.repository.CustomerRepository
import com.bizarreelectronics.crm.data.repository.InventoryRepository
import com.bizarreelectronics.crm.data.repository.InvoiceRepository
import com.bizarreelectronics.crm.data.repository.TicketRepository
import com.bizarreelectronics.crm.util.NetworkMonitor
import com.google.gson.Gson
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SyncManager @Inject constructor(
    private val syncQueueDao: SyncQueueDao,
    private val syncMetadataDao: SyncMetadataDao,
    private val ticketDao: TicketDao,
    private val customerDao: CustomerDao,
    private val notificationDao: NotificationDao,
    private val ticketApi: TicketApi,
    private val customerApi: CustomerApi,
    private val inventoryApi: InventoryApi,
    private val invoiceApi: InvoiceApi,
    private val notificationApi: NotificationApi,
    private val networkMonitor: NetworkMonitor,
    private val appPreferences: AppPreferences,
    private val gson: Gson,
    private val ticketRepository: TicketRepository,
    private val customerRepository: CustomerRepository,
    private val inventoryRepository: InventoryRepository,
    private val invoiceRepository: InvoiceRepository,
) {
    private val _isSyncing = MutableStateFlow(false)
    val isSyncing = _isSyncing.asStateFlow()

    /** Full sync — flush pending, then pull latest data from server into Room */
    suspend fun syncAll() {
        if (_isSyncing.value) return
        if (!networkMonitor.isCurrentlyOnline()) {
            Log.w(TAG, "Offline — skipping sync")
            return
        }

        _isSyncing.value = true
        try {
            withContext(Dispatchers.IO) {
                // 1. Flush pending local changes
                flushQueue()

                // 2. Pull all entity types via repositories (paginated)
                ticketRepository.refreshFromServer()
                customerRepository.refreshFromServer()
                inventoryRepository.refreshFromServer()
                invoiceRepository.refreshFromServer()

                // 3. Pull notifications
                syncNotifications()

                // Update last sync time
                appPreferences.lastFullSyncAt = java.time.Instant.now().toString().take(19).replace("T", " ")
            }
            Log.d(TAG, "Sync completed")
        } catch (e: Exception) {
            Log.e(TAG, "Sync failed: ${e.message}")
        } finally {
            _isSyncing.value = false
        }
    }

    private suspend fun syncNotifications() {
        try {
            val response = notificationApi.getNotifications(1)
            val data = response.data ?: return
            @Suppress("UNCHECKED_CAST")
            val notifList = (data as? Map<String, Any>)?.get("notifications") as? List<Map<String, Any>> ?: return

            val entities = notifList.mapNotNull { n ->
                try {
                    NotificationEntity(
                        id = (n["id"] as Number).toLong(),
                        userId = (n["user_id"] as? Number)?.toLong() ?: 0,
                        type = n["type"] as? String ?: "",
                        title = n["title"] as? String ?: "",
                        message = n["message"] as? String ?: "",
                        entityType = n["entity_type"] as? String,
                        entityId = (n["entity_id"] as? Number)?.toLong(),
                        isRead = (n["is_read"] as? Number)?.toInt() != 0,
                        createdAt = n["created_at"] as? String ?: "",
                    )
                } catch (_: Exception) { null }
            }
            notificationDao.insertAll(entities)
            Log.d(TAG, "Synced ${entities.size} notifications")
        } catch (e: Exception) {
            Log.e(TAG, "Notification sync failed: ${e.message}")
        }
    }

    /** Flush queued local changes to server */
    suspend fun flushQueue() {
        if (!networkMonitor.isCurrentlyOnline()) return

        val pending = syncQueueDao.getPending()
        for (entry in pending) {
            try {
                syncQueueDao.updateStatus(entry.id, "syncing", null)
                dispatchSyncEntry(entry)
                syncQueueDao.updateStatus(entry.id, "completed", null)
            } catch (e: Exception) {
                syncQueueDao.incrementRetry(entry.id)
                val newStatus = if (entry.retries >= 5) "failed" else "pending"
                syncQueueDao.updateStatus(entry.id, newStatus, e.message)
            }
        }
        syncQueueDao.deleteCompleted()
    }

    private suspend fun dispatchSyncEntry(entry: SyncQueueEntity) {
        when (entry.entityType) {
            "customer" -> dispatchCustomerEntry(entry)
            "ticket" -> dispatchTicketEntry(entry)
            "inventory" -> dispatchInventoryEntry(entry)
            "invoice" -> dispatchInvoiceEntry(entry)
            else -> Log.w(TAG, "Unknown entityType '${entry.entityType}' in sync queue (id=${entry.id})")
        }
    }

    private suspend fun dispatchCustomerEntry(entry: SyncQueueEntity) {
        when (entry.operation) {
            "create" -> {
                val request = gson.fromJson(entry.payload, CreateCustomerRequest::class.java)
                val response = customerApi.createCustomer(request)
                val created = response.data
                if (created != null && entry.entityId < 0) {
                    // Reconcile temp ID → server ID
                    customerDao.deleteById(entry.entityId)
                    customerDao.insert(com.bizarreelectronics.crm.data.repository.CustomerDetail_toEntity(created))
                }
            }
            "update" -> {
                val request = gson.fromJson(entry.payload, UpdateCustomerRequest::class.java)
                customerApi.updateCustomer(entry.entityId, request)
            }
            else -> Log.w(TAG, "Unknown operation '${entry.operation}' for customer #${entry.entityId}")
        }
    }

    private suspend fun dispatchTicketEntry(entry: SyncQueueEntity) {
        when (entry.operation) {
            "create" -> {
                val request = gson.fromJson(entry.payload, CreateTicketRequest::class.java)
                val response = ticketApi.createTicket(request)
                val created = response.data
                if (created != null && entry.entityId < 0) {
                    // Reconcile temp ID → server ID
                    ticketDao.deleteById(entry.entityId)
                    ticketDao.insert(com.bizarreelectronics.crm.data.repository.TicketDetail_toEntity(created))
                }
            }
            "update" -> {
                val request = gson.fromJson(entry.payload, UpdateTicketRequest::class.java)
                ticketApi.updateTicket(entry.entityId, request)
            }
            else -> Log.w(TAG, "Unknown operation '${entry.operation}' for ticket #${entry.entityId}")
        }
    }

    private suspend fun dispatchInventoryEntry(entry: SyncQueueEntity) {
        when (entry.operation) {
            "adjust_stock" -> {
                val request = gson.fromJson(entry.payload, AdjustStockRequest::class.java)
                inventoryApi.adjustStock(entry.entityId, request)
            }
            else -> Log.w(TAG, "Unknown operation '${entry.operation}' for inventory #${entry.entityId}")
        }
    }

    private suspend fun dispatchInvoiceEntry(entry: SyncQueueEntity) {
        when (entry.operation) {
            "record_payment" -> {
                val request = gson.fromJson(entry.payload, RecordPaymentRequest::class.java)
                invoiceApi.recordPayment(entry.entityId, request)
            }
            "void" -> {
                invoiceApi.voidInvoice(entry.entityId)
            }
            else -> Log.w(TAG, "Unknown operation '${entry.operation}' for invoice #${entry.entityId}")
        }
    }

    companion object {
        private const val TAG = "SyncManager"
    }
}

// Helper to call toEntity from the repository package
private fun CustomerDetail_toEntity(detail: com.bizarreelectronics.crm.data.remote.dto.CustomerDetail) =
    com.bizarreelectronics.crm.data.repository.toEntity(detail)

private fun TicketDetail_toEntity(detail: com.bizarreelectronics.crm.data.remote.dto.TicketDetail) =
    com.bizarreelectronics.crm.data.repository.toEntity(detail)
