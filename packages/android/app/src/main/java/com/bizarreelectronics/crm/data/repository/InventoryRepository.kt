package com.bizarreelectronics.crm.data.repository

import android.util.Log
import com.bizarreelectronics.crm.data.local.db.dao.InventoryDao
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.local.db.entities.InventoryItemEntity
import com.bizarreelectronics.crm.data.local.db.entities.SyncQueueEntity
import com.bizarreelectronics.crm.data.remote.api.InventoryApi
import com.bizarreelectronics.crm.data.remote.dto.AdjustStockRequest
import com.bizarreelectronics.crm.data.remote.dto.CreateInventoryRequest
import com.bizarreelectronics.crm.data.remote.dto.InventoryDetail
import com.bizarreelectronics.crm.data.remote.dto.InventoryListItem
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import com.google.gson.Gson
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class InventoryRepository @Inject constructor(
    private val inventoryDao: InventoryDao,
    private val inventoryApi: InventoryApi,
    private val syncQueueDao: SyncQueueDao,
    private val serverMonitor: ServerReachabilityMonitor,
    private val gson: Gson,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    fun getItems(): Flow<List<InventoryItemEntity>> {
        refreshItemsInBackground()
        return inventoryDao.getAll()
    }

    fun getItem(id: Long): Flow<InventoryItemEntity?> {
        refreshItemDetailInBackground(id)
        return inventoryDao.getById(id)
    }

    fun getBySku(sku: String): Flow<InventoryItemEntity?> = inventoryDao.getBySku(sku)

    fun getLowStock(): Flow<List<InventoryItemEntity>> = inventoryDao.getLowStock()

    fun searchItems(query: String): Flow<List<InventoryItemEntity>> {
        scope.launch {
            if (!serverMonitor.isEffectivelyOnline.value) return@launch
            try {
                val response = inventoryApi.getItems(mapOf("search" to query, "pagesize" to "50"))
                val items = response.data?.items ?: return@launch
                inventoryDao.insertAll(items.map { it.toEntity() })
            } catch (e: Exception) {
                Log.d(TAG, "API inventory search failed: ${e.message}")
            }
        }
        return inventoryDao.search(query)
    }

    /** Adjust stock. Online: API call. Offline: local adjust + sync queue. */
    suspend fun adjustStock(id: Long, request: AdjustStockRequest) {
        if (serverMonitor.isEffectivelyOnline.value) {
            try {
                inventoryApi.adjustStock(id, request)
                // Refresh the item from server to get updated stock
                refreshItemDetailInBackground(id)
                return
            } catch (e: Exception) {
                Log.w(TAG, "Online adjustStock failed, falling back to offline queue: ${e.message}")
            }
        }

        // Offline: adjust locally and queue
        inventoryDao.adjustStock(id, request.quantity)
        syncQueueDao.insert(
            SyncQueueEntity(
                entityType = "inventory",
                entityId = id,
                operation = "adjust_stock",
                payload = gson.toJson(request),
            )
        )
    }

    /** Create an inventory item. Online: API call. Offline: local insert + sync queue. */
    suspend fun createItem(request: CreateInventoryRequest): Long {
        if (serverMonitor.isEffectivelyOnline.value) {
            try {
                val response = inventoryApi.createItem(request)
                val detail = response.data?.item
                    ?: throw Exception(response.message ?: "Create failed")
                val entity = detail.toEntity()
                inventoryDao.insert(entity)
                return entity.id
            } catch (e: Exception) {
                Log.w(TAG, "Online create failed, falling back to offline queue: ${e.message}")
            }
        }

        val tempId = -System.currentTimeMillis()
        val now = java.time.Instant.now().toString().take(19).replace("T", " ")
        val entity = InventoryItemEntity(
            id = tempId,
            name = request.name,
            sku = request.sku,
            upcCode = request.upcCode,
            itemType = request.itemType,
            category = null,
            manufacturerId = request.manufacturerId,
            manufacturerName = null,
            costPrice = request.costPrice ?: 0.0,
            retailPrice = request.price ?: 0.0,
            inStock = request.inStock ?: 0,
            reorderLevel = request.reorderLevel ?: 0,
            taxClassId = request.taxClassId,
            supplierId = request.supplierId,
            supplierName = null,
            location = null,
            shelf = null,
            bin = null,
            description = request.description,
            isSerialize = (request.isSerialized ?: 0) == 1,
            createdAt = now,
            updatedAt = now,
            locallyModified = true,
        )
        inventoryDao.insert(entity)

        syncQueueDao.insert(
            SyncQueueEntity(
                entityType = "inventory",
                entityId = tempId,
                operation = "create",
                payload = gson.toJson(request),
            )
        )
        return tempId
    }

    /** Update an inventory item. Online: API call. Offline: local update + sync queue. */
    suspend fun updateItem(id: Long, request: CreateInventoryRequest): InventoryItemEntity? {
        if (serverMonitor.isEffectivelyOnline.value) {
            try {
                val response = inventoryApi.updateItem(id, request)
                val detail = response.data?.item
                    ?: throw Exception(response.message ?: "Update failed")
                val entity = detail.toEntity()
                inventoryDao.insert(entity)
                return entity
            } catch (e: Exception) {
                Log.w(TAG, "Online update failed, falling back to offline queue: ${e.message}")
            }
        }

        syncQueueDao.insert(
            SyncQueueEntity(
                entityType = "inventory",
                entityId = id,
                operation = "update",
                payload = gson.toJson(request),
            )
        )
        return null
    }

    suspend fun lookupBarcode(code: String): InventoryItemEntity? {
        if (serverMonitor.isEffectivelyOnline.value) {
            try {
                val response = inventoryApi.lookupBarcode(code)
                val item = response.data?.item ?: return null
                val entity = item.toEntity()
                inventoryDao.insert(entity)
                return entity
            } catch (e: Exception) {
                Log.d(TAG, "Barcode API lookup failed: ${e.message}")
            }
        }
        // Fallback: try local UPC match
        return null // getBySku returns Flow, barcode lookup is a one-shot
    }

    /** Full pull from server — used by SyncManager. */
    suspend fun refreshFromServer() {
        if (!serverMonitor.isEffectivelyOnline.value) return
        try {
            var page = 1
            while (true) {
                val response = inventoryApi.getItems(mapOf("pagesize" to "200", "page" to page.toString()))
                val items = response.data?.items ?: break
                if (items.isEmpty()) break
                inventoryDao.insertAll(items.map { it.toEntity() })
                val pagination = response.data?.pagination
                if (pagination == null || page >= pagination.totalPages) break
                page++
            }
        } catch (e: Exception) {
            Log.e(TAG, "refreshFromServer failed: ${e.message}")
        }
    }

    private fun refreshItemsInBackground() {
        scope.launch {
            if (!serverMonitor.isEffectivelyOnline.value) return@launch
            try {
                val response = inventoryApi.getItems(mapOf("pagesize" to "200"))
                val items = response.data?.items ?: return@launch
                inventoryDao.insertAll(items.map { it.toEntity() })
            } catch (e: Exception) {
                Log.d(TAG, "Background inventory refresh failed: ${e.message}")
            }
        }
    }

    private fun refreshItemDetailInBackground(id: Long) {
        scope.launch {
            if (!serverMonitor.isEffectivelyOnline.value) return@launch
            try {
                val response = inventoryApi.getItem(id)
                val detail = response.data?.item ?: return@launch
                inventoryDao.insert(detail.toEntity())
            } catch (e: Exception) {
                Log.d(TAG, "Background inventory detail refresh failed: ${e.message}")
            }
        }
    }

    companion object {
        private const val TAG = "InventoryRepository"
    }
}

fun InventoryListItem.toEntity() = InventoryItemEntity(
    id = id,
    name = name ?: "",
    sku = sku,
    upcCode = upcCode,
    itemType = itemType,
    category = null,
    manufacturerId = null,
    manufacturerName = manufacturerName,
    costPrice = costPrice ?: 0.0,
    retailPrice = price ?: 0.0,
    inStock = inStock ?: 0,
    reorderLevel = reorderLevel ?: 0,
    taxClassId = null,
    supplierId = null,
    supplierName = supplierName,
    location = null,
    shelf = null,
    bin = null,
    description = null,
    isSerialize = isSerialized == 1,
    createdAt = createdAt ?: "",
    updatedAt = "",
)

fun InventoryDetail.toEntity() = InventoryItemEntity(
    id = id,
    name = name ?: "",
    sku = sku,
    upcCode = upcCode,
    itemType = itemType,
    category = null,
    manufacturerId = manufacturerId,
    manufacturerName = manufacturerName,
    costPrice = costPrice ?: 0.0,
    retailPrice = price ?: 0.0,
    inStock = inStock ?: 0,
    reorderLevel = reorderLevel ?: 0,
    taxClassId = taxClassId,
    supplierId = supplierId,
    supplierName = supplierName,
    location = null,
    shelf = null,
    bin = null,
    description = description,
    isSerialize = isSerialized == 1,
    createdAt = createdAt ?: "",
    updatedAt = updatedAt ?: "",
)
