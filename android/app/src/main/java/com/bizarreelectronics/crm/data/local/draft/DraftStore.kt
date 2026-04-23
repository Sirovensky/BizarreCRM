package com.bizarreelectronics.crm.data.local.draft

import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import timber.log.Timber
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Facade over [DraftDao] that provides a clean, type-safe API for reading and
 * writing autosave drafts.
 *
 * ### Design guarantees
 *
 * **One draft per type (plan line 263)**
 * The underlying [DraftDao] uses a unique index on `(user_id, draft_type)` and
 * `OnConflictStrategy.REPLACE`.  Calling [save] twice for the same [DraftType]
 * silently overwrites the previous draft; an explicit [discard] call is required
 * before a wholly new draft of that type can be started.
 *
 * **Encryption at rest (plan line 264)**
 * Drafts are stored in the SQLCipher-encrypted Room database (`bizarre_crm.db`).
 * The passphrase is managed by
 * [com.bizarreelectronics.crm.data.local.prefs.DatabasePassphrase] and backed
 * by the Android Keystore.  No extra encryption layer is needed — any forensic
 * dump of the database file sees ciphertext only.
 *
 * Additionally, [save] performs a runtime sanitisation pass on [payloadJson]
 * before writing: any JSON key matching `password`, `pin`, `totp`, `secret`,
 * or `backup_code` (case-insensitive) — together with its string value — is
 * stripped and a Timber.w is logged.  Callers should still avoid serialising
 * such fields in the first place.
 *
 * **No cross-device sync (plan line 265)**
 * Drafts are intentionally local-only.  This class contains no sync plumbing,
 * no [com.bizarreelectronics.crm.data.local.db.entities.SyncQueueEntity]
 * enqueuing, and no reference to any remote data source.  Keeping drafts local
 * avoids confusion when the same account is used on multiple devices.
 *
 * **Auto-delete (plan line 266)**
 * Call [pruneOlderThanDays] on application startup (wired in a later wave) to
 * remove drafts older than 30 days.
 *
 * ### Per-feature 2-second autosave and recovery prompt (plan lines 260-261)
 * ViewModel-level wiring (debounce timer, recovery-prompt composable) is
 * implemented in later waves.  This store provides all the persistence
 * operations those layers need.
 *
 * ### Testability
 * All business logic (sanitisation, pruning cutoff, type mapping) is extracted
 * into package-internal top-level functions that host-side unit tests can call
 * directly without constructing [AuthPreferences] or a Room database.
 * See [sanitiseDraftPayload] and the [DraftStore.Companion.forTesting] factory.
 */
@Singleton
class DraftStore @Inject constructor(
    private val dao: DraftDao,
    private val authPreferences: AuthPreferences,
) {
    // ------------------------------------------------------------------
    // Public API
    // ------------------------------------------------------------------

    /**
     * Saves (or replaces) the draft for [type].
     *
     * [payloadJson] is sanitised to remove sensitive keys before writing.
     * If the current user ID is 0 (not logged in) the call is a no-op.
     */
    suspend fun save(type: DraftType, payloadJson: String, entityId: String? = null) {
        val userId = userIdString() ?: run {
            Timber.w("DraftStore.save: skipped — userId is 0 (not logged in)")
            return
        }

        val sanitised = sanitiseDraftPayload(payloadJson)
        dao.upsert(
            DraftEntity(
                userId = userId,
                draftType = type.storageKey,
                payloadJson = sanitised,
                savedAtMs = System.currentTimeMillis(),
                entityId = entityId,
            )
        )
    }

    /**
     * Returns the saved [Draft] for [type], or `null` if none exists.
     * Returns `null` when the user is not logged in (ID = 0).
     */
    suspend fun load(type: DraftType): Draft? {
        val userId = userIdString() ?: return null
        return dao.getForType(userId, type.storageKey)?.toDraft()
    }

    /**
     * Permanently discards the draft for [type].  No-op when no draft exists
     * or when the user is not logged in.
     */
    suspend fun discard(type: DraftType) {
        val userId = userIdString() ?: return
        dao.deleteForType(userId, type.storageKey)
    }

    /**
     * Deletes all drafts older than [days] days from now.
     * Returns the count of deleted rows.  Call on app startup (plan line 266).
     */
    suspend fun pruneOlderThanDays(days: Int = 30): Int {
        val cutoffMs = System.currentTimeMillis() - TimeUnit.DAYS.toMillis(days.toLong())
        return dao.deleteOlderThan(cutoffMs)
    }

    /**
     * Live stream of all drafts for the current user, newest first.
     * Emits an empty list when not logged in.  (Plan line 261, later wave.)
     */
    fun observeAll(): Flow<List<Draft>> {
        val userId = userIdString() ?: return flowOf(emptyList())
        return dao.observeAllForUser(userId).map { list -> list.map { it.toDraft() } }
    }

    // ------------------------------------------------------------------
    // Value types
    // ------------------------------------------------------------------

    /** Immutable view of a persisted draft exposed to callers. */
    data class Draft(
        val type: DraftType,
        val payloadJson: String,
        /** Epoch-millisecond timestamp for "Saved N ago" display (plan line 262). */
        val savedAtMs: Long,
        /** Non-null when the draft was opened from an existing entity (edit mode). */
        val entityId: String?,
    )

    /**
     * Supported autosave form types.
     *
     * [storageKey] is written to the `draft_type` column and must never change
     * once shipped — it is part of the on-disk schema contract.
     */
    enum class DraftType(val storageKey: String) {
        TICKET("ticket"),
        CUSTOMER("customer"),
        SMS("sms"),
    }

    // ------------------------------------------------------------------
    // Private helpers
    // ------------------------------------------------------------------

    private fun userIdString(): String? {
        val id = authPreferences.userId
        return if (id != 0L) id.toString() else null
    }

    private fun DraftEntity.toDraft(): Draft = Draft(
        type = DraftType.entries.first { it.storageKey == draftType },
        payloadJson = payloadJson,
        savedAtMs = savedAtMs,
        entityId = entityId,
    )

    // ------------------------------------------------------------------
    // Test factory
    // ------------------------------------------------------------------

    companion object {
        /**
         * Creates a [DraftStore]-equivalent for host-side unit tests.
         *
         * Returns a [TestDraftStore] that accepts a plain [DraftDao] and a
         * [userIdProvider] lambda — no Android [android.content.Context]
         * or real [AuthPreferences] is needed.
         *
         * **Not for production use.**
         */
        internal fun forTesting(dao: DraftDao, userIdProvider: () -> Long): TestDraftStore =
            TestDraftStore(dao, userIdProvider)
    }
}

// ---------------------------------------------------------------------------
// Package-internal test helper — avoids AuthPreferences in unit tests
// ---------------------------------------------------------------------------

/**
 * Thin wrapper around [DraftStore]'s core logic used by [DraftStoreTest].
 *
 * Duplicates the save/load/discard/prune/observeAll logic using only [DraftDao]
 * and a `() -> Long` user-ID supplier so no Android [android.content.Context]
 * is required.  All sanitisation is delegated to [sanitiseDraftPayload].
 */
internal class TestDraftStore(
    private val dao: DraftDao,
    private val userIdProvider: () -> Long,
) {
    private fun userIdString(): String? {
        val id = userIdProvider()
        return if (id != 0L) id.toString() else null
    }

    suspend fun save(
        type: DraftStore.DraftType,
        payloadJson: String,
        entityId: String? = null,
    ) {
        val userId = userIdString() ?: return
        val sanitised = sanitiseDraftPayload(payloadJson)
        dao.upsert(
            DraftEntity(
                userId = userId,
                draftType = type.storageKey,
                payloadJson = sanitised,
                savedAtMs = System.currentTimeMillis(),
                entityId = entityId,
            )
        )
    }

    suspend fun load(type: DraftStore.DraftType): DraftStore.Draft? {
        val userId = userIdString() ?: return null
        return dao.getForType(userId, type.storageKey)?.toDraft()
    }

    suspend fun discard(type: DraftStore.DraftType) {
        val userId = userIdString() ?: return
        dao.deleteForType(userId, type.storageKey)
    }

    suspend fun pruneOlderThanDays(days: Int = 30): Int {
        val cutoffMs = System.currentTimeMillis() - TimeUnit.DAYS.toMillis(days.toLong())
        return dao.deleteOlderThan(cutoffMs)
    }

    fun observeAll(): Flow<List<DraftStore.Draft>> {
        val userId = userIdString() ?: return flowOf(emptyList())
        return dao.observeAllForUser(userId).map { list -> list.map { it.toDraft() } }
    }

    private fun DraftEntity.toDraft(): DraftStore.Draft = DraftStore.Draft(
        type = DraftStore.DraftType.entries.first { it.storageKey == draftType },
        payloadJson = payloadJson,
        savedAtMs = savedAtMs,
        entityId = entityId,
    )
}

// ---------------------------------------------------------------------------
// Package-internal sanitisation function — callable from both DraftStore and tests
// ---------------------------------------------------------------------------

/**
 * Strips sensitive JSON string-value entries from [raw].
 *
 * Matches keys (case-insensitive): `password`, `pin`, `totp`, `secret`,
 * `backup_code`.  Only string values are matched (`"key":"value"` pairs).
 *
 * A Timber.w is emitted for each unique sensitive key found so that ViewModel
 * authors are alerted during development.
 */
internal fun sanitiseDraftPayload(raw: String): String {
    val sensitiveKeys = listOf("password", "pin", "totp", "secret", "backup_code")
    val found = sensitiveKeys.filter { key ->
        raw.contains("\"$key\"", ignoreCase = true)
    }
    if (found.isEmpty()) return raw

    Timber.w(
        "DraftStore: sensitive key(s) found in draft payload and stripped: %s. " +
            "Callers should not serialise these fields.",
        found.joinToString(),
    )

    // Remove  "key" : "value"  entries (string values only).
    // Trailing comma + optional whitespace consumed greedily.
    val pattern = Regex(
        """(?i)"(password|pin|totp|secret|backup_code)"\s*:\s*"[^"]*",?\s*""",
    )
    return pattern.replace(raw, "")
}
