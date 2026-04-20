package com.bizarreelectronics.crm.data.local.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import androidx.room.Upsert
import com.bizarreelectronics.crm.data.local.db.entities.InvoiceEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface InvoiceDao {

    @Query("SELECT * FROM invoices ORDER BY created_at DESC")
    fun getAll(): Flow<List<InvoiceEntity>>

    @Query("SELECT * FROM invoices WHERE id = :id")
    fun getById(id: Long): Flow<InvoiceEntity?>

    @Query("SELECT * FROM invoices WHERE customer_id = :customerId ORDER BY created_at DESC")
    fun getByCustomerId(customerId: Long): Flow<List<InvoiceEntity>>

    @Query("SELECT * FROM invoices WHERE status = :status ORDER BY created_at DESC")
    fun getByStatus(status: String): Flow<List<InvoiceEntity>>

    /** Returns outstanding balance in **cents** (sum of `amount_due`). */
    @Query("SELECT SUM(amount_due) FROM invoices WHERE amount_due > 0")
    fun getOutstandingBalance(): Flow<Long?>

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertAll(invoices: List<InvoiceEntity>)

    @Upsert
    suspend fun upsert(invoice: InvoiceEntity)

    @Upsert
    suspend fun insert(invoice: InvoiceEntity)

    @Update
    suspend fun update(invoice: InvoiceEntity)

    /**
     * @audit-fixed: Section 33 / D2 — InvoiceEntity has a `locally_modified`
     * column but no DAO query exposed it, so SyncManager could never enumerate
     * locally-edited invoices the way it does for tickets / customers /
     * inventory / leads. Adding the query closes the gap and matches the
     * pattern used by every other entity that carries the flag.
     */
    @Query("SELECT * FROM invoices WHERE locally_modified = 1")
    suspend fun getLocallyModified(): List<InvoiceEntity>

    /**
     * @audit-fixed: AND-20260414-H5 — rewrite invoices that reference a temp
     * customer id to the server-assigned real customer id. Called from SyncManager
     * after a customer sync succeeds and before the temp customer row is removed.
     * Idempotent: a no-op when no rows match.
     */
    @Query("UPDATE invoices SET customer_id = :newRealId WHERE customer_id = :oldTempId")
    suspend fun updateCustomerIdByOldTempId(oldTempId: Long, newRealId: Long)
}
