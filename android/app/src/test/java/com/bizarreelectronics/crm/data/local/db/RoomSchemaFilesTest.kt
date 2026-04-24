package com.bizarreelectronics.crm.data.local.db

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Guard rail that fails the build if any committed Room schema JSON is
 * deleted without replacement.
 *
 * Room exports every shipped database version under
 * `app/schemas/<database-class-fqn>/<version>.json` when `exportSchema = true`
 * is set on [BizarreDatabase]. Those JSON files are the canonical record of
 * what the on-device schema looked like at each version — `MigrationTestHelper`
 * reads them when validating migrations, and humans read them when reviewing
 * schema changes.
 *
 * **AUD-20260414-L1 context**
 *
 * When the database was bumped from v3 → v4 (see [Migrations.MIGRATION_3_4]),
 * the build that produced 3.json was never committed — only 1.json, 2.json,
 * and 4.json exist on disk. Reconstructing 3.json now would require either
 * checking out the exact v3 commit and running the Room compiler, or
 * hand-writing a JSON file whose Room-computed identity hash will not match
 * what v3 entity classes would have produced. Neither is practical, so the
 * gap is documented in
 * `app/schemas/com.bizarreelectronics.crm.data.local.db.BizarreDatabase/README.md`
 * and this test is the CI-level protection against losing any further schema
 * files.
 *
 * If a future bump adds 5.json, add "5.json" to [REQUIRED_SCHEMAS] below.
 */
class RoomSchemaFilesTest {

    @Test
    fun requiredRoomSchemaFilesExist() {
        val schemaDir = resolveSchemaDir()
        assertTrue(
            "Room schema directory missing: ${schemaDir.absolutePath}",
            schemaDir.isDirectory,
        )

        val missing = REQUIRED_SCHEMAS.filterNot { name ->
            File(schemaDir, name).isFile
        }
        assertTrue(
            "Missing required Room schema files: $missing. " +
                "If the database was just bumped, rebuild with " +
                "`./gradlew :app:kspDebugKotlin` to regenerate.",
            missing.isEmpty(),
        )
    }

    @Test
    fun documentedGapForVersion3Still() {
        // AUD-20260414-L1: 3.json is intentionally absent. If someone
        // reconstructs it, delete this test AND remove the "3.json" entry
        // from the README.
        val schemaDir = resolveSchemaDir()
        val v3 = File(schemaDir, "3.json")
        assertEquals(
            "3.json appeared on disk — delete this test and update the " +
                "schemas README to acknowledge the gap is closed.",
            false,
            v3.exists(),
        )
    }

    private fun resolveSchemaDir(): File {
        // Unit tests run with working dir = app module root. Schemas live at
        // `app/schemas/<db-fqn>/`.
        val moduleRoot = File("").absoluteFile
        return File(
            moduleRoot,
            "schemas/com.bizarreelectronics.crm.data.local.db.BizarreDatabase",
        )
    }

    private companion object {
        val REQUIRED_SCHEMAS = listOf("1.json", "2.json", "4.json", "5.json", "6.json", "7.json", "8.json", "9.json", "10.json")
    }
}
