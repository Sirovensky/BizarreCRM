package com.bizarreelectronics.crm.data.local.db

import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

/**
 * Central registry of every Room schema migration step.
 *
 * ## Purpose
 *
 * This object is the single source of truth for:
 *
 *  1. **Which [Migration] objects exist** — [Entry.migration] wraps every manual
 *     Migration and records timing metrics after each one completes.
 *  2. **Whether a migration is "heavy"** — when [Entry.heavy] is `true`,
 *     [com.bizarreelectronics.crm.data.sync.DbMigrationBackupWorker] is enqueued
 *     to run the migration out-of-process with a progress notification. No heavy
 *     migration currently exists; the flag is infrastructure for future use.
 *  3. **Validation at boot** — [validateAllStepsPresent] verifies that the
 *     `applied_migrations` table contains a record for every step from 1 to
 *     [BizarreDatabase.SCHEMA_VERSION]. A gap means the DB is structurally
 *     suspect and the app will stop with a clear message rather than silently
 *     misbehave.
 *
 * ## AutoMigration vs manual Migration convention (Line 215)
 *
 * - **@AutoMigration** — use when the schema change is purely additive or
 *   renames a column with a `@RenameColumn` spec. No data transformation is
 *   required and Room can derive the DDL automatically. Declare the annotation
 *   on [BizarreDatabase] and add an [Entry] with `heavy = false` and a
 *   pass-through [migration] that calls [Migration.migrate] on the wrapped
 *   Room-generated implementation.
 * - **Manual Migration** — use whenever rows must be back-filled, column types
 *   must change (e.g. REAL → INTEGER cents), foreign keys must be added, or any
 *   data transformation is needed. Always document the reason in KDoc on the
 *   [Migration] object in [Migrations].
 *
 * Rationale: AutoMigrations are brittle when data shifts are involved because
 * Room generates only schema DDL, not the INSERT … SELECT needed to preserve
 * row data across a table rebuild.
 *
 * ## Adding a new migration
 *
 * 1. Bump `version` in `@Database` on [BizarreDatabase].
 * 2. Add a `MIGRATION_N_(N+1)` object to [Migrations] with full KDoc.
 * 3. Add an [Entry] to [ALL_ENTRIES] below.
 * 4. Update [RoomSchemaFilesTest] with the new JSON filename.
 * 5. Run `./gradlew :app:kspDebugKotlin` to export the schema JSON.
 */
object MigrationRegistry {

    /**
     * Describes a single migration step.
     *
     * @param fromVersion source schema version.
     * @param toVersion target schema version.
     * @param name human-readable label shown in logs and the tracking table.
     * @param heavy when `true`, the migration is offloaded to
     *   [com.bizarreelectronics.crm.data.sync.DbMigrationBackupWorker] via an
     *   expedited WorkManager job. Set this for any migration that copies
     *   millions of rows or does expensive data transformations.
     * @param migration the Room [Migration] implementation. Wrap with
     *   [TimedMigration] so duration is recorded automatically — see [allMigrations].
     */
    data class Entry(
        val fromVersion: Int,
        val toVersion: Int,
        val name: String,
        val heavy: Boolean = false,
        val migration: Migration,
    )

    /**
     * Every migration step in ascending order.
     *
     * All entries must form a contiguous chain from 1 to [BizarreDatabase.SCHEMA_VERSION].
     * [validateAllStepsPresent] enforces this at boot via the tracking table.
     */
    val ALL_ENTRIES: List<Entry> = listOf(
        Entry(
            fromVersion = 1,
            toVersion = 2,
            name = "stub-1-2: no-op for dev builds",
            migration = Migrations.MIGRATION_1_2,
        ),
        Entry(
            fromVersion = 2,
            toVersion = 3,
            name = "money-cents: REAL → INTEGER cents + FK enforcement",
            migration = Migrations.MIGRATION_2_3,
        ),
        Entry(
            fromVersion = 3,
            toVersion = 4,
            name = "inventory-cents: cost/retail + indices + leads FK + sync_queue index",
            migration = Migrations.MIGRATION_3_4,
        ),
        Entry(
            fromVersion = 4,
            toVersion = 5,
            name = "customer-search-indices: last_name + email + phone",
            migration = Migrations.MIGRATION_4_5,
        ),
        Entry(
            fromVersion = 5,
            toVersion = 6,
            name = "drafts-table: autosave storage",
            migration = Migrations.MIGRATION_5_6,
        ),
        Entry(
            fromVersion = 6,
            toVersion = 7,
            name = "applied-migrations-table: migration discipline tracking",
            migration = Migrations.MIGRATION_6_7,
        ),
    )

    /**
     * Flat array of [Migration] objects suitable for
     * `RoomDatabase.Builder.addMigrations(*allMigrations())`.
     *
     * Each raw migration is wrapped in a [TimedMigration] so that
     * [com.bizarreelectronics.crm.data.local.db.entities.AppliedMigrationEntity]
     * rows are inserted automatically after each step completes.
     *
     * @param dao live DAO reference — acquired by [DatabaseModule] from the
     *   in-progress Room connection inside the builder callback. May be null
     *   during tests where tracking is not required.
     */
    fun allMigrations(
        dao: com.bizarreelectronics.crm.data.local.db.dao.AppliedMigrationDao? = null,
    ): Array<Migration> = ALL_ENTRIES
        .map { entry -> TimedMigration(entry, dao) }
        .toTypedArray()

    /**
     * Validate that every step from 1 → [BizarreDatabase.SCHEMA_VERSION] has a
     * corresponding row in `applied_migrations`.
     *
     * Called from [RoomDatabase.Callback.onOpen] in [DatabaseModule]. Throws a
     * [MissingMigrationException] if any step is absent. On brand-new installs
     * the table is empty but [expectedSteps] will also be empty (version went
     * from 0 → current in a single Room onCreate), so the check passes silently.
     *
     * @param dao DAO bound to the freshly-opened database.
     * @param installedVersion the version Room reports the DB is currently at —
     *   obtained via `db.version` inside onOpen. For a fresh install this equals
     *   [BizarreDatabase.SCHEMA_VERSION] and [expectedSteps] is empty.
     */
    fun validateAllStepsPresent(
        dao: com.bizarreelectronics.crm.data.local.db.dao.AppliedMigrationDao,
        installedVersion: Int,
    ) {
        if (installedVersion <= 1) return // fresh install — no migration rows expected

        val expectedSteps = ALL_ENTRIES.filter { it.toVersion <= installedVersion }
        if (expectedSteps.isEmpty()) return

        val missing = expectedSteps.filter { entry ->
            dao.countStep(entry.fromVersion, entry.toVersion) == 0
        }

        if (missing.isNotEmpty()) {
            val detail = missing.joinToString(", ") { "${it.fromVersion}→${it.toVersion} (${it.name})" }
            throw MissingMigrationException(
                "applied_migrations table is missing expected steps: $detail. " +
                    "The database may have been opened outside of the normal upgrade path. " +
                    "Contact Bizarre Electronics support or reinstall the app."
            )
        }
    }

    /**
     * Whether any entry in [ALL_ENTRIES] for a given (from, to) step is flagged
     * as heavy. Used by [DatabaseModule] to decide whether to enqueue
     * [com.bizarreelectronics.crm.data.sync.DbMigrationBackupWorker].
     */
    fun isHeavy(fromVersion: Int, toVersion: Int): Boolean =
        ALL_ENTRIES.any { it.fromVersion == fromVersion && it.toVersion == toVersion && it.heavy }

    /**
     * Thrown when the migration tracking table is missing expected rows at
     * app startup. Fatal — the caller should surface this to the user and exit.
     */
    class MissingMigrationException(message: String) : RuntimeException(message)

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    /**
     * Wraps a [Migration] to record timing in [AppliedMigrationEntity] after
     * each successful [migrate] call.
     */
    private class TimedMigration(
        private val entry: Entry,
        private val dao: com.bizarreelectronics.crm.data.local.db.dao.AppliedMigrationDao?,
    ) : Migration(entry.fromVersion, entry.toVersion) {

        override fun migrate(db: SupportSQLiteDatabase) {
            val start = System.currentTimeMillis()
            entry.migration.migrate(db)
            val duration = System.currentTimeMillis() - start

            dao?.insert(
                com.bizarreelectronics.crm.data.local.db.entities.AppliedMigrationEntity(
                    fromVersion = entry.fromVersion,
                    toVersion = entry.toVersion,
                    appliedAtMs = System.currentTimeMillis(),
                    durationMs = duration,
                    name = entry.name,
                )
            )
        }
    }
}
