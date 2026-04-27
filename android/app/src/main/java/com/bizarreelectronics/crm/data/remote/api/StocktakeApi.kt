package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.StocktakeCommitRequest
import com.bizarreelectronics.crm.data.remote.dto.StocktakeSessionData
import retrofit2.http.Body
import retrofit2.http.POST

/**
 * §60 Inventory Stocktake — remote endpoints.
 *
 * Both endpoints are 404-tolerant: callers catch HttpException(404) and fall
 * back to the offline-only path. The server routes are:
 *   POST /api/v1/inventory/stocktake/start
 *   POST /api/v1/inventory/stocktake/commit
 *
 * These routes do not yet exist on the server (server-blocked, §60.1).
 * The client-side flow works fully offline; sync happens on commit when online.
 */
interface StocktakeApi {

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
}
