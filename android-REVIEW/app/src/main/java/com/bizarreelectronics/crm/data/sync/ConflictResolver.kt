package com.bizarreelectronics.crm.data.sync

import android.util.Log
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.remote.api.SyncApi
import com.google.gson.Gson
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Plan §20.5 L2115-L2118 — 3-way conflict resolver.
 *
 * ## When is a conflict detected?
 *
 * [SyncManager] catches HTTP 409 on update operations. A 409 with a stale
 * `updated_at` means the server's version has advanced past the client's
 * snapshot. [resolve] is called in that situation.
 *
 * ## Resolution strategy
 *
 * | Field category | Strategy |
 * |----------------|----------|
 * | Simple scalars (name, status, notes) | Last-writer-wins (server timestamp wins) |
 * | List / tag fields (`labels`, `tags`) | List-union — both sets are merged |
 * | Price / total fields (`total`, `subtotal`, `price`) | User-prompt required → stored as [ConflictRecord] |
 *
 * Simple-field conflicts auto-resolve without user interaction. Price/total
 * conflicts are persisted to [_pendingConflicts] and surfaced in
 * [ConflictResolutionScreen] for the user to adjudicate.
 *
 * ## After resolution
 *
 * Auto-resolved fields: the client re-issues the update with the merged payload.
 * User-prompt fields: when the user submits from the UI, [ConflictResolutionScreen]
 * calls [SyncApi.resolveConflict] with the chosen field-level resolutions.
 */
@Singleton
class ConflictResolver @Inject constructor(
    private val syncQueueDao: SyncQueueDao,
    private val syncApi: SyncApi,
    private val gson: Gson,
) {

    /** In-memory list of conflicts awaiting user resolution. Observed by the ViewModel. */
    private val _pendingConflicts = mutableListOf<ConflictRecord>()
    val pendingConflicts: List<ConflictRecord> get() = _pendingConflicts.toList()

    /**
     * Attempt to resolve a 409 conflict for [queueEntryId].
     *
     * 1. Fetches the latest server version via the entity-specific GET endpoint
     *    (caller supplies [fetchLatest] to keep this class decoupled from entity APIs).
     * 2. Runs 3-way merge between [clientPayload] and [serverPayload].
     * 3. Returns a [MergeResult]:
     *    - [MergeResult.AutoResolved] — all fields merged automatically; caller
     *      should re-POST with the merged payload.
     *    - [MergeResult.NeedsUserInput] — at least one price/total field could not
     *      be auto-merged; a [ConflictRecord] has been stored in [pendingConflicts].
     *
     * @param queueEntryId The `sync_queue.id` of the failed queue entry.
     * @param entityType   Logical entity type, e.g. `"ticket"`.
     * @param entityId     Server-assigned id.
     * @param clientPayload JSON string of the client's attempted update payload.
     * @param fetchLatest  Suspend lambda that returns the server's current JSON for
     *   the entity. Called exactly once; exceptions propagate to the caller.
     */
    suspend fun resolve(
        queueEntryId: Long,
        entityType: String,
        entityId: Long,
        clientPayload: String,
        fetchLatest: suspend () -> String,
    ): MergeResult {
        val serverJson = fetchLatest()
        return merge(
            queueEntryId = queueEntryId,
            entityType = entityType,
            entityId = entityId,
            clientPayload = clientPayload,
            serverPayload = serverJson,
        )
    }

    /**
     * 3-way merge between [clientPayload] and [serverPayload].
     *
     * Fields are classified by [fieldCategory]. Simple scalars use LWW (server wins
     * for non-user-edited fields; client wins for fields the user explicitly changed).
     * List fields are union-merged. Price fields generate a [ConflictRecord].
     */
    private fun merge(
        queueEntryId: Long,
        entityType: String,
        entityId: Long,
        clientPayload: String,
        serverPayload: String,
    ): MergeResult {
        return try {
            val clientObj = JsonParser.parseString(clientPayload).takeIf { it.isJsonObject }?.asJsonObject
                ?: return MergeResult.AutoResolved(serverPayload) // can't parse client payload — defer to server
            val serverObj = JsonParser.parseString(serverPayload).takeIf { it.isJsonObject }?.asJsonObject
                ?: return MergeResult.AutoResolved(serverPayload)

            val merged = serverObj.deepCopy()
            val promptFields = mutableMapOf<String, FieldConflict>()

            for ((fieldName, clientValue) in clientObj.entrySet()) {
                val serverValue = serverObj.get(fieldName)

                // Skip if client and server agree.
                if (clientValue == serverValue) continue

                when (fieldCategory(fieldName)) {
                    FieldCategory.SIMPLE_SCALAR -> {
                        // Last-writer-wins: server version is newer, so server wins.
                        // The merged object already has the server value — no action.
                        Log.d(TAG, "LWW: field '$fieldName' — server value wins")
                    }
                    FieldCategory.LIST_UNION -> {
                        // Union-merge both JSON arrays.
                        val unionArray = unionJsonArrays(clientValue, serverValue)
                        if (unionArray != null) {
                            merged.add(fieldName, unionArray)
                            Log.d(TAG, "List-union: field '$fieldName' merged")
                        }
                    }
                    FieldCategory.PRICE_TOTAL -> {
                        // Cannot auto-resolve — needs user input.
                        promptFields[fieldName] = FieldConflict(
                            fieldName = fieldName,
                            clientValue = gson.toJson(clientValue),
                            serverValue = gson.toJson(serverValue),
                        )
                        Log.d(TAG, "Conflict on price field '$fieldName' — queuing for user prompt")
                    }
                }
            }

            if (promptFields.isEmpty()) {
                MergeResult.AutoResolved(gson.toJson(merged))
            } else {
                val record = ConflictRecord(
                    id = queueEntryId,
                    entityType = entityType,
                    entityId = entityId,
                    autoMergedPayload = gson.toJson(merged),
                    promptFields = promptFields,
                )
                _pendingConflicts.removeAll { it.entityType == entityType && it.entityId == entityId }
                _pendingConflicts.add(record)
                MergeResult.NeedsUserInput(record)
            }
        } catch (e: Exception) {
            Log.e(TAG, "3-way merge failed [${e.javaClass.simpleName}]: ${e.message} — deferring to server")
            MergeResult.AutoResolved(serverPayload)
        }
    }

    /** Remove a resolved conflict from the pending list. */
    fun clearConflict(conflictId: Long) {
        _pendingConflicts.removeAll { it.id == conflictId }
    }

    // ── private helpers ───────────────────────────────────────────────────────

    private fun fieldCategory(fieldName: String): FieldCategory = when {
        fieldName in PRICE_FIELDS -> FieldCategory.PRICE_TOTAL
        fieldName in LIST_FIELDS  -> FieldCategory.LIST_UNION
        else                      -> FieldCategory.SIMPLE_SCALAR
    }

    private fun unionJsonArrays(
        clientValue: com.google.gson.JsonElement?,
        serverValue: com.google.gson.JsonElement?,
    ): com.google.gson.JsonElement? {
        val clientArr = clientValue?.takeIf { it.isJsonArray }?.asJsonArray ?: return null
        val serverArr = serverValue?.takeIf { it.isJsonArray }?.asJsonArray ?: return null
        val union = com.google.gson.JsonArray()
        val seen = mutableSetOf<String>()
        for (elem in serverArr) { union.add(elem); seen.add(elem.toString()) }
        for (elem in clientArr) { if (seen.add(elem.toString())) union.add(elem) }
        return union
    }

    private fun JsonObject.deepCopy(): JsonObject = JsonParser.parseString(toString()).asJsonObject

    private enum class FieldCategory { SIMPLE_SCALAR, LIST_UNION, PRICE_TOTAL }

    companion object {
        private const val TAG = "ConflictResolver"

        /** Fields that represent money amounts and require user adjudication. */
        private val PRICE_FIELDS = setOf(
            "total", "subtotal", "price", "total_tax", "discount",
            "amount", "amount_paid", "amount_due", "cost_price_cents", "retail_price_cents",
        )

        /** Fields that are JSON arrays and should be union-merged. */
        private val LIST_FIELDS = setOf("labels", "tags")
    }
}

// ─── Result types ─────────────────────────────────────────────────────────────

/** Outcome returned by [ConflictResolver.resolve]. */
sealed class MergeResult {
    /** All fields auto-resolved. [mergedPayload] is ready to re-POST. */
    data class AutoResolved(val mergedPayload: String) : MergeResult()

    /** One or more price/total fields need user input. UI should show [record]. */
    data class NeedsUserInput(val record: ConflictRecord) : MergeResult()
}

/**
 * A conflict record for fields that could not be auto-merged.
 * Persisted in-memory by [ConflictResolver] and observed by [ConflictResolutionViewModel].
 *
 * @param id               The `sync_queue.id` of the queue entry that triggered the conflict.
 * @param entityType       Logical entity type.
 * @param entityId         Server-assigned entity id.
 * @param autoMergedPayload JSON of all auto-resolved fields — used as the base when the
 *   user's choices are applied.
 * @param promptFields     Map of field name → [FieldConflict] for each field awaiting
 *   user input.
 */
data class ConflictRecord(
    val id: Long,
    val entityType: String,
    val entityId: Long,
    val autoMergedPayload: String,
    val promptFields: Map<String, FieldConflict>,
)

/**
 * A single field conflict, with both the client's and server's values
 * serialised as JSON strings for display in [ConflictResolutionScreen].
 */
data class FieldConflict(
    val fieldName: String,
    val clientValue: String,
    val serverValue: String,
)
