package com.bizarreelectronics.crm.data.local.db.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(tableName = "sms_messages", indices = [Index("conv_phone"), Index("created_at")])
data class SmsMessageEntity(
    @PrimaryKey
    val id: Long,

    @ColumnInfo(name = "from_number")
    val fromNumber: String?,

    @ColumnInfo(name = "to_number")
    val toNumber: String?,

    @ColumnInfo(name = "conv_phone")
    val convPhone: String,

    val message: String,

    val status: String,

    val direction: String,

    val error: String?,

    val provider: String?,

    @ColumnInfo(name = "provider_message_id")
    val providerMessageId: String?,

    @ColumnInfo(name = "entity_type")
    val entityType: String?,

    @ColumnInfo(name = "entity_id")
    val entityId: Long?,

    @ColumnInfo(name = "user_id")
    val userId: Long?,

    @ColumnInfo(name = "sender_name")
    val senderName: String?,

    @ColumnInfo(name = "message_type")
    val messageType: String = "sms",

    @ColumnInfo(name = "media_urls")
    val mediaUrls: String?,

    @ColumnInfo(name = "media_types")
    val mediaTypes: String?,

    @ColumnInfo(name = "media_local_paths")
    val mediaLocalPaths: String?,

    @ColumnInfo(name = "delivered_at")
    val deliveredAt: String?,

    @ColumnInfo(name = "created_at")
    val createdAt: String,

    @ColumnInfo(name = "updated_at")
    val updatedAt: String?,
)
