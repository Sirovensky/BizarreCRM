package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.AddCustomerAssetRequest
import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.BulkDeleteRequest
import com.bizarreelectronics.crm.data.remote.dto.BulkRestoreRequest
import com.bizarreelectronics.crm.data.remote.dto.BulkTagRequest
import com.bizarreelectronics.crm.data.remote.dto.CreateCustomerNoteRequest
import com.bizarreelectronics.crm.data.remote.dto.CreateCustomerRequest
import com.bizarreelectronics.crm.data.remote.dto.CustomerAnalytics
import com.bizarreelectronics.crm.data.remote.dto.CustomerDetail
import com.bizarreelectronics.crm.data.remote.dto.CustomerHealthScore
import com.bizarreelectronics.crm.data.remote.dto.CustomerListData
import com.bizarreelectronics.crm.data.remote.dto.CustomerListItem
import com.bizarreelectronics.crm.data.remote.dto.CustomerLtvTier
import com.bizarreelectronics.crm.data.remote.dto.CustomerMergeRequest
import com.bizarreelectronics.crm.data.remote.dto.CustomerNote
import com.bizarreelectronics.crm.data.remote.dto.CustomerPageResponse
import com.bizarreelectronics.crm.data.remote.dto.CustomerStats
import com.bizarreelectronics.crm.data.remote.dto.InvoiceListData
import com.bizarreelectronics.crm.data.remote.dto.StoreCreditBalanceData
import com.bizarreelectronics.crm.data.remote.dto.TicketListData
import com.bizarreelectronics.crm.data.remote.dto.UpdateCustomerRequest
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.PUT
import retrofit2.http.Path
import retrofit2.http.Query
import retrofit2.http.QueryMap

interface CustomerApi {

    @GET("customers")
    suspend fun getCustomers(@QueryMap filters: Map<String, String> = emptyMap()): ApiResponse<CustomerListData>

    /** Cursor-based page fetch for [CustomerRemoteMediator] (plan:L874). */
    @GET("customers")
    suspend fun getCustomerPage(
        @Query("cursor") cursor: String?,
        @Query("limit") limit: Int = 50,
        @QueryMap filters: Map<String, String> = emptyMap(),
    ): ApiResponse<CustomerPageResponse>

    /** Stats header tiles (plan:L880). 404 tolerated — callers silent-degrade. */
    @GET("customers/stats")
    suspend fun getStats(): ApiResponse<CustomerStats>

    @GET("customers/search")
    suspend fun searchCustomers(@Query("q") query: String): ApiResponse<List<CustomerListItem>>

    @GET("customers/{id}")
    suspend fun getCustomer(@Path("id") id: Long): ApiResponse<CustomerDetail>

    // CROSS50-header: lifetime analytics fetched in parallel with getCustomer so
    // the CustomerDetail header can render ticket_count / lifetime_value /
    // last_visit without waiting on or re-fetching the full detail payload.
    @GET("customers/{id}/analytics")
    suspend fun getAnalytics(@Path("id") id: Long): ApiResponse<CustomerAnalytics>

    // CROSS9a: ticket history section on CustomerDetail. Server returns
    // `{ tickets: [TicketListItem], pagination }` — same shape as the main
    // `GET /tickets` endpoint — so we reuse `TicketListData`. Page size is
    // capped client-side to the first 10 for the detail section.
    @GET("customers/{id}/tickets")
    suspend fun getTickets(
        @Path("id") id: Long,
        @Query("page") page: Int = 1,
        @Query("pagesize") pageSize: Int = 10,
    ): ApiResponse<TicketListData>

    // POS-STORECREDIT-001: balance lookup for the POS entry Store-credit tile.
    // Returns { customer_id, amount_cents } with amount_cents=0 when the
    // customer has never had credit applied — no 404 on empty.
    @GET("customers/{id}/store-credit")
    suspend fun getStoreCredit(@Path("id") id: Long): ApiResponse<StoreCreditBalanceData>

    /** Customer's on-file devices (mockup PHONE 2 'ON FILE' picker). */
    @GET("customers/{id}/assets")
    suspend fun getAssets(@Path("id") id: Long): ApiResponse<List<com.bizarreelectronics.crm.data.remote.dto.CustomerAsset>>

    @POST("customers")
    suspend fun createCustomer(@Body request: CreateCustomerRequest): ApiResponse<CustomerDetail>

    @PUT("customers/{id}")
    suspend fun updateCustomer(@Path("id") id: Long, @Body request: UpdateCustomerRequest): ApiResponse<CustomerDetail>

    // CROSS9b: customer notes timeline. GET returns most-recent-first, capped
    // at 500 rows server-side; POST appends a single note (body ≤5000 chars).
    @GET("customers/{id}/notes")
    suspend fun getNotes(@Path("id") id: Long): ApiResponse<List<CustomerNote>>

    @POST("customers/{id}/notes")
    suspend fun postNote(
        @Path("id") id: Long,
        @Body request: CreateCustomerNoteRequest,
    ): ApiResponse<CustomerNote>

    // CROSS9b: undo compensatingSync — hard-deletes a single note by its server
    // id. Matches DELETE /customers/:id/notes/:noteId on the server.
    @DELETE("customers/{id}/notes/{noteId}")
    suspend fun deleteNote(
        @Path("id") customerId: Long,
        @Path("noteId") noteId: Long,
    ): ApiResponse<Unit>

    /** Health score ring (plan:L892). 404 tolerated — callers silent-degrade. */
    @GET("customers/{id}/health-score")
    suspend fun getHealthScore(@Path("id") id: Long): ApiResponse<CustomerHealthScore>

    /** Recalculate health score server-side (plan:L892). */
    @POST("customers/{id}/health-score/recalculate")
    suspend fun recalculateHealthScore(@Path("id") id: Long): ApiResponse<CustomerHealthScore>

    /** LTV tier chip (plan:L893). 404 tolerated — callers silent-degrade. */
    @GET("customers/{id}/ltv-tier")
    suspend fun getLtvTier(@Path("id") id: Long): ApiResponse<CustomerLtvTier>

    /** Invoices tab (plan:L897). */
    @GET("customers/{id}/invoices")
    suspend fun getInvoices(
        @Path("id") id: Long,
        @Query("page") page: Int = 1,
        @Query("pagesize") pageSize: Int = 20,
    ): ApiResponse<InvoiceListData>

    /** Delete customer (plan:L905). */
    @DELETE("customers/{id}")
    suspend fun deleteCustomer(@Path("id") id: Long): ApiResponse<Unit>

    // ─── 5.5 Merge ──────────────────────────────────────────────────────────

    /**
     * Merge two customer records. [keep_id] survives; [merge_id] is absorbed.
     * Destructive after 24 h (server enforces). POST /customers/merge.
     */
    @POST("customers/merge")
    suspend fun mergeCustomers(@Body request: CustomerMergeRequest): ApiResponse<CustomerDetail>

    // ─── 5.6 Bulk actions ────────────────────────────────────────────────────

    /** Bulk-apply a single tag string to a set of customer ids. */
    @POST("customers/bulk-tag")
    suspend fun bulkTag(@Body request: BulkTagRequest): ApiResponse<Unit>

    /** Bulk-delete a set of customer ids (soft-delete; reversible within 24 h). */
    @POST("customers/bulk-delete")
    suspend fun bulkDelete(@Body request: BulkDeleteRequest): ApiResponse<Unit>

    /**
     * Bulk-restore previously soft-deleted customers. Used by the 5-second undo
     * snackbar after a bulk-delete. Falls back to no-op when the endpoint 404s.
     */
    @POST("customers/bulk-restore")
    suspend fun bulkRestore(@Body request: BulkRestoreRequest): ApiResponse<Unit>

    // ─── 5.7 Asset tracking ──────────────────────────────────────────────────

    /** Add a device asset to a customer. POST /customers/:id/assets. */
    @POST("customers/{id}/assets")
    suspend fun addAsset(
        @Path("id") customerId: Long,
        @Body request: AddCustomerAssetRequest,
    ): ApiResponse<com.bizarreelectronics.crm.data.remote.dto.CustomerAsset>
}
