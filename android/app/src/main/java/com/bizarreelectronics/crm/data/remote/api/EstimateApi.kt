package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.CreateEstimateRequest
import com.bizarreelectronics.crm.data.remote.dto.EstimateDetail
import com.bizarreelectronics.crm.data.remote.dto.EstimateListData
import com.bizarreelectronics.crm.data.remote.dto.UpdateEstimateRequest
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.PUT
import retrofit2.http.Path
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

    @GET("estimates/{id}")
    suspend fun getEstimate(@Path("id") id: Long): ApiResponse<EstimateDetail>

    @POST("estimates")
    suspend fun createEstimate(@Body request: CreateEstimateRequest): ApiResponse<EstimateDetail>

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
     * GET /estimates/:id/versions — returns revision history.
     * 404 tolerated; call-site handles with emptyList().
     */
    @GET("estimates/{id}/versions")
    suspend fun getVersions(@Path("id") id: Long): ApiResponse<List<EstimateVersion>>
}
