package com.bizarreelectronics.crm.data.sync

import android.util.Log
import com.bizarreelectronics.crm.data.local.db.dao.*
import com.bizarreelectronics.crm.data.local.db.entities.*
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.remote.api.CustomerApi
import com.bizarreelectronics.crm.data.remote.api.InventoryApi
import com.bizarreelectronics.crm.data.remote.api.InvoiceApi
import com.bizarreelectronics.crm.data.remote.api.NotificationApi
import com.bizarreelectronics.crm.data.remote.api.EstimateApi
import com.bizarreelectronics.crm.data.remote.api.ExpenseApi
import com.bizarreelectronics.crm.data.remote.api.LeadApi
import com.bizarreelectronics.crm.data.remote.api.SettingsApi
import com.bizarreelectronics.crm.data.remote.api.SmsApi
import com.bizarreelectronics.crm.data.remote.api.TicketApi
import com.bizarreelectronics.crm.data.remote.dto.AddTicketPartRequest
import com.bizarreelectronics.crm.data.remote.dto.AdjustStockRequest
import com.bizarreelectronics.crm.data.remote.dto.CreateCustomerRequest
import com.bizarreelectronics.crm.data.remote.dto.CreateEstimateRequest
import com.bizarreelectronics.crm.data.remote.dto.CreateExpenseRequest
import com.bizarreelectronics.crm.data.remote.dto.CreateInventoryRequest
import com.bizarreelectronics.crm.data.remote.dto.CreateLeadRequest
import com.bizarreelectronics.crm.data.remote.dto.CreateTicketRequest
import com.bizarreelectronics.crm.data.remote.dto.RecordPaymentRequest
import com.bizarreelectronics.crm.data.remote.dto.UpdateEstimateRequest
import com.bizarreelectronics.crm.data.remote.dto.UpdateExpenseRequest
import com.bizarreelectronics.crm.data.remote.dto.UpdateLeadRequest
import com.bizarreelectronics.crm.data.remote.dto.UpdateCustomerRequest
import com.bizarreelectronics.crm.data.remote.dto.UpdateTicketDeviceRequest
import com.bizarreelectronics.crm.data.remote.dto.UpdateTicketRequest
import com.bizarreelectronics.crm.data.repository.CustomerRepository
import com.bizarreelectronics.crm.data.repository.InventoryRepository
import com.bizarreelectronics.crm.data.repository.InvoiceRepository
import com.bizarreelectronics.crm.data.repository.EstimateRepository
import com.bizarreelectronics.crm.data.repository.ExpenseRepository
import com.bizarreelectronics.crm.data.repository.LeadRepository
import com.bizarreelectronics.crm.data.repository.SmsRepository
import com.bizarreelectronics.crm.data.repository.TicketRepository
import com.bizarreelectronics.crm.data.repository.toEntity
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
    private val inventoryDao: InventoryDao,
    private val smsDao: SmsDao,
    private val notificationDao: NotificationDao,
    private val ticketApi: TicketApi,
    private val customerApi: CustomerApi,
    private val inventoryApi: InventoryApi,
    private val invoiceApi: InvoiceApi,
    private val smsApi: SmsApi,
    private val leadApi: LeadApi,
    private val estimateApi: EstimateApi,
    private val expenseApi: ExpenseApi,
    private val settingsApi: SettingsApi,
    private val notificationApi: NotificationApi,
    private val networkMonitor: NetworkMonitor,
    private val appPreferences: AppPreferences,
    private val gson: Gson,
    private val ticketRepository: TicketRepository,
    private val customerRepository: CustomerRepository,
    private val inventoryRepository: InventoryRepository,
    private val invoiceRepository: InvoiceRepository,
    private val smsRepository: SmsRepository,
    private val leadRepository: LeadRepository,
    private val estimateRepository: EstimateRepository,
    private val expenseRepository: ExpenseRepository,
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

                // 3. Pull leads, estimates, expenses
                leadRepository.refreshFromServer()
                estimateRepository.refreshFromServer()
                expenseRepository.refreshFromServer()

                // 4. Pull SMS conversations and messages
                smsRepository.refreshFromServer()

                // 4. Pull notifications
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
            "ticket_note" -> dispatchTicketNoteEntry(entry)
            "ticket_device" -> dispatchTicketDeviceEntry(entry)
            "inventory" -> dispatchInventoryEntry(entry)
            "invoice" -> dispatchInvoiceEntry(entry)
            "sms" -> dispatchSmsEntry(entry)
            "employee" -> dispatchEmployeeEntry(entry)
            "checkout" -> dispatchCheckoutEntry(entry)
            "lead" -> dispatchLeadEntry(entry)
            "estimate" -> dispatchEstimateEntry(entry)
            "expense" -> dispatchExpenseEntry(entry)
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
                    customerDao.insert(created.toEntity())
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
                    ticketDao.insert(created.toEntity())
                }
            }
            "update" -> {
                val request = gson.fromJson(entry.payload, UpdateTicketRequest::class.java)
                ticketApi.updateTicket(entry.entityId, request)
            }
            "convert_to_invoice" -> {
                // Queued from TicketDetailScreen when offline. Server returns the new invoice;
                // we don't navigate here (no UI context), we just fire and forget.
                ticketApi.convertToInvoice(entry.entityId)
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
            "create" -> {
                val request = gson.fromJson(entry.payload, CreateInventoryRequest::class.java)
                val response = inventoryApi.createItem(request)
                val created = response.data?.item
                if (created != null && entry.entityId < 0) {
                    // Reconcile temp ID → server ID
                    inventoryDao.deleteById(entry.entityId)
                    inventoryDao.insert(created.toEntity())
                }
            }
            "update" -> {
                val request = gson.fromJson(entry.payload, CreateInventoryRequest::class.java)
                inventoryApi.updateItem(entry.entityId, request)
            }
            else -> Log.w(TAG, "Unknown operation '${entry.operation}' for inventory #${entry.entityId}")
        }
    }

    private suspend fun dispatchLeadEntry(entry: SyncQueueEntity) {
        when (entry.operation) {
            "create" -> {
                val request = gson.fromJson(entry.payload, CreateLeadRequest::class.java)
                leadApi.createLead(request)
            }
            "update" -> {
                val request = gson.fromJson(entry.payload, UpdateLeadRequest::class.java)
                leadApi.updateLead(entry.entityId, request)
            }
            "delete" -> leadApi.deleteLead(entry.entityId)
            else -> Log.w(TAG, "Unknown operation '${entry.operation}' for lead #${entry.entityId}")
        }
    }

    private suspend fun dispatchEstimateEntry(entry: SyncQueueEntity) {
        when (entry.operation) {
            "create" -> {
                val request = gson.fromJson(entry.payload, CreateEstimateRequest::class.java)
                estimateApi.createEstimate(request)
            }
            "update" -> {
                val request = gson.fromJson(entry.payload, UpdateEstimateRequest::class.java)
                estimateApi.updateEstimate(entry.entityId, request)
            }
            "delete" -> estimateApi.deleteEstimate(entry.entityId)
            else -> Log.w(TAG, "Unknown operation '${entry.operation}' for estimate #${entry.entityId}")
        }
    }

    private suspend fun dispatchExpenseEntry(entry: SyncQueueEntity) {
        when (entry.operation) {
            "create" -> {
                val request = gson.fromJson(entry.payload, CreateExpenseRequest::class.java)
                expenseApi.createExpense(request)
            }
            "update" -> {
                val request = gson.fromJson(entry.payload, UpdateExpenseRequest::class.java)
                expenseApi.updateExpense(entry.entityId, request)
            }
            "delete" -> expenseApi.deleteExpense(entry.entityId)
            else -> Log.w(TAG, "Unknown operation '${entry.operation}' for expense #${entry.entityId}")
        }
    }

    private suspend fun dispatchEmployeeEntry(entry: SyncQueueEntity) {
        when (entry.operation) {
            "clock_in" -> settingsApi.clockIn(entry.entityId)
            "clock_out" -> settingsApi.clockOut(entry.entityId)
            else -> Log.w(TAG, "Unknown operation '${entry.operation}' for employee #${entry.entityId}")
        }
    }

    @Suppress("UNCHECKED_CAST")
    private suspend fun dispatchCheckoutEntry(entry: SyncQueueEntity) {
        when (entry.operation) {
            "convert_and_pay" -> {
                val payload = gson.fromJson(entry.payload, Map::class.java) as Map<String, Any>
                val ticketId = (payload["ticketId"] as Number).toLong()
                val method = payload["paymentMethod"] as? String ?: "cash"
                val amount = (payload["amount"] as Number).toDouble()

                // Step 1: Convert ticket to invoice
                val invoiceResponse = ticketApi.convertToInvoice(ticketId)
                val invoiceId = invoiceResponse.data?.id
                    ?: throw Exception("Failed to convert ticket to invoice")

                // Step 2: Record payment
                invoiceApi.recordPayment(
                    invoiceId,
                    RecordPaymentRequest(amount = amount, method = method)
                )
            }
            else -> Log.w(TAG, "Unknown operation '${entry.operation}' for checkout #${entry.entityId}")
        }
    }

    @Suppress("UNCHECKED_CAST")
    private suspend fun dispatchTicketNoteEntry(entry: SyncQueueEntity) {
        when (entry.operation) {
            "add" -> {
                val payload = gson.fromJson(entry.payload, Map::class.java) as Map<String, Any>
                ticketApi.addNote(entry.entityId, payload)
            }
            else -> Log.w(TAG, "Unknown operation '${entry.operation}' for ticket_note #${entry.entityId}")
        }
    }

    /**
     * Replays queued ticket_device edits (field updates, added parts, removed parts) to the
     * server. Queue entries are produced by the TicketDeviceEditScreen when offline.
     */
    private suspend fun dispatchTicketDeviceEntry(entry: SyncQueueEntity) {
        when (entry.operation) {
            "update" -> {
                val request = gson.fromJson(entry.payload, UpdateTicketDeviceRequest::class.java)
                ticketApi.updateDevice(entry.entityId, request)
            }
            "add_part" -> {
                val request = gson.fromJson(entry.payload, AddTicketPartRequest::class.java)
                ticketApi.addPartToDevice(entry.entityId, request)
            }
            "remove_part" -> {
                // entry.entityId is the partId here — the editor stored it that way so the
                // delete-by-id endpoint can be called without extra payload parsing.
                ticketApi.removePartFromDevice(entry.entityId)
            }
            else -> Log.w(TAG, "Unknown operation '${entry.operation}' for ticket_device #${entry.entityId}")
        }
    }

    @Suppress("UNCHECKED_CAST")
    private suspend fun dispatchSmsEntry(entry: SyncQueueEntity) {
        when (entry.operation) {
            "send" -> {
                val payload = gson.fromJson(entry.payload, Map::class.java) as Map<String, Any>
                smsApi.sendSms(payload)
                // Update local message status from "queued" to "sent"
                if (entry.entityId < 0) {
                    smsDao.updateStatus(entry.entityId, "sent")
                }
            }
            else -> Log.w(TAG, "Unknown operation '${entry.operation}' for sms #${entry.entityId}")
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
