package com.bizarreelectronics.crm.data.local.db.entities

import androidx.room.ColumnInfo
import androidx.room.Entity

/**
 * Persisted draft for an in-progress repair check-in session.
 *
 * Keyed by (customer_id, device_id) so each customer+device combination has
 * exactly one live draft. The upsert strategy in [CheckInDraftDao] replaces
 * any existing row with the same composite key.
 *
 * [payloadJson] holds a serialised [CheckInUiState]. Sensitive fields
 * (passcode) are stored here because this table lives in the SQLCipher-
 * encrypted database — no additional encryption layer is required. The passcode
 * column on the server is also encrypted and auto-deleted on ticket close.
 *
 * Not included in sync_queue: drafts are intentionally local-only.
 */
@Entity(
    tableName = "checkin_drafts",
    primaryKeys = ["customer_id", "device_id"],
)
data class CheckInDraftEntity(
    @ColumnInfo(name = "customer_id")
    val customerId: Long,

    @ColumnInfo(name = "device_id")
    val deviceId: Long,

    /** Which of the 6 steps the user was on when the draft was saved. */
    @ColumnInfo(name = "step")
    val step: Int,

    /** Serialised JSON of CheckInUiState. */
    @ColumnInfo(name = "payload_json")
    val payloadJson: String,

    /** Epoch-ms of last save — used for the "resume" chip age display. */
    @ColumnInfo(name = "updated_at")
    val updatedAt: Long,
)
