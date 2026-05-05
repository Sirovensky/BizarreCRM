package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import retrofit2.http.GET
import retrofit2.http.Query

interface SearchApi {

    @GET("search")
    suspend fun globalSearch(
        @Query("q") query: String
    ): ApiResponse<Map<String, @JvmSuppressWildcards Any>>
}
