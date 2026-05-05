package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.RmaCreatedData
import com.bizarreelectronics.crm.data.remote.dto.RmaCreateRequest
import com.bizarreelectronics.crm.data.remote.dto.RmaDetailData
import com.bizarreelectronics.crm.data.remote.dto.RmaRow
import com.bizarreelectronics.crm.data.remote.dto.RmaStatusData
import com.bizarreelectronics.crm.data.remote.dto.RmaStatusRequest
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query

/**
 * §61.5 Vendor Return (RMA) API.
 *
 * Server routes (registered in index.ts as /api/v1/rma):
 *   GET    /rma           — list, paginated, permission: inventory.adjust
 *   GET    /rma/:id       — single RMA with items, permission: inventory.adjust
 *   POST   /rma           — create, permission: inventory.edit
 *   PATCH  /rma/:id/status — advance state machine, permission: inventory.edit
 *
 * Status state machine: pending → approved|declined; approved → shipped|declined|pending;
 *   shipped → received|pending; received → resolved|pending; resolved/declined = terminal.
 *
 * On 'received' the server atomically restores inventory stock for linked items.
 * Non-admin callers have supplier_id, supplier_name, tracking_number, and notes
 * redacted from list/detail responses.
 */
interface RmaApi {

    // GET /rma?page=&per_page=&status=
    @GET("rma")
    suspend fun listRmas(
        @Query("page") page: Int = 1,
        @Query("per_page") perPage: Int = 30,
        @Query("status") status: String? = null,
    ): ApiResponse<List<RmaRow>>

    // GET /rma/:id  — returns { ...rmaRow, items: [] }
    @GET("rma/{id}")
    suspend fun getRma(
        @Path("id") id: Long,
    ): ApiResponse<RmaDetailData>

    // POST /rma
    @POST("rma")
    suspend fun createRma(
        @Body request: RmaCreateRequest,
    ): ApiResponse<RmaCreatedData>

    // PATCH /rma/:id/status
    @PATCH("rma/{id}/status")
    suspend fun updateRmaStatus(
        @Path("id") id: Long,
        @Body request: RmaStatusRequest,
    ): ApiResponse<RmaStatusData>
}
