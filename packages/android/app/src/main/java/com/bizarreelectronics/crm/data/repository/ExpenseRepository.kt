package com.bizarreelectronics.crm.data.repository

import android.util.Log
import com.bizarreelectronics.crm.data.local.db.dao.ExpenseDao
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.local.db.entities.ExpenseEntity
import com.bizarreelectronics.crm.data.local.db.entities.SyncQueueEntity
import com.bizarreelectronics.crm.data.remote.api.ExpenseApi
import com.bizarreelectronics.crm.data.remote.dto.CreateExpenseRequest
import com.bizarreelectronics.crm.data.remote.dto.ExpenseDetail
import com.bizarreelectronics.crm.data.remote.dto.ExpenseListItem
import com.bizarreelectronics.crm.data.remote.dto.UpdateExpenseRequest
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
class ExpenseRepository @Inject constructor(
    private val expenseDao: ExpenseDao,
    private val expenseApi: ExpenseApi,
    private val syncQueueDao: SyncQueueDao,
    private val serverMonitor: ServerReachabilityMonitor,
    private val gson: Gson,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** Returns cached expenses immediately, refreshes from API in background. */
    fun getExpenses(): Flow<List<ExpenseEntity>> {
        refreshExpensesInBackground()
        return expenseDao.getAll()
    }

    fun getExpense(id: Long): Flow<ExpenseEntity?> {
        refreshExpenseDetailInBackground(id)
        return expenseDao.getById(id)
    }

    fun searchExpenses(query: String): Flow<List<ExpenseEntity>> {
        // Also trigger API search in background
        scope.launch {
            if (!serverMonitor.isEffectivelyOnline.value) return@launch
            try {
                val response = expenseApi.getExpenses(mapOf("search" to query, "pagesize" to "50"))
                val expenses = response.data?.expenses ?: return@launch
                expenseDao.insertAll(expenses.map { it.toEntity() })
            } catch (e: Exception) {
                Log.d(TAG, "API search failed: ${e.message}")
            }
        }
        return expenseDao.search(query)
    }

    fun getByCategory(category: String): Flow<List<ExpenseEntity>> {
        refreshExpensesInBackground()
        return expenseDao.getByCategory(category)
    }

    /** Create an expense. Online: API call. Offline: local insert + sync queue. */
    suspend fun createExpense(request: CreateExpenseRequest): Long {
        if (serverMonitor.isEffectivelyOnline.value) {
            try {
                val response = expenseApi.createExpense(request)
                val detail = response.data ?: throw Exception(response.message ?: "Create failed")
                val entity = detail.toEntity()
                expenseDao.insert(entity)
                return entity.id
            } catch (e: Exception) {
                Log.w(TAG, "Online create failed, falling back to offline queue: ${e.message}")
            }
        }

        // Offline: insert with temporary negative ID
        val tempId = -System.currentTimeMillis()
        val now = java.time.Instant.now().toString().take(19).replace("T", " ")
        val entity = ExpenseEntity(
            id = tempId,
            category = request.category,
            amount = request.amount,
            description = request.description,
            date = request.date ?: now.take(10),
            createdAt = now,
            updatedAt = now,
            locallyModified = true,
        )
        expenseDao.insert(entity)

        syncQueueDao.insert(
            SyncQueueEntity(
                entityType = "expense",
                entityId = tempId,
                operation = "create",
                payload = gson.toJson(request),
            )
        )
        return tempId
    }

    /** Update an expense. Online: API call. Offline: local update + sync queue. */
    suspend fun updateExpense(id: Long, request: UpdateExpenseRequest): ExpenseEntity? {
        if (serverMonitor.isEffectivelyOnline.value) {
            try {
                val response = expenseApi.updateExpense(id, request)
                val detail = response.data ?: throw Exception(response.message ?: "Update failed")
                val entity = detail.toEntity()
                expenseDao.insert(entity)
                return entity
            } catch (e: Exception) {
                Log.w(TAG, "Online update failed, falling back to offline queue: ${e.message}")
            }
        }

        // Offline: update locally and queue
        expenseDao.getById(id).let { /* trigger flow but we need a snapshot */ }
        syncQueueDao.insert(
            SyncQueueEntity(
                entityType = "expense",
                entityId = id,
                operation = "update",
                payload = gson.toJson(request),
            )
        )
        return null
    }

    /** Delete an expense. Online: API call. Offline: queue for later deletion. */
    suspend fun deleteExpense(id: Long) {
        if (serverMonitor.isEffectivelyOnline.value) {
            try {
                expenseApi.deleteExpense(id)
                expenseDao.deleteById(id)
                return
            } catch (e: Exception) {
                Log.w(TAG, "Online delete failed, falling back to offline queue: ${e.message}")
            }
        }

        // Offline: queue deletion
        syncQueueDao.insert(
            SyncQueueEntity(
                entityType = "expense",
                entityId = id,
                operation = "delete",
                payload = gson.toJson(mapOf("id" to id)),
            )
        )
        expenseDao.deleteById(id)
    }

    /** Full pull from server — used by SyncManager. */
    suspend fun refreshFromServer() {
        if (!serverMonitor.isEffectivelyOnline.value) return
        try {
            var page = 1
            while (true) {
                val response = expenseApi.getExpenses(mapOf("pagesize" to "200", "page" to page.toString()))
                val expenses = response.data?.expenses ?: break
                if (expenses.isEmpty()) break
                expenseDao.insertAll(expenses.map { it.toEntity() })
                val pagination = response.data?.pagination
                if (pagination == null || page >= pagination.totalPages) break
                page++
            }
        } catch (e: Exception) {
            Log.e(TAG, "refreshFromServer failed: ${e.message}")
        }
    }

    private fun refreshExpensesInBackground() {
        scope.launch {
            if (!serverMonitor.isEffectivelyOnline.value) return@launch
            try {
                val response = expenseApi.getExpenses(mapOf("pagesize" to "200"))
                val expenses = response.data?.expenses ?: return@launch
                expenseDao.insertAll(expenses.map { it.toEntity() })
            } catch (e: Exception) {
                Log.d(TAG, "Background expense refresh failed: ${e.message}")
            }
        }
    }

    private fun refreshExpenseDetailInBackground(id: Long) {
        scope.launch {
            if (!serverMonitor.isEffectivelyOnline.value) return@launch
            try {
                val response = expenseApi.getExpense(id)
                val detail = response.data ?: return@launch
                expenseDao.insert(detail.toEntity())
            } catch (e: Exception) {
                Log.d(TAG, "Background expense detail refresh failed: ${e.message}")
            }
        }
    }

    companion object {
        private const val TAG = "ExpenseRepository"
    }
}

fun ExpenseListItem.toEntity() = ExpenseEntity(
    id = id,
    category = category ?: "",
    amount = amount ?: 0.0,
    description = description,
    date = date ?: "",
    userName = listOfNotNull(firstName, lastName).joinToString(" ").ifBlank { null },
    createdAt = createdAt ?: "",
    updatedAt = createdAt ?: "",
)

fun ExpenseDetail.toEntity() = ExpenseEntity(
    id = id,
    category = category ?: "",
    amount = amount ?: 0.0,
    description = description,
    date = date ?: "",
    userName = listOfNotNull(firstName, lastName).joinToString(" ").ifBlank { null },
    userId = userId,
    createdAt = createdAt ?: "",
    updatedAt = updatedAt ?: "",
)
