package com.bizarreelectronics.crm.data.local.db.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index

/**
 * Tracks server-side pagination / cursor state for each sync-able collection.
 *
 * ## Composite key
 *
 * Room does not allow nullable columns in a composite primary key. Nullable
 * dimensions (`filterKey`, `parentId`) are treated as empty string / 0
 * sentinels in the PK while the Kotlin API still exposes nullable types via
 * [SyncStateEntity.filterKey] and [SyncStateEntity.parentId].
 *
 * Use [SyncStateEntity.filterKey] / [SyncStateEntity.parentId] for reads;
 * set them to `""` / `0L` explicitly when constructing a root-level entry
 * (the DAO helpers coerce nulls for you).
 *
 * ## Columns
 *
 * | column               | meaning                                                   |
 * |----------------------|-----------------------------------------------------------|
 * | entity               | logical collection name, e.g. `"tickets"`, `"customers"` |
 * | filter_key           | optional filter tag, e.g. `"status:open"` (empty = none) |
 * | parent_id            | optional parent entity ID, e.g. ticket ID for notes (0 = none) |
 * | cursor               | opaque server cursor / next-page token                    |
 * | oldest_cached_at     | epoch-ms of the oldest item in the local cache            |
 * | server_exhausted_at  | epoch-ms when server confirmed no more pages (null = more pages remain) |
 * | last_updated_at      | epoch-ms of the last successful sync for this entry       |
 *
 * ## hasMore
 *
 * The derived "has more pages" state is `serverExhaustedAt == null`. The DAO
 * exposes [SyncStateDao.hasMore] as a convenience.
 */
@Entity(
    tableName = "sync_state",
    primaryKeys = ["entity", "filter_key", "parent_id"],
    indices = [
        Index(value = ["entity", "filter_key", "parent_id"], unique = true),
    ],
)
data class SyncStateEntity(
    /** Logical collection name, e.g. `"tickets"` or `"customers"`. */
    @ColumnInfo(name = "entity")
    val entity: String,

    /**
     * Optional filter tag, e.g. `"status:open"`.
     * Use empty string `""` to represent "no filter" (PK cannot be null).
     */
    @ColumnInfo(name = "filter_key")
    val filterKey: String = "",

    /**
     * Optional parent entity ID, e.g. a ticket ID for ticket-notes.
     * Use `0L` to represent "no parent" (PK cannot be null).
     */
    @ColumnInfo(name = "parent_id")
    val parentId: Long = 0L,

    /** Opaque server cursor / next-page token. Null when not yet fetched. */
    @ColumnInfo(name = "cursor")
    val cursor: String? = null,

    /** Epoch-ms of the oldest item currently held in the local cache. */
    @ColumnInfo(name = "oldest_cached_at")
    val oldestCachedAt: Long = 0L,

    /**
     * Epoch-ms when the server confirmed there are no more pages for this
     * collection/filter/parent combination. Null means more pages remain
     * or the state has never been fetched.
     */
    @ColumnInfo(name = "server_exhausted_at")
    val serverExhaustedAt: Long? = null,

    /** Epoch-ms of the last time this sync-state entry was updated. */
    @ColumnInfo(name = "last_updated_at")
    val lastUpdatedAt: Long = 0L,
)
