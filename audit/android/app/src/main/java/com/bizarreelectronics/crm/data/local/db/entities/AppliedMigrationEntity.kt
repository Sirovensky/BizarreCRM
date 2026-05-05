package com.bizarreelectronics.crm.data.local.db.entities

import androidx.room.ColumnInfo
import androidx.room.Entity

/**
 * Tracks every Room schema migration that has been applied on this device.
 *
 * A row is inserted immediately after each [androidx.room.migration.Migration.migrate]
 * call returns. On every subsequent app open, [com.bizarreelectronics.crm.data.local.db.MigrationRegistry]
 * reads this table and asserts that all expected steps from version 1 to the
 * current schema version are present. A missing step triggers a fatal-boot
 * error rather than silently producing a structurally invalid database.
 *
 * The table has no surrogate primary key — the `(from_version, to_version)`
 * pair is the natural identity. Duplicate inserts are idempotent via
 * `INSERT OR IGNORE` in [com.bizarreelectronics.crm.data.local.db.dao.AppliedMigrationDao].
 *
 * Column semantics:
 *  - [fromVersion] / [toVersion]: the migration step bounds, e.g. 5 → 6.
 *  - [appliedAtMs]: epoch-millisecond timestamp recorded right after the migration
 *    completes. Useful for diagnosing slow-migration complaints in field reports.
 *  - [durationMs]: wall-clock milliseconds the migration body took. 0 when unknown.
 *  - [name]: human-readable label from [com.bizarreelectronics.crm.data.local.db.MigrationRegistry.Entry.name].
 */
@Entity(
    tableName = "applied_migrations",
    primaryKeys = ["from_version", "to_version"],
)
data class AppliedMigrationEntity(
    @ColumnInfo(name = "from_version") val fromVersion: Int,
    @ColumnInfo(name = "to_version") val toVersion: Int,
    @ColumnInfo(name = "applied_at") val appliedAtMs: Long,
    @ColumnInfo(name = "duration_ms") val durationMs: Long,
    @ColumnInfo(name = "name") val name: String,
)
