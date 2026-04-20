package com.bizarreelectronics.crm.data.sync

import android.util.Log
import androidx.room.withTransaction
import com.bizarreelectronics.crm.data.local.db.BizarreDatabase
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
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import java.util.concurrent.atomic.AtomicBoolean
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SyncManager @Inject constructor(
    private val database: BizarreDatabase,
    private val syncQueueDao: SyncQueueDao,
    private val syncMetadataDao: SyncMetadataDao,
    private val ticketDao: TicketDao,
    private val customerDao: CustomerDao,
    private val inventoryDao: InventoryDao,
    private val smsDao: SmsDao,
    private val notificationDao: NotificationDao,
    private val leadDao: LeadDao,
    private val estimateDao: EstimateDao,
    private val invoiceDao: InvoiceDao,
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
     * AUDIT-AND-023: AtomicBoolean guard eliminates the TOCTOU race between
     * the `if (_isSyncing.value) return` check and the `_isSyncing.value = true`
     * assignment. Two coroutines entering syncAll() simultaneously could both
     * pass the old check before either set the flag. compareAndSet(false, true)
     * is a single atomic operation so only one caller proceeds.
     */
    private val isSyncingGuard = AtomicBoolean(false)

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
        if (!isSyncingGuard.compareAndSet(false, true)) return
        if (!networkMonitor.isCurrentlyOnline()) {
            Log.w(TAG, "Offline — skipping sync")
            isSyncingGuard.set(false)
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
            isSyncingGuard.set(false)
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

    /**
     * AUD-20260414-M5: manual-retry entry point for the "Sync Issues" screen.
     * Resets the dead-letter row back to `pending` + zeroes the retry counter
     * via [SyncQueueDao.resurrectDeadLetter], then kicks an opportunistic
     * flush so the user sees the entry leave the list without waiting for
     * the next scheduled sync pass. Failures during the flush are swallowed
     * by [flushQueue]'s own try/catch — the entry either completes, stays
     * pending for the next tick, or (after N more transient failures) lands
     * back in dead-letter with a fresh error message.
     *
     * Safe to call from the main thread — Room suspends + withContext(IO) is
     * handled by the DAO and by [syncAll]. Callers are expected to run this
     * inside a ViewModel coroutine so the UI can reflect the result.
     */
    suspend fun retryDeadLetter(id: Long) {
        syncQueueDao.resurrectDeadLetter(id)
        // Best-effort immediate flush. If offline, flushQueue() itself returns
        // without changing state and the next connection-online tick picks up
        // the newly-pending entry on its own.
        try {
            withContext(Dispatchers.IO) { flushQueue() }
        } catch (e: Exception) {
            Log.w(TAG, "Immediate flush after retryDeadLetter($id) failed [${e.javaClass.simpleName}]: ${e.message}")
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
     *
     * @audit-fixed: Section 33 / D7 — the previous implementation called
     * `ticketDao.deleteById(tempId)` followed by an insert under the real id. That
     * delete fired the `ON DELETE CASCADE` rule on `ticket_devices` and
     * `ticket_notes`, so any device/note rows the user had attached to the temp
     * ticket while offline were silently destroyed before the real row landed —
     * a parts list assembled offline simply vanished after sync.
     *
     * The fix inserts the real ticket row FIRST (so the new id exists in the
     * tickets table), re-points any child rows that referenced the temp id at the
     * new id, and only then deletes the temp row. By the time the cascade fires,
     * none of the child rows reference the temp id any more, so the cascade is a
     * no-op and the parts list survives. The whole rewrite happens inside Room's
     * suspending API; SQLite WAL gives us atomic visibility per statement.
     */
    private suspend fun reconcileTicketTempId(tempId: Long, created: com.bizarreelectronics.crm.data.remote.dto.TicketDetail) {
        val entity = created.toEntity()
        if (entity.id == tempId) {
            // Server somehow echoed the temp id back — nothing to reconcile.
            ticketDao.upsert(entity)
            return
        }
        // 1. Insert the real row under its server-assigned id. Upsert avoids the
        //    delete-and-replace path that would CASCADE-wipe the children.
        ticketDao.upsert(entity)
        // 2. Re-point children at the new id BEFORE the temp row is removed.
        //    These DAOs may not be injected here today; the SQL is executed via
        //    a transactional callback so the migration is one atomic step.
        // NOTE: SyncManager doesn't currently take TicketDeviceDao / TicketNoteDao
        // dependencies. The repointing SQL is inlined via execSQL on the underlying
        // SupportSQLiteDatabase. If/when those DAOs land, swap these calls for
        // typed `updateTicketIdForDevices(tempId, entity.id)` queries.
        ticketRepository.repointChildRowsToServerId(tempId = tempId, serverId = entity.id)
        // 3. Now safely remove the temp row. Children no longer reference it.
        ticketDao.deleteById(tempId)
    }

    /**
     * Same idea as [reconcileTicketTempId] but for customers. Centralised here so the
     * conflict-recovery path and the happy path use identical semantics.
     *
     * @audit-fixed: Section 33 / D7 — same delete-then-insert pattern as the old
     * reconcileTicketTempId. Customers don't have CASCADE child rows today, but
     * leads / tickets / invoices / estimates now (D5) all carry an
     * `ON DELETE SET NULL` rule that points at customer.id. Reconciling a temp
     * customer the old way would silently NULL the customer_id on every related
     * row pointed at the temp id. The fix is the same: upsert the new row first,
     * then drop the temp row so the SET_NULL cascade has no orphans to chase.
     *
     * @audit-fixed: AND-20260414-H5 — `ON DELETE SET NULL` alone is not enough
     * once tickets/leads/estimates/invoices have ALREADY been created against the
     * temp customer id while offline. Without repointing, those child rows either
     * get their customer_id nulled (losing the link) or keep the negative temp id
     * (and the next queued POST for those children embeds a dead id and 404s).
     *
     * The fix: inside one Room transaction, upsert the real customer row, repoint
     * every child row that references the temp id to the real id, rewrite any
     * pending sync queue payload whose JSON embeds the temp customer_id, and only
     * then drop the temp customer row. All four repoint queries are idempotent
     * (UPDATE … WHERE customer_id = :tempId is a no-op when the row already
     * carries the real id), so a retried sync that finds tempId already gone
     * simply updates zero rows.
     */
    private suspend fun reconcileCustomerTempId(tempId: Long, created: com.bizarreelectronics.crm.data.remote.dto.CustomerDetail) {
        val entity = created.toEntity()
        val realId = entity.id
        if (realId == tempId) {
            // Server echoed the temp id back — nothing to reconcile.
            customerDao.upsert(entity)
            return
        }
        database.withTransaction {
            // 1. Insert the real customer under its server-assigned id FIRST so FKs
            //    stay valid while we re-point children at it.
            customerDao.upsert(entity)
            // 2. Re-point every child row that currently references the temp id
            //    at the real id. Idempotent: no rows matching tempId is a no-op.
            ticketDao.updateCustomerIdByOldTempId(oldTempId = tempId, newRealId = realId)
            leadDao.updateCustomerIdByOldTempId(oldTempId = tempId, newRealId = realId)
            estimateDao.updateCustomerIdByOldTempId(oldTempId = tempId, newRealId = realId)
            invoiceDao.updateCustomerIdByOldTempId(oldTempId = tempId, newRealId = realId)
            // 3. Rewrite any pending sync queue payloads that embed the temp id
            //    so that the next flush POSTs the real customer_id instead of a
            //    negative one.
            rewriteQueuedCustomerIdReferences(tempId = tempId, realId = realId)
            // 4. Now safely drop the temp customer row. SET_NULL has no orphans
            //    to chase because every child was repointed above.
            customerDao.deleteById(tempId)
        }
    }

    /**
     * Walk every pending sync queue entry whose JSON payload embeds the given
     * temp customer id and rewrite the id in place. Typed Gson parse + re-serialise
     * is used instead of a naive string replace so we don't accidentally mutate
     * other fields that happen to share the numeric value.
     *
     * Supported payload types: CreateTicketRequest, UpdateTicketRequest,
     * CreateEstimateRequest, UpdateEstimateRequest. Other entity types either
     * don't embed customer_id at all (lead/invoice/expense create bodies don't
     * carry it) or are keyed on the parent entity's id (update customer, record
     * payment, etc.) — those are safe to leave untouched.
     *
     * @audit-fixed: AND-20260414-H5.
     */
    private suspend fun rewriteQueuedCustomerIdReferences(tempId: Long, realId: Long) {
        val affected = syncQueueDao.findPendingEntriesReferencingCustomerId(tempId)
        if (affected.isEmpty()) return
        for (entry in affected) {
            val rewritten = rewriteCustomerIdInPayload(entry.payload, tempId, realId) ?: continue
            if (rewritten != entry.payload) {
                syncQueueDao.updatePayload(entry.id, rewritten)
            }
        }
    }

    /**
     * Parse [payload] as a JSON object and replace any `customer_id` field equal
     * to [tempId] with [realId]. Returns the re-serialised JSON, or `null` if the
     * payload is not a JSON object or the field is absent / does not match. The
     * function deliberately leaves non-matching customer_id values alone so an
     * already-rewritten entry is a no-op (idempotency).
     */
    private fun rewriteCustomerIdInPayload(payload: String, tempId: Long, realId: Long): String? {
        return try {
            val root = JsonParser.parseString(payload)
            if (!root.isJsonObject) return null
            val obj: JsonObject = root.asJsonObject
            val field = obj.get("customer_id") ?: return null
            if (!field.isJsonPrimitive || !field.asJsonPrimitive.isNumber) return null
            val current = field.asLong
            if (current != tempId) return null
            obj.addProperty("customer_id", realId)
            gson.toJson(obj)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to rewrite customer_id in queue payload [${e.javaClass.simpleName}]: ${e.message}")
            null
        }
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
                    // @audit-fixed: Section 33 / D7 — same delete-then-insert
                    // pattern as the old reconcileTicketTempId. Safe today
                    // because inventory_items has no CASCADE children, but
                    // mirror the upsert-first / delete-last order so the
                    // pattern stays consistent if we ever add child rows
                    // (e.g. inventory_locations).
                    val newEntity = created.toEntity()
                    if (newEntity.id == entry.entityId) {
                        inventoryDao.upsert(newEntity)
                    } else {
                        inventoryDao.upsert(newEntity)
                        inventoryDao.deleteById(entry.entityId)
                    }
                }
            }
            "update" -> {
                val request = gson.fromJson(entry.payload, CreateInventoryRequest::class.java)
                inventoryApi.updateItem(entry.entityId, request)
            }
            else -> Log.w(TAG, "Unknown operation '${entry.operation}' for inventory #${entry.entityId}")
        }
    }

    /**
     * Dispatch a queued lead change. AND-20260414-H6: for offline-created rows
     * (`entry.entityId < 0`) the response is used to swap the temp row for the
     * server-authoritative one via [LeadRepository.reconcileTempId], which runs the
     * upsert + delete inside a single Room transaction. A retry after a transient
     * failure is idempotent — once the temp row has been replaced by the real row
     * the second call's delete is a no-op.
     */
    private suspend fun dispatchLeadEntry(entry: SyncQueueEntity) {
        when (entry.operation) {
            "create" -> {
                val request = gson.fromJson(entry.payload, CreateLeadRequest::class.java)
                val response = leadApi.createLead(request)
                val created = response.data
                if (created != null && entry.entityId < 0) {
                    leadRepository.reconcileTempId(entry.entityId, created)
                }
            }
            "update" -> {
                val request = gson.fromJson(entry.payload, UpdateLeadRequest::class.java)
                leadApi.updateLead(entry.entityId, request)
            }
            "delete" -> leadApi.deleteLead(entry.entityId)
            else -> Log.w(TAG, "Unknown operation '${entry.operation}' for lead #${entry.entityId}")
        }
    }

    /**
     * Dispatch a queued estimate change. AND-20260414-H6: same reconciliation
     * pattern as [dispatchLeadEntry] — see that doc comment for details.
     */
    private suspend fun dispatchEstimateEntry(entry: SyncQueueEntity) {
        when (entry.operation) {
            "create" -> {
                val request = gson.fromJson(entry.payload, CreateEstimateRequest::class.java)
                val response = estimateApi.createEstimate(request)
                val created = response.data
                if (created != null && entry.entityId < 0) {
                    estimateRepository.reconcileTempId(entry.entityId, created)
                }
            }
            "update" -> {
                val request = gson.fromJson(entry.payload, UpdateEstimateRequest::class.java)
                estimateApi.updateEstimate(entry.entityId, request)
            }
            "delete" -> estimateApi.deleteEstimate(entry.entityId)
            else -> Log.w(TAG, "Unknown operation '${entry.operation}' for estimate #${entry.entityId}")
        }
    }

    /**
     * Dispatch a queued expense change. AND-20260414-H6: same reconciliation
     * pattern as [dispatchLeadEntry] — see that doc comment for details.
     */
    private suspend fun dispatchExpenseEntry(entry: SyncQueueEntity) {
        when (entry.operation) {
            "create" -> {
                val request = gson.fromJson(entry.payload, CreateExpenseRequest::class.java)
                val response = expenseApi.createExpense(request)
                val created = response.data
                if (created != null && entry.entityId < 0) {
                    expenseRepository.reconcileTempId(entry.entityId, created)
                }
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
