package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.PurchaseOrderCreateRequest
import com.bizarreelectronics.crm.data.remote.dto.PurchaseOrderDetailData
import com.bizarreelectronics.crm.data.remote.dto.PurchaseOrderListData
import com.bizarreelectronics.crm.data.remote.dto.PurchaseOrderReceiveRequest
import com.bizarreelectronics.crm.data.remote.dto.PurchaseOrderUpdateRequest
import com.bizarreelectronics.crm.data.remote.dto.PurchaseOrderRow
import com.bizarreelectronics.crm.data.remote.dto.SupplierRow
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.PUT
import retrofit2.http.Path
import retrofit2.http.Query

interface PurchaseOrderApi {

    // GET /inventory/purchase-orders/list?page=&pagesize=&status=
    @GET("inventory/purchase-orders/list")
    suspend fun listPurchaseOrders(
        @Query("page") page: Int = 1,
        @Query("pagesize") pageSize: Int = 20,
        @Query("status") status: String? = null,
    ): ApiResponse<PurchaseOrderListData>

    // POST /inventory/purchase-orders
    @POST("inventory/purchase-orders")
    suspend fun createPurchaseOrder(
        @Body request: PurchaseOrderCreateRequest,
    ): ApiResponse<PurchaseOrderRow>

    // GET /inventory/purchase-orders/:id
    @GET("inventory/purchase-orders/{id}")
    suspend fun getPurchaseOrder(
        @Path("id") id: Long,
    ): ApiResponse<PurchaseOrderDetailData>

    // POST /inventory/purchase-orders/:id/receive
    @POST("inventory/purchase-orders/{id}/receive")
    suspend fun receivePurchaseOrder(
        @Path("id") id: Long,
        @Body request: PurchaseOrderReceiveRequest,
    ): ApiResponse<PurchaseOrderRow>

    // PUT /inventory/purchase-orders/:id  (status transitions, cancel, etc.)
    @PUT("inventory/purchase-orders/{id}")
    suspend fun updatePurchaseOrder(
        @Path("id") id: Long,
        @Body request: PurchaseOrderUpdateRequest,
    ): ApiResponse<PurchaseOrderRow>

    // GET /inventory/suppliers/list  — server returns data: [ {id, name, ...}, ... ]
    @GET("inventory/suppliers/list")
    suspend fun listSuppliers(
        @Query("active_only") activeOnly: String? = "true",
    ): ApiResponse<List<SupplierRow>>
}
