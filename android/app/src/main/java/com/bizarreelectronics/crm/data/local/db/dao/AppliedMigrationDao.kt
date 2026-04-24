package com.bizarreelectronics.crm.data.local.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.bizarreelectronics.crm.data.local.db.entities.AppliedMigrationEntity

/**
 * Data-access object for the [AppliedMigrationEntity] tracking table.
 *
 * All writes use [OnConflictStrategy.IGNORE] so a retried migration run does
 * not fail — idempotence means the first successful write wins and duplicates
 * are silently dropped.
 */
@Dao
interface AppliedMigrationDao {

    /** Insert a migration record. Duplicate (from, to) pairs are ignored. */
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    fun insert(entity: AppliedMigrationEntity)

    /** Return every recorded migration, ordered by [AppliedMigrationEntity.fromVersion]. */
    @Query("SELECT * FROM applied_migrations ORDER BY from_version ASC")
    fun getAll(): List<AppliedMigrationEntity>

    /** Check whether a specific step has been recorded. */
    @Query(
        "SELECT COUNT(*) FROM applied_migrations WHERE from_version = :from AND to_version = :to"
    )
    fun countStep(from: Int, to: Int): Int
}
