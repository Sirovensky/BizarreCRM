package com.bizarreelectronics.crm.data.local.db.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import androidx.compose.runtime.Immutable

/**
 * @audit-fixed: Section 33 / D5 — `customer_id` was an undeclared FK reference.
 * The column had an index but no [ForeignKey] constraint, so deleting a customer
 * left orphaned lead rows pointing at a customer id that no longer existed. The
 * SET_NULL rule mirrors the policy already used by tickets/invoices/estimates so
 * a hard customer delete (e.g. GDPR purge) wipes the link without taking the
 * lead history with it.
 */
@Entity(
    tableName = "leads",
    foreignKeys = [
        ForeignKey(
            entity = CustomerEntity::class,
            parentColumns = ["id"],
            childColumns = ["customer_id"],
            onDelete = ForeignKey.SET_NULL,
        ),
    ],
    indices = [
        Index("customer_id"),
        Index("status"),
        Index("assigned_to"),
        Index("created_at"),
    ]
)
@Immutable
data class LeadEntity(
    @PrimaryKey
    val id: Long,

    @ColumnInfo(name = "order_id")
    val orderId: String? = null,

    @ColumnInfo(name = "customer_id")
    val customerId: Long? = null,

    @ColumnInfo(name = "first_name")
    val firstName: String? = null,

    @ColumnInfo(name = "last_name")
    val lastName: String? = null,

    val email: String? = null,

    val phone: String? = null,

    @ColumnInfo(name = "zip_code")
    val zipCode: String? = null,

    val address: String? = null,

    val status: String? = null,

    @ColumnInfo(name = "referred_by")
    val referredBy: String? = null,

    @ColumnInfo(name = "assigned_to")
    val assignedTo: Long? = null,

    val source: String? = null,

    val notes: String? = null,

    @ColumnInfo(name = "lost_reason")
    val lostReason: String? = null,

    @ColumnInfo(name = "lead_score")
    val leadScore: Int = 0,

    @ColumnInfo(name = "assigned_name")
    val assignedName: String? = null,

    @ColumnInfo(name = "created_at")
    val createdAt: String,

    @ColumnInfo(name = "updated_at")
    val updatedAt: String,

    @ColumnInfo(name = "is_deleted")
    val isDeleted: Boolean = false,

    @ColumnInfo(name = "locally_modified")
    val locallyModified: Boolean = false,
)
