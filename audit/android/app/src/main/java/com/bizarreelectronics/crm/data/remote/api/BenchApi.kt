package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.TicketDetail
import com.bizarreelectronics.crm.data.remote.dto.TicketListData
import retrofit2.http.GET

/**
 * BenchApi — §4.9 L756
 *
 * Retrofit interface for bench-workflow endpoints. Exposes the current
 * technician's active bench tickets. 404-tolerant: callers catch
 * [retrofit2.HttpException] with code 404 and fall back to an empty list.
 *
 * iOS parallel: same endpoints are consumed by the iOS Swift client via
 * URLSession; request/response shapes are identical.
 *
 * Server endpoints (packages/server/src/routes/tickets.ts):
 *   GET /api/v1/tickets?assignedToMe=true&status=in_repair
 */
interface BenchApi {

    /**
     * Fetch the authenticated technician's current bench tickets.
     *
     * @return [ApiResponse] wrapping [TicketListData] with `tickets` list.
     *         Returns 404 when the server build pre-dates this endpoint; callers
     *         should fall back to an empty list in that case.
     */
    @GET("tickets?assignedToMe=true&status=in_repair")
    suspend fun myBench(): ApiResponse<TicketListData>
}
