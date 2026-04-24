package com.bizarreelectronics.crm.data.local.db.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import androidx.compose.runtime.Immutable

// AUDIT-AND-026: added indices on the three columns used by name/email/phone
// search queries. Room will create corresponding SQLite indices automatically.
// A matching Room migration (MIGRATION_4_5) is added in Migrations.kt and the
// @Database version is bumped to 5.
@Entity(
    tableName = "customers",
    indices = [
        Index("last_name"),
        Index("email"),
        Index("phone"),
    ],
)
@Immutable
data class CustomerEntity(
    @PrimaryKey
    val id: Long,

    val code: String? = null,

    @ColumnInfo(name = "first_name")
    val firstName: String? = null,

    @ColumnInfo(name = "last_name")
    val lastName: String? = null,

    val title: String? = null,

    val organization: String? = null,

    val email: String? = null,

    val phone: String? = null,

    val mobile: String? = null,

    val address1: String? = null,

    val address2: String? = null,

    val city: String? = null,

    val state: String? = null,

    val postcode: String? = null,

    val country: String? = null,

    val type: String? = null,

    @ColumnInfo(name = "group_id")
    val groupId: Long? = null,

    @ColumnInfo(name = "group_name")
    val groupName: String? = null,

    @ColumnInfo(name = "email_opt_in")
    val emailOptIn: Boolean = true,

    @ColumnInfo(name = "sms_opt_in")
    val smsOptIn: Boolean = true,

    val comments: String? = null,

    @ColumnInfo(name = "avatar_url")
    val avatarUrl: String? = null,

    val tags: String? = null,

    @ColumnInfo(name = "tax_number")
    val taxNumber: String? = null,

    val source: String? = null,

    @ColumnInfo(name = "referred_by")
    val referredBy: String? = null,

    @ColumnInfo(name = "created_at")
    val createdAt: String,

    @ColumnInfo(name = "updated_at")
    val updatedAt: String,

    @ColumnInfo(name = "is_deleted")
    val isDeleted: Boolean = false,

    @ColumnInfo(name = "locally_modified")
    val locallyModified: Boolean = false,

    /**
     * Epoch-ms timestamp of the last time this row was successfully written
     * to or confirmed by the server. 0 = never synced.
     */
    @ColumnInfo(name = "_synced_at")
    val syncedAt: Long = 0L,
)
