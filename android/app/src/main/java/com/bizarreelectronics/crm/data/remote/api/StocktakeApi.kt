package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.StocktakeCommitRequest
import com.bizarreelectronics.crm.data.remote.dto.StocktakeCreateRequest
import com.bizarreelectronics.crm.data.remote.dto.StocktakeListItem
import com.bizarreelectronics.crm.data.remote.dto.StocktakeSessionData
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query

/**
 * §60 Inventory Stocktake — remote endpoints.
 *
 * Server routes (mounted at /api/v1/stocktake):
 *   GET  /stocktake          — list sessions, most recent first
 *   POST /stocktake          — open a new count session
 *   GET  /stocktake/:id      — session + counts + variance summary
 *   POST /stocktake/:id/counts   — UPSERT a single item count (scanner)
 *   POST /stocktake/:id/commit   — apply variance + close session
 *   POST /stocktake/:id/cancel   — abandon session (no stock change)
 *
 * Legacy offline-only paths kept for backward compat:
 *   POST /inventory/stocktake/start   — NOT on server; 404-tolerant
 *   POST /inventory/stocktake/commit  — NOT on server; 404-tolerant
 */
interface StocktakeApi {

    // ── §6.6 Sessions list ────────────────────────────────────────────────────

    /**
     * List all stocktake sessions (open + recent), most recent first.
     * Optional [status] filter: "open" | "committed" | "cancelled".
     * Returns a list of [StocktakeListItem].
     */
    @GET("stocktake")
    suspend fun listSessions(
        @Query("status") status: String? = null,
    ): ApiResponse<List<StocktakeListItem>>

    /**
     * Open a new count session.
     * [name] is required (max 120 chars); [location] and [notes] optional.
     * Returns the newly created [StocktakeListItem] with its server-assigned id.
     */
    @POST("stocktake")
    suspend fun createSession(
        @Body request: StocktakeCreateRequest,
    ): ApiResponse<StocktakeListItem>

    // ── Legacy offline paths (404-tolerant, used by StocktakeViewModel) ───────

    /**
     * Notify the server that a new stocktake session has started.
     * Returns a server-assigned session ID (used for multi-scanner sync, §60.3).
     * 404-tolerant — offline mode silently skips this call.
     */
    @POST("inventory/stocktake/start")
    suspend fun startSession(): ApiResponse<StocktakeSessionData>

    /**
     * Commit final count lines to the server. The server creates stock-adjustment
     * records and returns a summary. 404-tolerant — if the endpoint is absent,
     * the client applies adjustments locally via [InventoryApi.adjustStock] and
     * queues them in the SyncQueue.
     */
    @POST("inventory/stocktake/commit")
    suspend fun commitSession(@Body request: StocktakeCommitRequest): ApiResponse<Unit>

    // ── Per-session actions ───────────────────────────────────────────────────

    /**
     * Commit a session by server id — apply all counted variances as stock
     * movements and close the session.
     */
    @POST("stocktake/{id}/commit")
    suspend fun commitById(@Path("id") id: Int): ApiResponse<Unit>

    /**
     * Cancel an open session — no stock changes applied.
     */
    @POST("stocktake/{id}/cancel")
    suspend fun cancelById(@Path("id") id: Int): ApiResponse<Unit>
}
