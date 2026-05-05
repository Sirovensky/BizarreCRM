package com.bizarreelectronics.crm.data.local.db

import com.bizarreelectronics.crm.data.local.db.dao.AppliedMigrationDao
import com.bizarreelectronics.crm.data.local.db.entities.AppliedMigrationEntity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * JVM-only unit tests for [MigrationRegistry].
 *
 * Asserts that:
 *  1. [MigrationRegistry.ALL_ENTRIES] is non-empty.
 *  2. Every step forms a contiguous chain from 1 → [BizarreDatabase.SCHEMA_VERSION].
 *  3. No step is duplicated.
 *  4. [MigrationRegistry.validateAllStepsPresent] passes when the DAO reports
 *     all expected rows present.
 *  5. [MigrationRegistry.validateAllStepsPresent] throws when a row is missing.
 *  6. [MigrationRegistry.allMigrations] returns an array sized equal to
 *     [MigrationRegistry.ALL_ENTRIES].
 *
 * Does not require an Android device or emulator — all dependencies are
 * either pure Kotlin or stubbed inline.
 */
class MigrationRegistryTest {

    // -------------------------------------------------------------------------
    // Entry list invariants
    // -------------------------------------------------------------------------

    @Test
    fun entriesListIsNotEmpty() {
        assertTrue(
            "MigrationRegistry.ALL_ENTRIES must not be empty",
            MigrationRegistry.ALL_ENTRIES.isNotEmpty(),
        )
    }

    @Test
    fun allEntriesAreOrderedAscending() {
        val entries = MigrationRegistry.ALL_ENTRIES
        for (i in 0 until entries.size - 1) {
            assertTrue(
                "Entry at index $i (${entries[i].fromVersion}→${entries[i].toVersion}) " +
                    "is not ordered before entry at index ${i + 1} " +
                    "(${entries[i + 1].fromVersion}→${entries[i + 1].toVersion})",
                entries[i].fromVersion < entries[i + 1].fromVersion,
            )
        }
    }

    @Test
    fun chainCoversOneToCurrentVersion() {
        val current = BizarreDatabase.SCHEMA_VERSION
        val entries = MigrationRegistry.ALL_ENTRIES

        // Every consecutive version step from 1 to current must be present.
        for (v in 1 until current) {
            val found = entries.any { it.fromVersion == v && it.toVersion == v + 1 }
            assertTrue(
                "Missing migration step $v → ${v + 1} in MigrationRegistry.ALL_ENTRIES. " +
                    "Every version bump must have a corresponding Entry.",
                found,
            )
        }
    }

    @Test
    fun noDuplicateSteps() {
        val pairs = MigrationRegistry.ALL_ENTRIES.map { it.fromVersion to it.toVersion }
        val distinct = pairs.distinct()
        assertEquals(
            "Duplicate (fromVersion, toVersion) pairs found in ALL_ENTRIES: " +
                "${pairs - distinct.toSet()}",
            pairs.size,
            distinct.size,
        )
    }

    @Test
    fun lastEntryTargetsCurrentSchemaVersion() {
        val last = MigrationRegistry.ALL_ENTRIES.last()
        assertEquals(
            "Last ALL_ENTRIES entry toVersion must equal BizarreDatabase.SCHEMA_VERSION",
            BizarreDatabase.SCHEMA_VERSION,
            last.toVersion,
        )
    }

    @Test
    fun allMigrationsArraySizeMatchesEntries() {
        val migrations = MigrationRegistry.allMigrations(dao = null)
        assertEquals(
            "allMigrations() array size must equal ALL_ENTRIES size",
            MigrationRegistry.ALL_ENTRIES.size,
            migrations.size,
        )
    }

    // -------------------------------------------------------------------------
    // validateAllStepsPresent
    // -------------------------------------------------------------------------

    @Test
    fun validatePassesWhenAllStepsPresent() {
        val dao = FakeAppliedMigrationDao(allStepsPresent = true)
        // Should not throw.
        MigrationRegistry.validateAllStepsPresent(dao, BizarreDatabase.SCHEMA_VERSION)
    }

    @Test
    fun validateThrowsWhenStepMissing() {
        val dao = FakeAppliedMigrationDao(allStepsPresent = false)
        try {
            MigrationRegistry.validateAllStepsPresent(dao, BizarreDatabase.SCHEMA_VERSION)
            fail("Expected MissingMigrationException but no exception was thrown")
        } catch (e: MigrationRegistry.MissingMigrationException) {
            assertTrue(
                "Exception message should describe the missing step",
                e.message?.contains("missing") == true,
            )
        }
    }

    @Test
    fun validateSkipsCheckForFreshInstall() {
        // installedVersion <= 1 means a fresh install — no rows expected.
        val dao = FakeAppliedMigrationDao(allStepsPresent = false)
        // Should not throw even though the DAO reports no rows.
        MigrationRegistry.validateAllStepsPresent(dao, installedVersion = 1)
    }

    // -------------------------------------------------------------------------
    // MIGRATION_7_8 specific
    // -------------------------------------------------------------------------

    @Test
    fun migration7to8IsPresentInAllEntries() {
        val entry = MigrationRegistry.ALL_ENTRIES.find { it.fromVersion == 7 && it.toVersion == 8 }
        assertTrue(
            "MIGRATION_7_8 (sync_state table + _synced_at columns) must be present in " +
                "MigrationRegistry.ALL_ENTRIES",
            entry != null,
        )
    }

    @Test
    fun chainCoversOneToEight() {
        // Explicit check that 1→8 chain is complete, independent of SCHEMA_VERSION.
        val entries = MigrationRegistry.ALL_ENTRIES
        for (v in 1..7) {
            val found = entries.any { it.fromVersion == v && it.toVersion == v + 1 }
            assertTrue(
                "Missing migration step $v → ${v + 1} in ALL_ENTRIES",
                found,
            )
        }
    }

    // -------------------------------------------------------------------------
    // Heavy migration flag
    // -------------------------------------------------------------------------

    @Test
    fun noEntryIsHeavyByDefault() {
        val anyHeavy = MigrationRegistry.ALL_ENTRIES.any { it.heavy }
        assertFalse(
            "No migration should be flagged heavy yet — update this test when the first heavy " +
                "migration is added.",
            anyHeavy,
        )
    }

    // -------------------------------------------------------------------------
    // Fake DAO
    // -------------------------------------------------------------------------

    /**
     * Minimal fake [AppliedMigrationDao] for unit tests.
     *
     * @param allStepsPresent when true, [countStep] returns 1 for every query;
     *   when false, returns 0 to simulate a missing migration row.
     */
    private class FakeAppliedMigrationDao(
        private val allStepsPresent: Boolean,
    ) : AppliedMigrationDao {
        private val inserted = mutableListOf<AppliedMigrationEntity>()

        override fun insert(entity: AppliedMigrationEntity) {
            inserted.add(entity)
        }

        override fun getAll(): List<AppliedMigrationEntity> = inserted.toList()

        override fun countStep(from: Int, to: Int): Int = if (allStepsPresent) 1 else 0
    }
}
