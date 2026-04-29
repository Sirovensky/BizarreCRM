package com.bizarreelectronics.crm.data.local.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import androidx.room.Update
import androidx.room.Upsert
import com.bizarreelectronics.crm.data.local.db.entities.ExpenseEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface ExpenseDao {

    @Query("SELECT * FROM expenses ORDER BY date DESC")
    fun getAll(): Flow<List<ExpenseEntity>>

    @Query("SELECT * FROM expenses WHERE id = :id")
    fun getById(id: Long): Flow<ExpenseEntity?>

    @Query("SELECT * FROM expenses WHERE category = :category ORDER BY date DESC")
    fun getByCategory(category: String): Flow<List<ExpenseEntity>>

    @Query("SELECT * FROM expenses WHERE approval_status = :status ORDER BY date DESC")
    fun getByApprovalStatus(status: String): Flow<List<ExpenseEntity>>

    /**
     * Combined filter query supporting date range, category, and approval status.
     * Pass empty string to skip a filter. Supports any combination of the three.
     */
    @Query(
        """
        SELECT * FROM expenses
        WHERE (:category = '' OR category = :category)
          AND (:dateFrom = '' OR date >= :dateFrom)
          AND (:dateTo = '' OR date <= :dateTo)
          AND (:approvalStatus = '' OR approval_status = :approvalStatus)
          AND (:employeeName = '' OR user_name LIKE '%' || :employeeName || '%')
        ORDER BY date DESC
        """
    )
    fun getFiltered(
        category: String,
        dateFrom: String,
        dateTo: String,
        approvalStatus: String,
        employeeName: String,
    ): Flow<List<ExpenseEntity>>

    @Query(
        """
        SELECT * FROM expenses
        WHERE description LIKE '%' || :query || '%'
            OR category LIKE '%' || :query || '%'
        ORDER BY date DESC
        """
    )
    fun search(query: String): Flow<List<ExpenseEntity>>

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertAll(expenses: List<ExpenseEntity>)

    @Upsert
    suspend fun upsert(expense: ExpenseEntity)

    @Upsert
    suspend fun insert(expense: ExpenseEntity)

    @Update
    suspend fun update(expense: ExpenseEntity)

    @Query("DELETE FROM expenses WHERE id = :id")
    suspend fun deleteById(id: Long)

    /**
     * Atomically swap a temp (negative-id) expense row for the server-authoritative
     * row. Upsert-first, delete-last inside a single Room transaction so concurrent
     * readers never observe a window with zero rows. Idempotent: a no-op when the
     * server echoes the temp id back or when the temp row is already gone. See
     * AND-20260414-H6.
     */
    @Transaction
    suspend fun reconcileTempId(tempId: Long, newEntity: ExpenseEntity) {
        if (newEntity.id == tempId) {
            upsert(newEntity)
            return
        }
        upsert(newEntity)
        deleteById(tempId)
    }

    /**
     * Filter by ISO date range (inclusive). Pass empty string to skip a bound.
     * Used by [ExpenseListViewModel] for the date-range filter.
     */
    @Query(
        """
        SELECT * FROM expenses
        WHERE (:fromDate = '' OR date >= :fromDate)
          AND (:toDate   = '' OR date <= :toDate)
        ORDER BY date DESC
        """
    )
    fun getByDateRange(fromDate: String, toDate: String): Flow<List<ExpenseEntity>>

    /**
     * Filter by employee user_id. Null user_id rows are excluded.
     * Used by [ExpenseListViewModel] for the employee filter.
     */
    @Query("SELECT * FROM expenses WHERE user_id = :userId ORDER BY date DESC")
    fun getByEmployee(userId: Long): Flow<List<ExpenseEntity>>

    /**
     * Filter by approval status (`pending` | `approved` | `denied`).
     * Used by [ExpenseListViewModel] for the approval-status filter.
     */
    @Query("SELECT * FROM expenses WHERE status = :status ORDER BY date DESC")
    fun getByStatus(status: String): Flow<List<ExpenseEntity>>

    /** Total expense amount in **cents**. */
    @Query("SELECT SUM(amount) FROM expenses")
    fun getTotalAmount(): Flow<Long?>

    /**
     * @audit-fixed: Section 33 / D4 — Same gap as Invoice and Estimate. The
     * `locally_modified` flag exists on [ExpenseEntity] but had no DAO accessor,
     * which meant edits made offline could never be enumerated for replay.
     */
    @Query("SELECT * FROM expenses WHERE locally_modified = 1")
    suspend fun getLocallyModified(): List<ExpenseEntity>
}
