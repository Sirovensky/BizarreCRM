package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.AgingReportData
import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.CreateInvoiceRequest
import com.bizarreelectronics.crm.data.remote.dto.CreditNoteRequest
import com.bizarreelectronics.crm.data.remote.dto.CreditNoteResponseData
import com.bizarreelectronics.crm.data.remote.dto.InvoiceDetailData
import com.bizarreelectronics.crm.data.remote.dto.InvoiceListData
import com.bizarreelectronics.crm.data.remote.dto.InvoicePageResponse
import com.bizarreelectronics.crm.data.remote.dto.InvoiceStatsData
import com.bizarreelectronics.crm.data.remote.dto.IssueRefundRequest
import com.bizarreelectronics.crm.data.remote.dto.RecordPaymentRequest
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query
import retrofit2.http.QueryMap

interface InvoiceApi {

    @GET("invoices")
    suspend fun getInvoices(@QueryMap filters: Map<String, String> = emptyMap()): ApiResponse<InvoiceListData>

    /**
     * Cursor-based page fetch for offline-first paging (§7.1).
     * When [cursor] is null the server returns the first page.
     * On servers that do not yet support cursor params the response is treated as a
     * final page ([InvoicePageResponse.cursor] = null).
     */
    @GET("invoices")
    suspend fun getInvoicePage(
        @Query("cursor") cursor: String?,
        @Query("limit") limit: Int = 50,
        @QueryMap filters: Map<String, String> = emptyMap(),
    ): ApiResponse<InvoicePageResponse>

    @GET("invoices/{id}")
    suspend fun getInvoice(@Path("id") id: Long): ApiResponse<InvoiceDetailData>

    /**
     * Aggregate stats: total unpaid / paid / overdue amounts.
     * 404 → tolerated; callers should gracefully skip the stats header.
     */
    @GET("invoices/stats")
    suspend fun getStats(): ApiResponse<InvoiceStatsData>

    /** Create a new invoice. Server requires at least one line item and a valid customer_id. */
    @POST("invoices")
    suspend fun createInvoice(@Body body: CreateInvoiceRequest): ApiResponse<InvoiceDetailData>

    @POST("invoices/{id}/payments")
    suspend fun recordPayment(@Path("id") id: Long, @Body request: RecordPaymentRequest): ApiResponse<InvoiceDetailData>

    @POST("invoices/{id}/void")
    suspend fun voidInvoice(@Path("id") id: Long): ApiResponse<Unit>

    /**
     * Issue a refund against a paid invoice.
     * 404 → endpoint not yet deployed; callers catch and display stub.
     */
    @POST("refunds")
    suspend fun issueRefund(@Body request: IssueRefundRequest): ApiResponse<Unit>

    /**
     * Clone an existing invoice (creates a new Draft copy).
     * 404 → endpoint not yet deployed; callers catch and display stub.
     */
    @POST("invoices/{id}/clone")
    suspend fun cloneInvoice(@Path("id") id: Long): ApiResponse<InvoiceDetailData>

    /**
     * Create a credit note against a paid/partial invoice.
     * Server requires `amount` (> 0, <= invoice total) and `reason` (non-blank).
     * Requires `invoices.credit_note` permission.
     */
    @POST("invoices/{id}/credit-note")
    suspend fun createCreditNote(
        @Path("id") id: Long,
        @Body request: CreditNoteRequest,
    ): ApiResponse<CreditNoteResponseData>

    /**
     * Aging report: buckets + flat invoice list from GET /dunning/invoices/aging.
     * Mounted on the dunning router at /api/v1/dunning/invoices/aging.
     */
    @GET("dunning/invoices/aging")
    suspend fun getAgingReport(): ApiResponse<AgingReportData>
}
