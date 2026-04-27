package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.*
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Query

/**
 * Server: GET /catalog/categories — distinct device categories with display
 * labels + counts. Refreshed on app start so chip-row pickers stay in sync
 * with the tenant catalog (no hardcoded list).
 */
data class DeviceCategoryItem(
    val slug: String,
    val label: String,
    val count: Int = 0,
)

interface CatalogApi {
    @GET("catalog/manufacturers")
    suspend fun getManufacturers(): ApiResponse<List<ManufacturerItem>>

    @GET("catalog/categories")
    suspend fun getCategories(): ApiResponse<List<DeviceCategoryItem>>

    @GET("catalog/devices")
    suspend fun searchDevices(
        @Query("q") query: String? = null,
        @Query("category") category: String? = null,
        @Query("manufacturer_id") manufacturerId: Int? = null,
        @Query("popular") popular: Int? = null,
        @Query("limit") limit: Int = 100
    ): ApiResponse<List<DeviceModelItem>>

    /** Admin-only: add a new device model to the catalog (POST /catalog/devices). */
    @POST("catalog/devices")
    suspend fun addDevice(@Body body: AddDeviceModelRequest): ApiResponse<DeviceModelItem>
}
