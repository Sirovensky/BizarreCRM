package com.bizarreelectronics.crm.data.sync

import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.local.db.entities.SyncQueueEntity
import com.bizarreelectronics.crm.data.remote.api.ConflictResolutionRequest
import com.bizarreelectronics.crm.data.remote.api.ResolvedEntity
import com.bizarreelectronics.crm.data.remote.api.SyncApi
import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.google.gson.Gson
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * JVM unit tests for [ConflictResolver] — plan §20.5 L2118.
 *
 * Tests:
 * 1. Simple scalar field: last-writer-wins — server value wins.
 * 2. List / tag field: union-merge produces combined array.
 * 3. Price field: conflict stored in pendingConflicts, NeedsUserInput returned.
 * 4. Mixed payload: scalars + list + price produces NeedsUserInput with only price in prompt.
 * 5. clearConflict removes the record from pendingConflicts.
 * 6. Unparseable client payload falls back to AutoResolved(serverPayload).
 */
class ConflictResolverTest {

    private lateinit var resolver: ConflictResolver
    private val fakeSyncQueueDao = FakeSyncQueueDao()
    private val fakeSyncApi = FakeSyncApi()
    private val gson = Gson()

    @Before
    fun setUp() {
        resolver = ConflictResolver(fakeSyncQueueDao, fakeSyncApi, gson)
    }

    // ── 1. Last-writer-wins for simple scalar ─────────────────────────────────

    @Test
    fun `simple scalar conflict resolves to server value`() = runTest {
        val client = """{"status":"open","notes":"client note"}"""
        val server = """{"status":"closed","notes":"server note"}"""

        val result = resolver.resolve(
            queueEntryId = 1L,
            entityType = "ticket",
            entityId = 42L,
            clientPayload = client,
            fetchLatest = { server },
        )

        assertTrue("Expected AutoResolved", result is MergeResult.AutoResolved)
        val merged = gson.fromJson((result as MergeResult.AutoResolved).mergedPayload, Map::class.java)
        // LWW: server wins for scalars
        assertEquals("closed", merged["status"])
        assertEquals("server note", merged["notes"])
        assertTrue("No pending conflicts after LWW", resolver.pendingConflicts.isEmpty())
    }

    // ── 2. List-union for tags/labels ─────────────────────────────────────────

    @Test
    fun `list field union-merges client and server arrays`() = runTest {
        val client = """{"labels":["urgent","vip"],"status":"open"}"""
        val server = """{"labels":["vip","warranty"],"status":"open"}"""

        val result = resolver.resolve(
            queueEntryId = 2L,
            entityType = "ticket",
            entityId = 43L,
            clientPayload = client,
            fetchLatest = { server },
        )

        assertTrue("Expected AutoResolved", result is MergeResult.AutoResolved)
        val merged = gson.fromJson((result as MergeResult.AutoResolved).mergedPayload, Map::class.java)
        @Suppress("UNCHECKED_CAST")
        val labels = (merged["labels"] as? List<Any>)?.map { it.toString() }
        assertNotNull("labels should be present", labels)
        assertTrue("union should contain 'urgent'", labels!!.contains("urgent"))
        assertTrue("union should contain 'vip'", labels.contains("vip"))
        assertTrue("union should contain 'warranty'", labels.contains("warranty"))
        assertEquals("no duplicates in union", 3, labels.size)
    }

    // ── 3. Price field triggers user prompt ───────────────────────────────────

    @Test
    fun `price field conflict stored as pending conflict`() = runTest {
        val client = """{"total":15000,"status":"open"}"""
        val server = """{"total":18000,"status":"open"}"""

        val result = resolver.resolve(
            queueEntryId = 3L,
            entityType = "ticket",
            entityId = 44L,
            clientPayload = client,
            fetchLatest = { server },
        )

        assertTrue("Expected NeedsUserInput", result is MergeResult.NeedsUserInput)
        val record = (result as MergeResult.NeedsUserInput).record
        assertEquals(3L, record.id)
        assertEquals("ticket", record.entityType)
        assertEquals(44L, record.entityId)
        assertTrue("total field should be in promptFields", record.promptFields.containsKey("total"))

        // Verify it's stored in pendingConflicts
        assertEquals(1, resolver.pendingConflicts.size)
        assertEquals(3L, resolver.pendingConflicts.first().id)
    }

    // ── 4. Mixed payload ──────────────────────────────────────────────────────

    @Test
    fun `mixed payload: only price fields go to prompt, scalars and lists auto-resolve`() = runTest {
        val client = """{"status":"open","labels":["urgent"],"total":15000}"""
        val server = """{"status":"closed","labels":["warranty"],"total":18000}"""

        val result = resolver.resolve(
            queueEntryId = 4L,
            entityType = "ticket",
            entityId = 45L,
            clientPayload = client,
            fetchLatest = { server },
        )

        assertTrue("Expected NeedsUserInput due to price field", result is MergeResult.NeedsUserInput)
        val record = (result as MergeResult.NeedsUserInput).record
        // Only total should be in promptFields
        assertEquals(1, record.promptFields.size)
        assertTrue(record.promptFields.containsKey("total"))
        // autoMergedPayload should have server status (LWW) and union labels
        val autoMerged = gson.fromJson(record.autoMergedPayload, Map::class.java)
        assertEquals("closed", autoMerged["status"])
        @Suppress("UNCHECKED_CAST")
        val labels = (autoMerged["labels"] as? List<Any>)?.map { it.toString() }
        assertNotNull(labels)
        assertTrue(labels!!.contains("urgent"))
        assertTrue(labels.contains("warranty"))
    }

    // ── 5. clearConflict removes from pendingConflicts ────────────────────────

    @Test
    fun `clearConflict removes the record from pendingConflicts`() = runTest {
        val client = """{"total":15000}"""
        val server = """{"total":18000}"""
        resolver.resolve(
            queueEntryId = 5L,
            entityType = "ticket",
            entityId = 46L,
            clientPayload = client,
            fetchLatest = { server },
        )
        assertEquals(1, resolver.pendingConflicts.size)
        resolver.clearConflict(5L)
        assertTrue("pendingConflicts should be empty after clear", resolver.pendingConflicts.isEmpty())
    }

    // ── 6. Unparseable payload falls back gracefully ──────────────────────────

    @Test
    fun `unparseable client payload falls back to AutoResolved with server payload`() = runTest {
        val client = "NOT_JSON"
        val server = """{"status":"open"}"""

        val result = resolver.resolve(
            queueEntryId = 6L,
            entityType = "ticket",
            entityId = 47L,
            clientPayload = client,
            fetchLatest = { server },
        )

        assertTrue("Expected AutoResolved fallback", result is MergeResult.AutoResolved)
        assertEquals(server, (result as MergeResult.AutoResolved).mergedPayload)
        assertTrue("No pending conflicts on fallback", resolver.pendingConflicts.isEmpty())
    }

    // ── 7. Same values don't produce conflicts ────────────────────────────────

    @Test
    fun `identical client and server values produce no conflicts`() = runTest {
        val payload = """{"total":15000,"status":"open","labels":["urgent"]}"""

        val result = resolver.resolve(
            queueEntryId = 7L,
            entityType = "ticket",
            entityId = 48L,
            clientPayload = payload,
            fetchLatest = { payload },
        )

        assertTrue("Expected AutoResolved when no differences", result is MergeResult.AutoResolved)
        assertTrue("No pending conflicts when values match", resolver.pendingConflicts.isEmpty())
    }

    // ─── Fake DAO ─────────────────────────────────────────────────────────────

    private class FakeSyncQueueDao : SyncQueueDao {
        private val rows = mutableMapOf<Long, SyncQueueEntity>()

        override suspend fun getPending(): List<SyncQueueEntity> =
            rows.values.filter { it.status == "pending" }.sortedBy { it.createdAt }

        override suspend fun getByStatus(status: String): List<SyncQueueEntity> =
            rows.values.filter { it.status == status }

        override suspend fun findByEntity(entityType: String, entityId: Long, operation: String): SyncQueueEntity? =
            rows.values.firstOrNull { it.entityType == entityType && it.entityId == entityId && it.operation == operation }

        override suspend fun insert(entry: SyncQueueEntity): Long {
            val id = (rows.keys.maxOrNull() ?: 0L) + 1
            rows[id] = entry.copy(id = id)
            return id
        }

        override suspend fun updateStatus(id: Long, status: String, error: String?) {
            rows[id]?.let { rows[id] = it.copy(status = status, lastError = error) }
        }

        override suspend fun updatePayload(id: Long, payload: String) {
            rows[id]?.let { rows[id] = it.copy(payload = payload) }
        }

        override suspend fun findPendingEntriesReferencingCustomerId(tempId: Long): List<SyncQueueEntity> =
            rows.values.filter { it.status == "pending" && it.payload.contains("\"customer_id\":$tempId") }

        override suspend fun incrementRetry(id: Long) {
            rows[id]?.let { rows[id] = it.copy(retries = it.retries + 1) }
        }

        override suspend fun deleteCompleted() {
            rows.entries.removeAll { it.value.status == "completed" }
        }

        override fun getCount(): Flow<Int> = kotlinx.coroutines.flow.flowOf(rows.count { it.value.status == "pending" })

        override suspend fun getDeadLetterEntries(): List<SyncQueueEntity> =
            rows.values.filter { it.status == "dead_letter" }

        override fun observeDeadLetterEntries(): Flow<List<SyncQueueEntity>> =
            kotlinx.coroutines.flow.flowOf(rows.values.filter { it.status == "dead_letter" })

        override fun getDeadLetterCount(): Flow<Int> =
            kotlinx.coroutines.flow.flowOf(rows.count { it.value.status == "dead_letter" })

        override suspend fun countDeadLetter(): Int = rows.count { it.value.status == "dead_letter" }

        override suspend fun markDeadLetter(id: Long, error: String?) {
            rows[id]?.let { rows[id] = it.copy(status = "dead_letter", lastError = error) }
        }

        override suspend fun purgeOldDeadLetters(olderThanMillis: Long) {
            rows.entries.removeAll { it.value.status == "dead_letter" && it.value.createdAt < olderThanMillis }
        }

        override suspend fun resurrectDeadLetter(id: Long) {
            rows[id]?.let { rows[id] = it.copy(status = "pending", retries = 0, lastError = null) }
        }

        override suspend fun nextReady(): SyncQueueEntity? =
            rows.values
                .filter { it.status == "pending" }
                .filter { entry ->
                    val depId = entry.dependsOnQueueId ?: return@filter true
                    rows[depId]?.status == "completed"
                }
                .minByOrNull { it.createdAt }

        override suspend fun markSyncing(ids: List<Long>) {
            ids.forEach { id -> rows[id]?.let { rows[id] = it.copy(status = "syncing") } }
        }
    }

    // ─── Fake API ─────────────────────────────────────────────────────────────

    private class FakeSyncApi : SyncApi {
        override suspend fun getDelta(
            since: String,
            cursor: String?,
            limit: Int,
        ): ApiResponse<com.bizarreelectronics.crm.data.remote.api.DeltaPage> =
            ApiResponse(success = true, data = com.bizarreelectronics.crm.data.remote.api.DeltaPage())

        override suspend fun resolveConflict(
            resolution: ConflictResolutionRequest,
        ): ApiResponse<ResolvedEntity> =
            ApiResponse(
                success = true,
                data = ResolvedEntity(
                    entityType = resolution.entityType,
                    id = resolution.entityId,
                    payload = "{}",
                    updatedAt = "2026-01-01T00:00:00Z",
                ),
            )
    }
}
