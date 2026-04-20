package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import retrofit2.http.GET
import retrofit2.http.QueryMap

interface ReportApi {

    @GET("reports/dashboard")
    suspend fun getDashboard(): ApiResponse<Map<String, @JvmSuppressWildcards Any>>

    @GET("reports/needs-attention")
    suspend fun getNeedsAttention(): ApiResponse<Map<String, @JvmSuppressWildcards Any>>

    @GET("reports/sales")
    suspend fun getSalesReport(
        @QueryMap filters: Map<String, String> = emptyMap()
    ): ApiResponse<Map<String, @JvmSuppressWildcards Any>>
}
