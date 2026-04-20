package com.bizarreelectronics.crm.data.local.db.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * @audit-fixed: Section 33 / D6 — `sync_queue` had no indices, so every call to
 * [com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao.getPending] did a
 * full table scan + sort over the entire history of pending+completed+dead-letter
 * entries. The composite index on (status, created_at) supports both the
 * pending-flush hot path and the dead-letter listing in O(log n).
 */
@Entity(
    tableName = "sync_queue",
    indices = [
        Index(value = ["status", "created_at"], name = "index_sync_queue_status_created_at"),
    ],
)
data class SyncQueueEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,

    @ColumnInfo(name = "entity_type")
    val entityType: String,

    @ColumnInfo(name = "entity_id")
    val entityId: Long,

    val operation: String,

    val payload: String,

    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis(),

    val retries: Int = 0,

    @ColumnInfo(name = "last_error")
    val lastError: String? = null,

    val status: String = "pending",
)
