package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.CreateEstimateRequest
import com.bizarreelectronics.crm.data.remote.dto.EstimateDetail
import com.bizarreelectronics.crm.data.remote.dto.EstimateListData
import com.bizarreelectronics.crm.data.remote.dto.EstimatePageResponse
import com.bizarreelectronics.crm.data.remote.dto.UpdateEstimateRequest
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.PUT
import retrofit2.http.Path
import retrofit2.http.Query
import retrofit2.http.QueryMap

/** Minimal version snapshot returned by GET /estimates/:id/versions (404-tolerant). */
data class EstimateVersion(
    val versionNumber: Int,
    val createdAt: String,
    val createdBy: String?,
    val total: Long,
    val status: String,
)

interface EstimateApi {

    @GET("estimates")
    suspend fun getEstimates(@QueryMap filters: Map<String, String> = emptyMap()): ApiResponse<EstimateListData>

    /**
     * Cursor-based page fetch for offline-first paging (plan:L1325).
     * When [cursor] is null the server returns the first page.
     * On servers that do not yet support cursor the response is treated as a
     * final page ([EstimatePageResponse.cursor] = null).
     */
    @GET("estimates")
    suspend fun getEstimatePage(
        @Query("cursor") cursor: String?,
        @Query("limit") limit: Int = 50,
        @QueryMap filters: Map<String, String> = emptyMap(),
    ): ApiResponse<EstimatePageResponse>

    @GET("estimates/{id}")
    suspend fun getEstimate(@Path("id") id: Long): ApiResponse<EstimateDetail>

    @POST("estimates")
    suspend fun createEstimate(
        @Header("Idempotency-Key") idempotencyKey: String,
        @Body request: CreateEstimateRequest,
    ): ApiResponse<EstimateDetail>

    @PUT("estimates/{id}")
    suspend fun updateEstimate(@Path("id") id: Long, @Body request: UpdateEstimateRequest): ApiResponse<EstimateDetail>

    @DELETE("estimates/{id}")
    suspend fun deleteEstimate(@Path("id") id: Long): ApiResponse<Unit>

    @POST("estimates/{id}/convert")
    suspend fun convertToTicket(@Path("id") id: Long): ApiResponse<@JvmSuppressWildcards Map<String, Any>>

    @POST("estimates/{id}/send")
    suspend fun sendEstimate(@Path("id") id: Long, @Body request: Map<String, @JvmSuppressWildcards Any>): ApiResponse<Unit>

    /** POST /estimates/:id/approve — 404 tolerated (server stub not yet deployed). */
    @POST("estimates/{id}/approve")
    suspend fun approveEstimate(@Path("id") id: Long): ApiResponse<Unit>

    /**
     * POST /estimates/:id/reject — requires a non-blank [reason] body field.
     * 404 tolerated.
     */
    @POST("estimates/{id}/reject")
    suspend fun rejectEstimate(
        @Path("id") id: Long,
        @Body body: Map<String, @JvmSuppressWildcards Any>,
    ): ApiResponse<Unit>

    /**
     * POST /estimates/:id/convert-to-invoice — 404 tolerated.
     * Returns the new invoice id in data.invoiceId when available.
     */
    @POST("estimates/{id}/convert-to-invoice")
    suspend fun convertToInvoice(@Path("id") id: Long): ApiResponse<@JvmSuppressWildcards Map<String, Any>>

    /**
     * PATCH /estimates/:id — partial update; used to mark as expired via {status: "expired"}.
     * 404 tolerated; call-site falls back to POST .../expire.
     */
    @PATCH("estimates/{id}")
    suspend fun patchEstimate(
        @Path("id") id: Long,
        @Body body: Map<String, @JvmSuppressWildcards Any>,
    ): ApiResponse<EstimateDetail>

    /**
     * POST /estimates/:id/expire — alternative expire action for servers without PATCH.
     * 404 tolerated; caller wraps in runCatching.
     */
    @POST("estimates/{id}/expire")
    suspend fun expireEstimate(@Path("id") id: Long): ApiResponse<Unit>

    /**
     * GET /estimates/:id/versions — returns revision history.
     * 404 tolerated; call-site handles with emptyList().
     */
    @GET("estimates/{id}/versions")
    suspend fun getVersions(@Path("id") id: Long): ApiResponse<List<EstimateVersion>>
}
