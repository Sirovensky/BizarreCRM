package com.bizarreelectronics.crm.data.local.draft

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Unit tests for [DraftStore] business logic using a pure-JVM fake DAO.
 *
 * No Android context, Room, or Robolectric required.  Logic under test lives
 * in [TestDraftStore] (same module, `internal`) and the package-internal
 * [sanitiseDraftPayload] function, both in the same package.
 *
 * ### Cases
 *  1.  save + load roundtrip preserves type, payload, entityId
 *  2.  unique-per-type: saving twice replaces prior draft
 *  3.  discard removes draft; load returns null
 *  4.  pruneOlderThanDays removes old rows, keeps recent ones
 *  5.  sensitive field `password` is stripped by sanitiseDraftPayload
 *  6.  sensitive field `pin` is stripped
 *  7.  sensitive field `totp` is stripped
 *  8.  sensitive field `secret` is stripped
 *  9.  sensitive field `backup_code` is stripped
 * 10.  non-sensitive payload passes through unchanged
 * 11.  save is a no-op when userId provider returns 0 (not logged in)
 * 12.  load returns null when userId provider returns 0
 * 13.  observeAll emits empty list when userId provider returns 0
 * 14.  save with entityId roundtrips correctly
 * 15.  different types do not interfere with each other
 */
class DraftStoreTest {

    // ------------------------------------------------------------------
    // Fake DAO
    // ------------------------------------------------------------------

    private class FakeDraftDao : DraftDao {
        private val store = mutableMapOf<Pair<String, String>, DraftEntity>()
        private val flow = MutableStateFlow<List<DraftEntity>>(emptyList())

        private fun publish() {
            flow.value = store.values.toList()
        }

        override suspend fun getForType(userId: String, type: String): DraftEntity? =
            store[userId to type]

        override suspend fun upsert(draft: DraftEntity) {
            store[draft.userId to draft.draftType] = draft
            publish()
        }

        override suspend fun deleteForType(userId: String, type: String) {
            store.remove(userId to type)
            publish()
        }

        override suspend fun deleteOlderThan(olderThanMs: Long): Int {
            val stale = store.entries.filter { it.value.savedAtMs < olderThanMs }
            stale.forEach { store.remove(it.key) }
            publish()
            return stale.size
        }

        override fun observeAllForUser(userId: String): Flow<List<DraftEntity>> =
            flow.map { list -> list.filter { it.userId == userId } }
    }

    // ------------------------------------------------------------------
    // System under test
    // ------------------------------------------------------------------

    private lateinit var fakeDao: FakeDraftDao
    private var currentUserId: Long = USER_ID

    /** Creates a fresh [TestDraftStore] with the shared fake DAO. */
    private fun makeStore() = DraftStore.forTesting(fakeDao) { currentUserId }

    @Before
    fun setUp() {
        fakeDao = FakeDraftDao()
        currentUserId = USER_ID
    }

    // ------------------------------------------------------------------
    // 1. save + load roundtrip
    // ------------------------------------------------------------------

    @Test
    fun `save then load returns Draft with correct type and payload`() = runBlocking {
        val store = makeStore()
        store.save(DraftStore.DraftType.TICKET, """{"title":"fix screen"}""")

        val draft = store.load(DraftStore.DraftType.TICKET)

        assertNotNull(draft)
        assertEquals(DraftStore.DraftType.TICKET, draft!!.type)
        assertEquals("""{"title":"fix screen"}""", draft.payloadJson)
        assertNull(draft.entityId)
    }

    // ------------------------------------------------------------------
    // 2. unique-per-type: save twice replaces prior draft
    // ------------------------------------------------------------------

    @Test
    fun `save twice for same type replaces prior draft`() = runBlocking {
        val store = makeStore()
        store.save(DraftStore.DraftType.CUSTOMER, """{"first_name":"Alice"}""")
        store.save(DraftStore.DraftType.CUSTOMER, """{"first_name":"Bob"}""")

        val draft = store.load(DraftStore.DraftType.CUSTOMER)

        assertNotNull(draft)
        assertEquals("""{"first_name":"Bob"}""", draft!!.payloadJson)
        // Only one entry in the fake DAO for this key
        assertNotNull(fakeDao.getForType(USER_ID.toString(), "customer"))
        assertNull(fakeDao.getForType(USER_ID.toString(), "customer_alt"))
    }

    // ------------------------------------------------------------------
    // 3. discard removes draft
    // ------------------------------------------------------------------

    @Test
    fun `discard removes draft and subsequent load returns null`() = runBlocking {
        val store = makeStore()
        store.save(DraftStore.DraftType.SMS, """{"body":"hello"}""")
        assertNotNull(store.load(DraftStore.DraftType.SMS))

        store.discard(DraftStore.DraftType.SMS)

        assertNull(store.load(DraftStore.DraftType.SMS))
    }

    // ------------------------------------------------------------------
    // 4. pruneOlderThanDays
    // ------------------------------------------------------------------

    @Test
    fun `pruneOlderThanDays removes stale rows and preserves recent ones`() = runBlocking {
        val now = System.currentTimeMillis()
        val fiftyDaysMs = now - 50L * 24 * 60 * 60 * 1000
        val oneDayMs = now - 1L * 24 * 60 * 60 * 1000

        fakeDao.upsert(
            DraftEntity(userId = USER_ID.toString(), draftType = "ticket", payloadJson = "{}", savedAtMs = fiftyDaysMs)
        )
        fakeDao.upsert(
            DraftEntity(userId = USER_ID.toString(), draftType = "customer", payloadJson = "{}", savedAtMs = oneDayMs)
        )

        val store = makeStore()
        val deleted = store.pruneOlderThanDays(30)

        assertEquals("One old draft should be deleted", 1, deleted)
        assertNull("Stale ticket draft must be gone", fakeDao.getForType(USER_ID.toString(), "ticket"))
        assertNotNull("Recent customer draft must survive", fakeDao.getForType(USER_ID.toString(), "customer"))
    }

    // ------------------------------------------------------------------
    // 5–9. Sensitive field sanitisation (via sanitiseDraftPayload directly)
    // ------------------------------------------------------------------

    @Test
    fun `sanitiseDraftPayload strips password key`() {
        val result = sanitiseDraftPayload("""{"title":"fix","password":"s3cr3t"}""")
        assertTrue("password must be stripped", !result.contains("password", ignoreCase = true))
        assertTrue("title must survive", result.contains("title"))
    }

    @Test
    fun `sanitiseDraftPayload strips pin key`() {
        val result = sanitiseDraftPayload("""{"name":"Alice","pin":"1234"}""")
        assertTrue("pin must be stripped", !result.contains("\"pin\"", ignoreCase = true))
    }

    @Test
    fun `sanitiseDraftPayload strips totp key`() {
        val result = sanitiseDraftPayload("""{"device":"iPhone","totp":"123456"}""")
        assertTrue("totp must be stripped", !result.contains("totp", ignoreCase = true))
    }

    @Test
    fun `sanitiseDraftPayload strips secret key`() {
        val result = sanitiseDraftPayload("""{"body":"hello","secret":"abc"}""")
        assertTrue("secret must be stripped", !result.contains("\"secret\"", ignoreCase = true))
    }

    @Test
    fun `sanitiseDraftPayload strips backup_code key`() {
        val result = sanitiseDraftPayload("""{"notes":"test","backup_code":"ABCDE"}""")
        assertTrue("backup_code must be stripped", !result.contains("backup_code", ignoreCase = true))
    }

    // ------------------------------------------------------------------
    // 10. Non-sensitive payload passes through unchanged
    // ------------------------------------------------------------------

    @Test
    fun `non-sensitive payload is stored exactly as provided`() = runBlocking {
        val json = """{"title":"Cracked screen","customer_id":42,"notes":"careful"}"""
        val store = makeStore()
        store.save(DraftStore.DraftType.TICKET, json)

        val draft = store.load(DraftStore.DraftType.TICKET)

        assertNotNull(draft)
        assertEquals(json, draft!!.payloadJson)
    }

    // ------------------------------------------------------------------
    // 11. save is no-op when userId is 0
    // ------------------------------------------------------------------

    @Test
    fun `save is a no-op when userId provider returns 0`() = runBlocking {
        currentUserId = 0L
        val store = makeStore()

        store.save(DraftStore.DraftType.TICKET, """{"title":"should not persist"}""")

        assertNull(
            "No draft should be stored when userId is 0",
            fakeDao.getForType("0", "ticket"),
        )
        // Confirm no row for the real userId either (which happens to be 0)
        assertNull(fakeDao.getForType(USER_ID.toString(), "ticket"))
    }

    // ------------------------------------------------------------------
    // 12. load returns null when userId is 0
    // ------------------------------------------------------------------

    @Test
    fun `load returns null when userId provider returns 0`() = runBlocking {
        // Pre-populate the DAO as the real user
        fakeDao.upsert(
            DraftEntity(userId = USER_ID.toString(), draftType = "ticket", payloadJson = "{}", savedAtMs = 1L)
        )

        currentUserId = 0L
        val store = makeStore()

        assertNull("load must return null when userId is 0", store.load(DraftStore.DraftType.TICKET))
    }

    // ------------------------------------------------------------------
    // 13. observeAll emits empty list when userId is 0
    // ------------------------------------------------------------------

    @Test
    fun `observeAll emits empty list when userId provider returns 0`() = runBlocking {
        currentUserId = 0L
        val store = makeStore()

        val result = store.observeAll().first()

        assertEquals(emptyList<DraftStore.Draft>(), result)
    }

    // ------------------------------------------------------------------
    // 14. save with entityId roundtrips correctly
    // ------------------------------------------------------------------

    @Test
    fun `save with entityId is preserved in load`() = runBlocking {
        val store = makeStore()
        store.save(DraftStore.DraftType.TICKET, """{"title":"edit"}""", entityId = "ticket-99")

        val draft = store.load(DraftStore.DraftType.TICKET)

        assertNotNull(draft)
        assertEquals("ticket-99", draft!!.entityId)
    }

    // ------------------------------------------------------------------
    // 15. different types do not interfere
    // ------------------------------------------------------------------

    @Test
    fun `drafts for different types are independent`() = runBlocking {
        val store = makeStore()
        store.save(DraftStore.DraftType.TICKET, """{"title":"T1"}""")
        store.save(DraftStore.DraftType.CUSTOMER, """{"first_name":"C1"}""")
        store.save(DraftStore.DraftType.SMS, """{"body":"S1"}""")

        store.discard(DraftStore.DraftType.CUSTOMER)

        assertNotNull("Ticket draft must survive customer discard", store.load(DraftStore.DraftType.TICKET))
        assertNull("Customer draft must be gone", store.load(DraftStore.DraftType.CUSTOMER))
        assertNotNull("SMS draft must survive customer discard", store.load(DraftStore.DraftType.SMS))
    }

    // ------------------------------------------------------------------
    // Companion
    // ------------------------------------------------------------------

    private companion object {
        const val USER_ID = 7L
    }
}
