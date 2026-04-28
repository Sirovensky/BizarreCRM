package com.bizarreelectronics.crm.data.repository

import android.util.Log
import com.bizarreelectronics.crm.data.local.db.dao.ExpenseDao
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.local.db.entities.ExpenseEntity
import com.bizarreelectronics.crm.data.local.db.entities.SyncQueueEntity
import com.bizarreelectronics.crm.data.local.prefs.OfflineIdGenerator
import com.bizarreelectronics.crm.data.remote.api.ExpenseApi
import com.bizarreelectronics.crm.data.remote.dto.CreateExpenseRequest
import com.bizarreelectronics.crm.data.remote.dto.CreateMileageExpenseRequest
import com.bizarreelectronics.crm.data.remote.dto.CreatePerDiemExpenseRequest
import com.bizarreelectronics.crm.data.remote.dto.ExpenseDetail
import com.bizarreelectronics.crm.data.remote.dto.ExpenseListItem
import com.bizarreelectronics.crm.data.remote.dto.UpdateExpenseRequest
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import com.bizarreelectronics.crm.util.toCentsOrZero
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
    private val offlineIdGenerator: OfflineIdGenerator,
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

    /**
     * Returns expenses within [fromDate]..[toDate] (ISO date strings, inclusive).
     * Pass empty string for either bound to omit it. Triggers a background refresh.
     */
    fun getByDateRange(fromDate: String, toDate: String): Flow<List<ExpenseEntity>> {
        refreshExpensesInBackground()
        return expenseDao.getByDateRange(fromDate, toDate)
    }

    /** Returns expenses recorded by a specific employee. Triggers a background refresh. */
    fun getByEmployee(userId: Long): Flow<List<ExpenseEntity>> {
        refreshExpensesInBackground()
        return expenseDao.getByEmployee(userId)
    }

    /**
     * Returns expenses with a specific approval status (`pending` | `approved` | `denied`).
     * Triggers a background refresh so the local cache stays current.
     */
    fun getByApprovalStatus(status: String): Flow<List<ExpenseEntity>> {
        refreshExpensesInBackground()
        return expenseDao.getByStatus(status)
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

        // Offline: insert with a collision-free temporary negative ID. AND-20260414-H6:
        // switched from `-System.currentTimeMillis()` to [OfflineIdGenerator.nextTempId]
        // so two offline creates inside the same millisecond can't collide on PK.
        val tempId = offlineIdGenerator.nextTempId()
        val now = java.time.Instant.now().toString().take(19).replace("T", " ")
        val entity = ExpenseEntity(
            id = tempId,
            category = request.category,
            amount = request.amount.toCentsOrZero(),
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

    /**
     * Create a mileage expense. Online: calls POST /expenses/mileage; amount is server-computed.
     * Offline: falls back to a general-expense offline insert so the trip is not lost.
     * Returns the server-assigned id (positive) or a temp id (negative, offline path).
     */
    suspend fun createMileageExpense(request: CreateMileageExpenseRequest): Long {
        if (serverMonitor.isEffectivelyOnline.value) {
            try {
                val response = expenseApi.createMileageExpense(request)
                val detail = response.data ?: throw Exception(response.message ?: "Mileage create failed")
                val entity = detail.toEntity()
                expenseDao.insert(entity)
                return entity.id
            } catch (e: Exception) {
                Log.w(TAG, "Online mileage create failed, falling back to offline queue: ${e.message}")
            }
        }

        // Offline: queue as a 'mileage' payload so SyncManager can call the right endpoint later.
        val tempId = offlineIdGenerator.nextTempId()
        val now = java.time.Instant.now().toString().take(19).replace("T", " ")
        val computedCents = (request.miles * request.rateCents).toLong().coerceAtLeast(0L)
        val entity = ExpenseEntity(
            id = tempId,
            category = request.category,
            amount = computedCents,
            description = buildString {
                if (!request.vendor.isNullOrBlank()) append(request.vendor)
                if (!request.description.isNullOrBlank()) {
                    if (isNotEmpty()) append(" — ")
                    append(request.description)
                }
            }.ifBlank { null },
            date = request.incurredAt ?: now.take(10),
            createdAt = now,
            updatedAt = now,
            locallyModified = true,
        )
        expenseDao.insert(entity)
        syncQueueDao.insert(
            SyncQueueEntity(
                entityType = "expense_mileage",
                entityId = tempId,
                operation = "create",
                payload = gson.toJson(request),
            )
        )
        return tempId
    }

    /**
     * Create a per-diem expense. Online: calls POST /expenses/perdiem; amount is server-computed.
     * Offline: falls back to a local insert + sync queue with per-diem payload.
     * Returns the server-assigned id (positive) or a temp id (negative, offline path).
     */
    suspend fun createPerDiemExpense(request: CreatePerDiemExpenseRequest): Long {
        if (serverMonitor.isEffectivelyOnline.value) {
            try {
                val response = expenseApi.createPerDiemExpense(request)
                val detail = response.data ?: throw Exception(response.message ?: "Per-diem create failed")
                val entity = detail.toEntity()
                expenseDao.insert(entity)
                return entity.id
            } catch (e: Exception) {
                Log.w(TAG, "Online per-diem create failed, falling back to offline queue: ${e.message}")
            }
        }

        // Offline: compute amount locally so the list screen can display a useful figure.
        val tempId = offlineIdGenerator.nextTempId()
        val now = java.time.Instant.now().toString().take(19).replace("T", " ")
        val computedCents = (request.days.toLong() * request.rateCents.toLong()).coerceAtLeast(0L)
        val entity = ExpenseEntity(
            id = tempId,
            category = request.category,
            amount = computedCents,
            description = request.description,
            date = request.incurredAt ?: now.take(10),
            createdAt = now,
            updatedAt = now,
            locallyModified = true,
        )
        expenseDao.insert(entity)
        syncQueueDao.insert(
            SyncQueueEntity(
                entityType = "expense_perdiem",
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

    /**
     * Swap the temp expense row at [tempId] for the server-authoritative detail.
     * Runs the upsert + delete inside a single Room transaction via
     * [ExpenseDao.reconcileTempId]. Safe to call with an already-reconciled temp id;
     * the delete step is a no-op if the temp row is already gone (AND-20260414-H6).
     */
    suspend fun reconcileTempId(tempId: Long, detail: ExpenseDetail) {
        expenseDao.reconcileTempId(tempId, detail.toEntity())
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
    amount = amount.toCentsOrZero(),
    description = description,
    date = date ?: "",
    status = status ?: "pending",
    userName = listOfNotNull(firstName, lastName).joinToString(" ").ifBlank { null },
    createdAt = createdAt ?: "",
    updatedAt = createdAt ?: "",
)

fun ExpenseDetail.toEntity() = ExpenseEntity(
    id = id,
    category = category ?: "",
    amount = amount.toCentsOrZero(),
    description = description,
    date = date ?: "",
    status = status ?: "pending",
    userName = listOfNotNull(firstName, lastName).joinToString(" ").ifBlank { null },
    userId = userId,
    createdAt = createdAt ?: "",
    updatedAt = updatedAt ?: "",
)
