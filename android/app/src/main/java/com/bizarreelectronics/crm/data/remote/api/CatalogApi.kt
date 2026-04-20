package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.*
import retrofit2.http.GET
import retrofit2.http.Query

interface CatalogApi {
    @GET("catalog/manufacturers")
    suspend fun getManufacturers(): ApiResponse<List<ManufacturerItem>>

    @GET("catalog/devices")
    suspend fun searchDevices(
        @Query("q") query: String? = null,
        @Query("category") category: String? = null,
        @Query("manufacturer_id") manufacturerId: Int? = null,
        @Query("popular") popular: Int? = null,
        @Query("limit") limit: Int = 100
    ): ApiResponse<List<DeviceModelItem>>
}
