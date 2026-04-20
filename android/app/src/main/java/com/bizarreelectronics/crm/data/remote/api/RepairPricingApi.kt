package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.*
import retrofit2.http.GET
import retrofit2.http.Query

interface RepairPricingApi {
    @GET("repair-pricing/services")
    suspend fun getServices(
        @Query("category") category: String? = null
    ): ApiResponse<List<RepairServiceItem>>

    @GET("repair-pricing/lookup")
    suspend fun pricingLookup(
        @Query("device_model_id") deviceModelId: Int,
        @Query("repair_service_id") serviceId: Int
    ): ApiResponse<RepairPriceLookup>
}
