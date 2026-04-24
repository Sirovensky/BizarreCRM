package com.bizarreelectronics.crm.data.local.draft

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * Persisted draft for in-progress form sessions.
 *
 * **One draft per (user_id, draft_type)** — enforced by the unique index so a
 * second save for the same type overwrites the first ([DraftDao.upsert] uses
 * [OnConflictStrategy.REPLACE]).  An explicit discard via [DraftDao.deleteForType]
 * is required before starting a wholly different entity of the same type.
 * (Plan line 263)
 *
 * **Security** — drafts live in the SQLCipher-encrypted `bizarre_crm.db` so
 * [payloadJson] is protected at rest without any additional layer.  Callers
 * MUST NOT serialize password, PIN, TOTP, or backup-code fields into
 * [payloadJson]; [DraftStore] performs a runtime regex sanitisation pass before
 * writing and logs a warning if sensitive keys are found.  (Plan line 264)
 *
 * **No cross-device sync** — this entity is intentionally local-only; it is
 * never included in [SyncQueueEntity] operations and [DraftStore] contains no
 * sync plumbing.  (Plan line 265)
 *
 * **Auto-delete** — rows older than 30 days are pruned via
 * [DraftStore.pruneOlderThanDays].  (Plan line 266)
 */
@Entity(
    tableName = "drafts",
    indices = [Index(value = ["user_id", "draft_type"], unique = true)],
)
data class DraftEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,

    /** Server-assigned user ID, stringified.  Isolates drafts when multiple
     *  users share a device (§2.14 shared-device mode). */
    @ColumnInfo(name = "user_id")
    val userId: String,

    /** Logical form type: "ticket" | "customer" | "sms" (see [DraftStore.DraftType]). */
    @ColumnInfo(name = "draft_type")
    val draftType: String,

    /** Serialised form-field snapshot.  Sensitive keys are stripped by
     *  [DraftStore] before this value is written.  Never null — an empty
     *  JSON object `"{}"` is stored when the form is blank. */
    @ColumnInfo(name = "payload_json")
    val payloadJson: String,

    /** Epoch-millisecond timestamp of the last save.  Used for the "Saved N
     *  ago" age indicator (plan line 262) and for pruning (plan line 266). */
    @ColumnInfo(name = "saved_at")
    val savedAtMs: Long,

    /** If the draft was opened from an existing entity (edit mode), the
     *  server-side ID is stored here so the recovery prompt can route back
     *  to the correct edit screen. Null for create-new drafts. */
    @ColumnInfo(name = "entity_id")
    val entityId: String? = null,
)
