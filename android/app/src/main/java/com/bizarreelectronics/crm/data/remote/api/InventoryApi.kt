package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.AdjustStockRequest
import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.CreateInventoryRequest
import com.bizarreelectronics.crm.data.remote.dto.InventoryDetailData
import com.bizarreelectronics.crm.data.remote.dto.InventoryListData
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.PUT
import retrofit2.http.Path
import retrofit2.http.QueryMap

interface InventoryApi {

    @GET("inventory")
    suspend fun getItems(@QueryMap filters: Map<String, String> = emptyMap()): ApiResponse<InventoryListData>

    @GET("inventory/{id}")
    suspend fun getItem(@Path("id") id: Long): ApiResponse<InventoryDetailData>

    @POST("inventory")
    suspend fun createItem(@Body request: CreateInventoryRequest): ApiResponse<InventoryDetailData>

    @PUT("inventory/{id}")
    suspend fun updateItem(
        @Path("id") id: Long,
        @Body request: CreateInventoryRequest,
    ): ApiResponse<InventoryDetailData>

    @POST("inventory/{id}/adjust-stock")
    suspend fun adjustStock(@Path("id") id: Long, @Body request: AdjustStockRequest): ApiResponse<Unit>

    @GET("inventory/barcode/{code}")
    suspend fun lookupBarcode(@Path("code") code: String): ApiResponse<InventoryDetailData>
}
