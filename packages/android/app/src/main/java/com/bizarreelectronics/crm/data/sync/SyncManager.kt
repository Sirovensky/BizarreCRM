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

    /**
     * Full sync — flush pending, then pull latest data from server into Room.
     *
     * R8: each entity's refresh runs inside its own isolated try/catch so that a crash
     * or network failure in one entity type (e.g. a 500 from `/tickets`) does not roll
     * back progress made by the others. Partial progress is the intended outcome — an
     * entity-level failure leaves that entity stale while the rest of the cache still
     * advances. Dead-letter queue is also opportunistically purged on every full sync.
     */
    suspend fun syncAll() {
        if (_isSyncing.value) return
        if (!networkMonitor.isCurrentlyOnline()) {
            Log.w(TAG, "Offline — skipping sync")
            return
        }

        _isSyncing.value = true
        try {
            withContext(Dispatchers.IO) {
                // 1. Flush pending local changes. Per-entry isolation is handled by
                //    flushQueue() itself, so a single bad entry cannot abort the loop.
                runIsolated("flushQueue") { flushQueue() }

                // 2. Pull each entity type under its own isolation boundary. A failure
                //    here marks that entity as stale but allows the others to advance.
                runIsolated("ticket refresh")    { ticketRepository.refreshFromServer() }
                runIsolated("customer refresh")  { customerRepository.refreshFromServer() }
                runIsolated("inventory refresh") { inventoryRepository.refreshFromServer() }
                runIsolated("invoice refresh")   { invoiceRepository.refreshFromServer() }
                runIsolated("lead refresh")      { leadRepository.refreshFromServer() }
                runIsolated("estimate refresh")  { estimateRepository.refreshFromServer() }
                runIsolated("expense refresh")   { expenseRepository.refreshFromServer() }
                runIsolated("sms refresh")       { smsRepository.refreshFromServer() }
                runIsolated("notifications")     { syncNotifications() }

                // 3. Retention: purge dead-letter entries older than the configured
                //    retention window so the queue table doesn't grow unbounded.
                runIsolated("dead letter purge") { purgeOldDeadLetters() }

                // Update last sync time — done even on partial failure so the user sees
                // "last synced N minutes ago" rather than a stale value from hours ago.
                appPreferences.lastFullSyncAt = java.time.Instant.now().toString().take(19).replace("T", " ")
            }
            Log.d(TAG, "Sync completed")
        } catch (e: Exception) {
            Log.e(TAG, "Sync failed [${e.javaClass.simpleName}]: ${e.message}")
        } finally {
            _isSyncing.value = false
        }
    }

    /**
     * Runs [block] under a local try/catch so an exception in one sync step does not
     * abort the others (R8). The step name is logged on failure for diagnostics.
     */
    private suspend inline fun runIsolated(stepName: String, crossinline block: suspend () -> Unit) {
        try {
            block()
        } catch (e: Exception) {
            Log.e(TAG, "Sync step '$stepName' failed [${e.javaClass.simpleName}]: ${e.message}")
        }
    }

    /**
     * Deletes dead-letter sync queue rows older than
     * [SyncQueueDao.DEAD_LETTER_RETENTION_DAYS] days. Protects the sync_queue table
     * from unbounded growth while still keeping recent failures around long enough for
     * a user or admin to inspect them.
     */
    private suspend fun purgeOldDeadLetters() {
        val retentionMs = SyncQueueDao.DEAD_LETTER_RETENTION_DAYS.toLong() * 24L * 60L * 60L * 1000L
        val cutoff = System.currentTimeMillis() - retentionMs
        syncQueueDao.purgeOldDeadLetters(cutoff)
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
            Log.e(TAG, "Notification sync failed [${e.javaClass.simpleName}]: ${e.message}")
        }
    }

    /**
     * Flush queued local changes to the server.
     *
     * N8/R9: failed entries are moved to the `dead_letter` status instead of being
     * deleted. They are retained for 30 days so the user can inspect/retry them from a
     * diagnostic screen (UI TODO owned by a separate agent). Completed entries are
     * still swept at the end of the pass to keep the table lean.
     */
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
                // NB: entry.retries is the snapshot BEFORE incrementRetry was called, so
                // the comparison uses retries + 1 to reflect the new count. When the
                // count reaches MAX_RETRIES we route the entry to the dead letter queue
                // instead of deleting it (N8).
                val effectiveRetries = entry.retries + 1
                if (effectiveRetries >= SyncQueueDao.MAX_RETRIES) {
                    Log.w(
                        TAG,
                        "Dead-lettering sync entry ${entry.id} (${entry.entityType}/${entry.operation}) " +
                            "after $effectiveRetries retries [${e.javaClass.simpleName}]: ${e.message}",
                    )
                    syncQueueDao.markDeadLetter(entry.id, e.message)
                } else {
                    syncQueueDao.updateStatus(entry.id, "pending", e.message)
                }
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
                // Ensure the request carries a stable idempotency key so a retried
                // POST after a transient network error does not produce a duplicate
                // row on the server. The original repository call should already have
                // seeded the key, but we guard against legacy rows that were queued
                // before AP5 landed. (AP5)
                val rawRequest = gson.fromJson(entry.payload, CreateCustomerRequest::class.java)
                val request = if (rawRequest.clientRequestId.isNullOrBlank()) {
                    val keyed = rawRequest.copy(clientRequestId = java.util.UUID.randomUUID().toString())
                    syncQueueDao.updatePayload(entry.id, gson.toJson(keyed))
                    keyed
                } else {
                    rawRequest
                }
                try {
                    val response = customerApi.createCustomer(request)
                    val created = response.data
                    if (created != null && entry.entityId < 0) {
                        reconcileCustomerTempId(entry.entityId, created)
                    }
                } catch (e: retrofit2.HttpException) {
                    // R5: a 409 Conflict means the server already has the row (likely
                    // because the previous attempt's response was dropped on the way
                    // back to us). Treat it as success and reconcile the temp id to
                    // whatever the server now owns, rather than failing the entry.
                    if (e.code() == HTTP_CONFLICT && entry.entityId < 0) {
                        reconcileCustomerByClientRequestId(entry.entityId, request.clientRequestId)
                    } else {
                        throw e
                    }
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
                try {
                    val response = ticketApi.createTicket(request)
                    val created = response.data
                    if (created != null && entry.entityId < 0) {
                        reconcileTicketTempId(entry.entityId, created)
                    }
                } catch (e: retrofit2.HttpException) {
                    // R5: server reported the row already exists. Best effort: refresh
                    // from server so the new id/orderId replaces the temp row. Without
                    // a server-side idempotency key we can't pinpoint the conflicting
                    // row, so we defer to the next paginated refresh.
                    if (e.code() == HTTP_CONFLICT && entry.entityId < 0) {
                        Log.w(TAG, "Ticket create returned 409 for temp id ${entry.entityId}; deferring reconciliation to next refresh")
                        // Leave the temp row in place; the next ticketRepository.refreshFromServer()
                        // will pull the real row and the temp row will be cleaned up below.
                        cleanupTemporaryTicketRow(entry.entityId)
                    } else {
                        throw e
                    }
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

    /**
     * Reconciles a temp ticket row with the server-assigned detail. Both the primary
     * key (`id`) AND the human-visible `orderId` are rewritten so downstream Room
     * queries, child rows, and UI references all point at the real server row.
     * See N1/N2/I1/I2.
     */
    private suspend fun reconcileTicketTempId(tempId: Long, created: com.bizarreelectronics.crm.data.remote.dto.TicketDetail) {
        val entity = created.toEntity()
        // Delete the stale temp row first so we don't leave an orphan with PENDING
        // orderId behind when the new row is inserted under its real id.
        ticketDao.deleteById(tempId)
        ticketDao.insert(entity)
    }

    /**
     * Same idea as [reconcileTicketTempId] but for customers. Centralised here so the
     * conflict-recovery path and the happy path use identical semantics.
     */
    private suspend fun reconcileCustomerTempId(tempId: Long, created: com.bizarreelectronics.crm.data.remote.dto.CustomerDetail) {
        val entity = created.toEntity()
        customerDao.deleteById(tempId)
        customerDao.insert(entity)
    }

    /**
     * Attempted best-effort reconciliation when the server returns 409 Conflict on
     * customer create. Without an explicit "fetch by client_request_id" endpoint we
     * can't directly map back to the real row, so we fall back to dropping the temp
     * row and letting the next refresh pull the canonical row. The request's client
     * id is logged for traceability. R5.
     */
    private suspend fun reconcileCustomerByClientRequestId(tempId: Long, clientRequestId: String?) {
        Log.w(TAG, "Customer create returned 409 for temp id $tempId, clientRequestId=$clientRequestId — deferring to next refresh")
        customerDao.deleteById(tempId)
    }

    /** Drop a temp ticket row after a 409 so the next full refresh can replace it. */
    private suspend fun cleanupTemporaryTicketRow(tempId: Long) {
        ticketDao.deleteById(tempId)
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
                try {
                    smsApi.sendSms(payload)
                    // N3: only mark as "sent" after the server has confirmed delivery.
                    // If the call throws, the local row stays as "queued" so the next
                    // flush can retry it and the UI does not show a false positive.
                    if (entry.entityId < 0) {
                        smsDao.updateStatus(entry.entityId, "sent")
                    }
                } catch (e: Exception) {
                    // Make sure the UI reflects that the message is still in flight —
                    // flushQueue()'s outer catch will either retry or dead-letter the
                    // entry, but the local row must NOT show "sent" regardless. We
                    // leave it as "queued" (its current state) and rethrow so the
                    // queue machinery increments retries.
                    if (entry.entityId < 0) {
                        smsDao.updateStatus(entry.entityId, "queued")
                    }
                    throw e
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

        /**
         * HTTP 409 Conflict — used by the server to signal "you already created this"
         * (idempotency collision) or "the version you sent is stale" (optimistic
         * locking failure). Either way, the client should not retry blindly; it
         * should reconcile with the server's canonical state. See R5.
         */
        private const val HTTP_CONFLICT = 409
    }
}
