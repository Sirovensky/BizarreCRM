package com.bizarreelectronics.crm.data.local.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
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
