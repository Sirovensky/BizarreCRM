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
 *
 * Plan §20.2 L2108 — added `depends_on_queue_id` (nullable Long). When non-null,
 * [OrderedQueueProcessor] will not dispatch this entry until the parent entry's
 * status is `completed`. A separate index on `depends_on_queue_id` keeps the
 * readiness check O(log n) even with a large queue.
 */
@Entity(
    tableName = "sync_queue",
    indices = [
        Index(value = ["status", "created_at"], name = "index_sync_queue_status_created_at"),
        Index(value = ["depends_on_queue_id"], name = "index_sync_queue_depends_on_queue_id"),
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

    /** Stable UUID assigned at enqueue time. Used for server-side idempotency checks. */
    @ColumnInfo(name = "idempotency_key")
    val idempotencyKey: String? = null,

    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis(),

    val retries: Int = 0,

    @ColumnInfo(name = "last_error")
    val lastError: String? = null,

    val status: String = "pending",

    /**
     * Optional foreign key into the same `sync_queue` table. When non-null,
     * [OrderedQueueProcessor.nextReady] will skip this entry until the parent
     * entry (identified by this id) has `status = 'completed'`. This enforces
     * FIFO-within-dependency-chain semantics: e.g. a ticket-create must complete
     * before its child note-add is dispatched. Set to null for independent entries.
     *
     * Plan §20.2 L2108 / MIGRATION_9_10 adds this column via ALTER TABLE.
     */
    @ColumnInfo(name = "depends_on_queue_id")
    val dependsOnQueueId: Long? = null,
)
