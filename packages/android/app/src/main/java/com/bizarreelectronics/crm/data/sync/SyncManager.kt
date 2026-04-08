package com.bizarreelectronics.crm.data.sync

import android.util.Log
import com.bizarreelectronics.crm.data.local.db.dao.*
import com.bizarreelectronics.crm.data.local.db.entities.*
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.remote.api.CustomerApi
import com.bizarreelectronics.crm.data.remote.api.InventoryApi
import com.bizarreelectronics.crm.data.remote.api.TicketApi
import com.bizarreelectronics.crm.data.remote.api.InvoiceApi
import com.bizarreelectronics.crm.data.remote.api.NotificationApi
import com.bizarreelectronics.crm.data.remote.dto.AdjustStockRequest
import com.bizarreelectronics.crm.data.remote.dto.CreateCustomerRequest
import com.bizarreelectronics.crm.data.remote.dto.UpdateCustomerRequest
import com.bizarreelectronics.crm.data.remote.dto.UpdateTicketRequest
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
    private val notificationApi: NotificationApi,
    private val networkMonitor: NetworkMonitor,
    private val appPreferences: AppPreferences,
    private val gson: Gson,
) {
    private val _isSyncing = MutableStateFlow(false)
    val isSyncing = _isSyncing.asStateFlow()

    /** Full sync — pull latest data from server into Room */
    suspend fun syncAll() {
        if (_isSyncing.value) return
        if (!networkMonitor.isCurrentlyOnline()) {
            Log.w("SyncManager", "Offline — skipping sync")
            return
        }

        _isSyncing.value = true
        try {
            withContext(Dispatchers.IO) {
                // 1. Flush pending local changes
                flushQueue()

                // 2. Pull tickets
                syncTickets()

                // 3. Pull customers
                syncCustomers()

                // 4. Pull notifications
                syncNotifications()

                // Update last sync time
                appPreferences.lastFullSyncAt = java.time.Instant.now().toString().take(19).replace("T", " ")
            }
            Log.d("SyncManager", "Sync completed")
        } catch (e: Exception) {
            Log.e("SyncManager", "Sync failed: ${e.message}")
        } finally {
            _isSyncing.value = false
        }
    }

    private suspend fun syncTickets() {
        try {
            val response = ticketApi.getTickets(mapOf("pagesize" to "200"))
            val ticketList = response.data?.tickets ?: return

            val entities = ticketList.map { t ->
                TicketEntity(
                    id = t.id,
                    orderId = t.orderId,
                    customerId = t.customerId,
                    statusId = t.status?.id,
                    statusName = t.statusName,
                    statusColor = t.statusColor,
                    statusIsClosed = t.status?.isClosed == 1,
                    assignedTo = t.assignedUser?.id,
                    total = t.total ?: 0.0,
                    createdAt = t.createdAt ?: "",
                    updatedAt = t.updatedAt ?: "",
                )
            }
            ticketDao.insertAll(entities)
            Log.d("SyncManager", "Synced ${entities.size} tickets")
        } catch (e: Exception) {
            Log.e("SyncManager", "Ticket sync failed: ${e.message}")
        }
    }

    private suspend fun syncCustomers() {
        try {
            val response = customerApi.getCustomers(mapOf("pagesize" to "500"))
            val customerList = response.data?.customers ?: return

            val entities = customerList.map { c ->
                CustomerEntity(
                    id = c.id,
                    firstName = c.firstName,
                    lastName = c.lastName,
                    email = c.email,
                    phone = c.phone,
                    mobile = c.mobile,
                    organization = c.organization,
                    createdAt = c.createdAt ?: "",
                    updatedAt = c.createdAt ?: "", // CustomerListItem doesn't have updatedAt
                )
            }
            customerDao.insertAll(entities)
            Log.d("SyncManager", "Synced ${entities.size} customers")
        } catch (e: Exception) {
            Log.e("SyncManager", "Customer sync failed: ${e.message}")
        }
    }

    private suspend fun syncNotifications() {
        try {
            val response = notificationApi.getNotifications(1)
            // The response is a generic map — parse carefully
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
            Log.d("SyncManager", "Synced ${entities.size} notifications")
        } catch (e: Exception) {
            Log.e("SyncManager", "Notification sync failed: ${e.message}")
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
            "customer" -> {
                when (entry.operation) {
                    "create" -> {
                        val request = gson.fromJson(entry.payload, CreateCustomerRequest::class.java)
                        customerApi.createCustomer(request)
                    }
                    "update" -> {
                        val request = gson.fromJson(entry.payload, UpdateCustomerRequest::class.java)
                        customerApi.updateCustomer(entry.entityId, request)
                    }
                    else -> Log.w(TAG, "Unknown operation '${entry.operation}' for customer #${entry.entityId}")
                }
            }
            "ticket" -> {
                when (entry.operation) {
                    "update" -> {
                        val request = gson.fromJson(entry.payload, UpdateTicketRequest::class.java)
                        ticketApi.updateTicket(entry.entityId, request)
                    }
                    else -> Log.w(TAG, "Unknown operation '${entry.operation}' for ticket #${entry.entityId}")
                }
            }
            "inventory" -> {
                when (entry.operation) {
                    "adjust_stock" -> {
                        val request = gson.fromJson(entry.payload, AdjustStockRequest::class.java)
                        inventoryApi.adjustStock(entry.entityId, request)
                    }
                    else -> Log.w(TAG, "Unknown operation '${entry.operation}' for inventory #${entry.entityId}")
                }
            }
            else -> Log.w(TAG, "Unknown entityType '${entry.entityType}' in sync queue (id=${entry.id})")
        }
    }

    companion object {
        private const val TAG = "SyncManager"
    }
}
