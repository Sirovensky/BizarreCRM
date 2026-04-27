package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.AdjustStockRequest
import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.AutoReorderRequest
import com.bizarreelectronics.crm.data.remote.dto.BinListData
import com.bizarreelectronics.crm.data.remote.dto.CreateInventoryRequest
import com.bizarreelectronics.crm.data.remote.dto.InventoryDetailData
import com.bizarreelectronics.crm.data.remote.dto.InventoryListData
import com.bizarreelectronics.crm.data.remote.dto.MovementPage
import com.bizarreelectronics.crm.data.remote.dto.PhotoListData
import com.bizarreelectronics.crm.data.remote.dto.PriceHistoryData
import com.bizarreelectronics.crm.data.remote.dto.SalesHistoryData
import com.bizarreelectronics.crm.data.remote.dto.SupplierDetailData
import com.bizarreelectronics.crm.data.remote.dto.SupplierListItem
import com.bizarreelectronics.crm.data.remote.dto.PurchaseOrderListData
import com.bizarreelectronics.crm.data.remote.dto.PurchaseOrderDetailData
import com.bizarreelectronics.crm.data.remote.dto.CreatePurchaseOrderRequest
import com.bizarreelectronics.crm.data.remote.dto.UpdatePurchaseOrderRequest
import com.bizarreelectronics.crm.data.remote.dto.ReceivePurchaseOrderRequest
import com.bizarreelectronics.crm.data.remote.dto.TaxClassOption
import com.bizarreelectronics.crm.data.remote.dto.TicketUsageData
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.PUT
import retrofit2.http.Path
import retrofit2.http.Query
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

    // ── L1071: Paginated movement history ───────────────────────────────────
    /** Cursor-based movement history; omit [cursor] for the first page. */
    @GET("inventory/{id}/movements")
    suspend fun getMovements(
        @Path("id") id: Long,
        @Query("cursor") cursor: String? = null,
        @Query("limit") limit: Int = 25,
    ): ApiResponse<MovementPage>

    // ── L1072: Price history ─────────────────────────────────────────────────
    @GET("inventory/{id}/price-history")
    suspend fun getPriceHistory(@Path("id") id: Long): ApiResponse<PriceHistoryData>

    // ── L1073: Sales history ─────────────────────────────────────────────────
    @GET("inventory/{id}/sales-history")
    suspend fun getSalesHistory(
        @Path("id") id: Long,
        @Query("days") days: Int = 30,
    ): ApiResponse<SalesHistoryData>

    // ── L1074: Supplier detail ───────────────────────────────────────────────
    @GET("suppliers/{supplierId}")
    suspend fun getSupplierDetail(@Path("supplierId") supplierId: Long): ApiResponse<SupplierDetailData>

    // ── L1075: Auto-reorder ──────────────────────────────────────────────────
    @PATCH("inventory/{id}/auto-reorder")
    suspend fun setAutoReorder(
        @Path("id") id: Long,
        @Body config: AutoReorderRequest,
    ): ApiResponse<Unit>

    // ── L1076: Bins autocomplete ─────────────────────────────────────────────
    @GET("inventory/bins")
    suspend fun getBins(): ApiResponse<BinListData>

    // ── L1080: Ticket usage ──────────────────────────────────────────────────
    @GET("inventory/{id}/tickets")
    suspend fun getUsageInTickets(
        @Path("id") id: Long,
        @Query("limit") limit: Int = 10,
    ): ApiResponse<TicketUsageData>

    // ── L1082: Tax classes ───────────────────────────────────────────────────
    // Server mounts the tax-classes route under /api/v1/settings
    // (see packages/server/src/routes/settings.routes.ts:657). The previous
    // bare 'tax-classes' path 404s; corrected to 'settings/tax-classes'.
    @GET("settings/tax-classes")
    suspend fun getTaxClasses(): ApiResponse<List<TaxClassOption>>

    // ── L1083: Photos ────────────────────────────────────────────────────────
    @GET("inventory/{id}/photos")
    suspend fun getPhotos(@Path("id") id: Long): ApiResponse<PhotoListData>

    // ── §6.4: Delete (soft-delete; server sets is_active=0) ──────────────────
    @retrofit2.http.DELETE("inventory/{id}")
    suspend fun deleteItem(@Path("id") id: Long): ApiResponse<Unit>

    // ── §6.7: Purchase Orders ────────────────────────────────────────────────
    @GET("inventory/purchase-orders/list")
    suspend fun getPurchaseOrders(
        @Query("page") page: Int = 1,
        @Query("pagesize") pageSize: Int = 20,
        @Query("status") status: String? = null,
    ): ApiResponse<PurchaseOrderListData>

    @GET("inventory/purchase-orders/{id}")
    suspend fun getPurchaseOrder(@Path("id") id: Long): ApiResponse<PurchaseOrderDetailData>

    @POST("inventory/purchase-orders")
    suspend fun createPurchaseOrder(@Body request: CreatePurchaseOrderRequest): ApiResponse<PurchaseOrderDetailData>

    @retrofit2.http.PUT("inventory/purchase-orders/{id}")
    suspend fun updatePurchaseOrder(
        @Path("id") id: Long,
        @Body request: UpdatePurchaseOrderRequest,
    ): ApiResponse<PurchaseOrderDetailData>

    @POST("inventory/purchase-orders/{id}/receive")
    suspend fun receivePurchaseOrder(
        @Path("id") id: Long,
        @Body request: ReceivePurchaseOrderRequest,
    ): ApiResponse<PurchaseOrderDetailData>

    @GET("inventory/suppliers/list")
    suspend fun getSuppliers(@Query("active_only") activeOnly: Boolean = true): ApiResponse<List<SupplierListItem>>
}
