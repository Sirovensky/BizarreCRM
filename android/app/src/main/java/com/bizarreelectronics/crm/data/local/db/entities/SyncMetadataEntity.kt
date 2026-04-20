package com.bizarreelectronics.crm.data.local.db.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "sync_metadata")
data class SyncMetadataEntity(
    @PrimaryKey
    @ColumnInfo(name = "table_name")
    val tableName: String,

    @ColumnInfo(name = "last_synced_at")
    val lastSyncedAt: String,

    @ColumnInfo(name = "last_sync_id")
    val lastSyncId: Long = 0,
)
