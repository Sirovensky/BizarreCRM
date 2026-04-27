package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.StocktakeCancelData
import com.bizarreelectronics.crm.data.remote.dto.StocktakeCommitData
import com.bizarreelectronics.crm.data.remote.dto.StocktakeCountRequest
import com.bizarreelectronics.crm.data.remote.dto.StocktakeCountResult
import com.bizarreelectronics.crm.data.remote.dto.StocktakeOpenRequest
import com.bizarreelectronics.crm.data.remote.dto.StocktakeRow
import com.bizarreelectronics.crm.data.remote.dto.StocktakeSessionDetail
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query

/**
 * §60 — Stocktake API.
 *
 * Server: /api/v1/stocktake (mounted in index.ts from stocktake.routes.ts).
 *
 * Lifecycle:
 *   POST /stocktake                 → open a session
 *   GET  /stocktake                 → list sessions
 *   GET  /stocktake/:id             → session + counts + variance summary
 *   POST /stocktake/:id/counts      → UPSERT a per-item scan
 *   POST /stocktake/:id/commit      → apply variance + close session
 *   POST /stocktake/:id/cancel      → abandon session (no stock change)
 */
interface StocktakeApi {

    /** List sessions (most recent first, max 200). Optional status filter. */
    @GET("stocktake")
    suspend fun listSessions(
        @Query("status") status: String? = null,
    ): ApiResponse<List<StocktakeRow>>

    /** Open a new stocktake session (admin/manager only). */
    @POST("stocktake")
    suspend fun openSession(@Body request: StocktakeOpenRequest): ApiResponse<StocktakeRow>

    /** Fetch a session with all counts and a variance summary. */
    @GET("stocktake/{id}")
    suspend fun getSession(@Path("id") id: Long): ApiResponse<StocktakeSessionDetail>

    /**
     * UPSERT a single item count.
     * Re-scanning the same SKU replaces the prior row (server ON CONFLICT DO UPDATE).
     */
    @POST("stocktake/{id}/counts")
    suspend fun submitCount(
        @Path("id") sessionId: Long,
        @Body request: StocktakeCountRequest,
    ): ApiResponse<StocktakeCountResult>

    /** Apply variance to inventory_items and close the session (admin/manager only). */
    @POST("stocktake/{id}/commit")
    suspend fun commitSession(@Path("id") id: Long): ApiResponse<StocktakeCommitData>

    /** Abandon the session without applying any stock changes (admin/manager only). */
    @POST("stocktake/{id}/cancel")
    suspend fun cancelSession(@Path("id") id: Long): ApiResponse<StocktakeCancelData>
}
