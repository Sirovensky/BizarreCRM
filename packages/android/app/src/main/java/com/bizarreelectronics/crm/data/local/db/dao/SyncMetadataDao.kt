package com.bizarreelectronics.crm.data.local.db.dao

import androidx.room.Dao
import androidx.room.Query
import androidx.room.Upsert
import com.bizarreelectronics.crm.data.local.db.entities.SyncMetadataEntity

@Dao
interface SyncMetadataDao {

    @Query("SELECT * FROM sync_metadata WHERE table_name = :tableName")
    suspend fun get(tableName: String): SyncMetadataEntity?

    /** Metadata rows are always upserted by table_name; no child FKs to worry about. */
    @Upsert
    suspend fun upsert(metadata: SyncMetadataEntity)
}
