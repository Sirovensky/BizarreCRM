package com.bizarreelectronics.crm.data.local.db.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey
import androidx.compose.runtime.Immutable

@Entity(tableName = "call_logs")
@Immutable
data class CallLogEntity(
    @PrimaryKey
    val id: Long,

    val direction: String,

    @ColumnInfo(name = "from_number")
    val fromNumber: String?,

    @ColumnInfo(name = "to_number")
    val toNumber: String?,

    @ColumnInfo(name = "conv_phone")
    val convPhone: String?,

    val provider: String?,

    @ColumnInfo(name = "provider_call_id")
    val providerCallId: String?,

    val status: String,

    @ColumnInfo(name = "duration_secs")
    val durationSecs: Int?,

    @ColumnInfo(name = "recording_url")
    val recordingUrl: String?,

    @ColumnInfo(name = "recording_local_path")
    val recordingLocalPath: String?,

    val transcription: String?,

    @ColumnInfo(name = "transcription_status")
    val transcriptionStatus: String = "none",

    @ColumnInfo(name = "call_mode")
    val callMode: String = "bridge",

    @ColumnInfo(name = "user_id")
    val userId: Long?,

    @ColumnInfo(name = "user_name")
    val userName: String?,

    @ColumnInfo(name = "entity_type")
    val entityType: String?,

    @ColumnInfo(name = "entity_id")
    val entityId: Long?,

    @ColumnInfo(name = "created_at")
    val createdAt: String,
)
