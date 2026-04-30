package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.AdjustStockRequest
import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.AutoReorderRequest
import com.bizarreelectronics.crm.data.remote.dto.AutoReorderRunResult
import com.bizarreelectronics.crm.data.remote.dto.BinListData
import com.bizarreelectronics.crm.data.remote.dto.BinLocationItem
import com.bizarreelectronics.crm.data.remote.dto.CreateBinLocationRequest
import com.bizarreelectronics.crm.data.remote.dto.CreateInventoryRequest
import com.bizarreelectronics.crm.data.remote.dto.InventoryDetailData
import com.bizarreelectronics.crm.data.remote.dto.InventoryImageUploadData
import com.bizarreelectronics.crm.data.remote.dto.InventoryListData
import com.bizarreelectronics.crm.data.remote.dto.MovementPage
import com.bizarreelectronics.crm.data.remote.dto.PhotoListData
import com.bizarreelectronics.crm.data.remote.dto.PriceHistoryData
import com.bizarreelectronics.crm.data.remote.dto.SalesHistoryData
import com.bizarreelectronics.crm.data.remote.dto.SupplierDetailData
import com.bizarreelectronics.crm.data.remote.dto.TaxClassOption
import com.bizarreelectronics.crm.data.remote.dto.TicketUsageData
import com.bizarreelectronics.crm.data.remote.dto.UpdateBinLocationRequest
import okhttp3.MultipartBody
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.Multipart
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.PUT
import retrofit2.http.Part
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

    /**
     * §6.8 — Run auto-reorder: scan all low-stock items with a supplier assigned,
     * group by supplier, and create draft purchase orders.
     *
     * Server route: POST /api/v1/inventory/auto-reorder
     * Requires `inventory.bulk_action` permission (admin-only in current schema).
     *
     * Returns [AutoReorderRunResult] with order count + per-order detail, or an
     * empty result set when no items qualify.
     */
    @POST("inventory/auto-reorder")
    suspend fun runAutoReorder(): ApiResponse<AutoReorderRunResult>

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

    // ── §6.3: Upload/replace primary image ──────────────────────────────────
    /**
     * POST /inventory/:id/image — multipart upload, field name "image".
     * Server stores the file and returns { image_url: "<relative-path>" }.
     * This replaces the existing primary image (single-image model).
     */
    @Multipart
    @POST("inventory/{id}/image")
    suspend fun uploadImage(
        @Path("id") id: Long,
        @Part image: MultipartBody.Part,
    ): ApiResponse<InventoryImageUploadData>

    // ── §6.4: Delete (soft-delete; server sets is_active=0) ──────────────────
    @DELETE("inventory/{id}")
    suspend fun deleteItem(@Path("id") id: Long): ApiResponse<Unit>

    // §6.7 Purchase Orders + supplier list moved to dedicated PurchaseOrderApi.kt
    // (cb7e0472). Don't duplicate here.

    // ── §6.8 Bin locations CRUD (/inventory-enrich/bin-locations) ────────────
    /**
     * List all active bin locations.
     *
     * GET /inventory-enrich/bin-locations
     * Response: `{ success: true, data: [BinLocationItem, ...] }`
     * 404-tolerated — server predates the bin-locations table; UI shows empty list.
     */
    @GET("inventory-enrich/bin-locations")
    suspend fun getBinLocations(): ApiResponse<List<BinLocationItem>>

    /**
     * Create a new bin location.
     *
     * POST /inventory-enrich/bin-locations
     * 409 when [code] is already taken (server enforces UNIQUE).
     */
    @POST("inventory-enrich/bin-locations")
    suspend fun createBinLocation(
        @Body request: CreateBinLocationRequest,
    ): ApiResponse<BinLocationItem>

    /**
     * Update an existing bin location's description / address parts.
     *
     * PUT /inventory-enrich/bin-locations/:id
     * Note: [code] is immutable after creation; only description/aisle/shelf/bin
     * can be changed.
     */
    @PUT("inventory-enrich/bin-locations/{id}")
    suspend fun updateBinLocation(
        @Path("id") id: Long,
        @Body request: UpdateBinLocationRequest,
    ): ApiResponse<BinLocationItem>

    /**
     * Soft-delete a bin location (sets is_active = 0).
     *
     * DELETE /inventory-enrich/bin-locations/:id
     */
    @DELETE("inventory-enrich/bin-locations/{id}")
    suspend fun deleteBinLocation(@Path("id") id: Long): ApiResponse<Map<String, Long>>
}
