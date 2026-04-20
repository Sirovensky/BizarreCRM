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
}
