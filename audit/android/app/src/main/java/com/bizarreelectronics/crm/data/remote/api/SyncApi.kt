package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.google.gson.annotations.SerializedName
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Query

/**
 * Plan §20.6 L2121 — Delta-sync and conflict-resolution endpoints.
 *
 * ## Delta sync
 *
 * [getDelta] fetches the changeset that occurred after `since` (epoch-ms ISO-8601
 * timestamp). The server returns up to `limit` items per page and an opaque `cursor`
 * for the next page. When the response's `cursor` is null the client has consumed
 * the full delta window and should persist `last_updated_at` for the next sync.
 *
 * The server may return `tombstones` — entity IDs that were deleted server-side and
 * should be removed from Room. [DeltaSyncer] handles both upserts and tombstones.
 *
 * ## Conflict resolution
 *
 * [resolveConflict] posts the user's chosen resolution for a conflict that could not
 * be auto-merged by [ConflictResolver]. The server applies the authoritative merge
 * and returns the resolved entity state.
 */
interface SyncApi {

    /**
     * Fetch the delta changeset since [since].
     *
     * @param since  ISO-8601 timestamp (or epoch-ms string). The server returns all
     *   changes that occurred after this point.
     * @param cursor Opaque continuation token from a previous response. Null on the
     *   first page of a delta window.
     * @param limit  Maximum entries to return per page. Defaults to 500 on the server.
     */
    @GET("sync/delta")
    suspend fun getDelta(
        @Query("since") since: String,
        @Query("cursor") cursor: String? = null,
        @Query("limit") limit: Int = 500,
    ): ApiResponse<DeltaPage>

    /**
     * Post the user's chosen conflict resolution for a pending [ConflictRecord].
     *
     * The server merges the resolution, persists the winning version, and returns
     * the authoritative entity state so the client can upsert it immediately.
     */
    @POST("sync/conflicts/resolve")
    suspend fun resolveConflict(@Body resolution: ConflictResolutionRequest): ApiResponse<ResolvedEntity>
}

// ─── DTO shapes ───────────────────────────────────────────────────────────────

/**
 * One page of delta changes returned by [SyncApi.getDelta].
 *
 * @property upserts Entity payloads to insert/update in Room.
 * @property tombstones Entity references to delete from Room.
 * @property cursor Opaque token for the next page. Null when this is the last page.
 * @property serverExhausted True when the server confirms no further pages remain.
 * @property since The effective `since` timestamp echoed back by the server (for
 *   bookkeeping — callers should persist this as the new `last_updated_at`).
 */
data class DeltaPage(
    val upserts: List<DeltaUpsert> = emptyList(),
    val tombstones: List<DeltaTombstone> = emptyList(),
    val cursor: String? = null,
    @SerializedName("server_exhausted")
    val serverExhausted: Boolean = false,
    val since: String? = null,
)

/** A single entity to upsert during delta sync. */
data class DeltaUpsert(
    /** Logical entity type: `"ticket"`, `"customer"`, `"inventory"`, etc. */
    @SerializedName("entity_type")
    val entityType: String,
    /** Server-assigned entity id. */
    val id: Long,
    /** Full JSON payload — parsed entity-specifically by [DeltaSyncer]. */
    val payload: String,
    /** ISO-8601 timestamp of the last server-side change to this entity. */
    @SerializedName("updated_at")
    val updatedAt: String,
)

/** A single entity deletion to apply during delta sync (tombstone). */
data class DeltaTombstone(
    @SerializedName("entity_type")
    val entityType: String,
    val id: Long,
)

/** User's resolution choice for a conflict surfaced by [ConflictResolver]. */
data class ConflictResolutionRequest(
    /** Local (queue-level) id of the conflict record being resolved. */
    @SerializedName("conflict_id")
    val conflictId: Long,
    /** Entity type: `"ticket"`, `"customer"`, etc. */
    @SerializedName("entity_type")
    val entityType: String,
    /** Server-assigned entity id. */
    @SerializedName("entity_id")
    val entityId: Long,
    /**
     * Field-level resolution choices.
     * Key = field name; value = `"mine"` | `"theirs"` | `"merge"` (for list fields).
     */
    val resolutions: Map<String, String>,
    /**
     * When `resolutions` for a field is `"mine"`, this map holds the client's
     * value for that field (serialised as JSON string). Optional — server uses
     * the value it already holds for `"theirs"` resolutions.
     */
    @SerializedName("my_values")
    val myValues: Map<String, String> = emptyMap(),
)

/** Server's authoritative entity state after conflict resolution. */
data class ResolvedEntity(
    @SerializedName("entity_type")
    val entityType: String,
    val id: Long,
    /** Full JSON of the resolved entity for [DeltaSyncer] to upsert. */
    val payload: String,
    @SerializedName("updated_at")
    val updatedAt: String,
)
