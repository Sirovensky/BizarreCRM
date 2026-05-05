package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.RecurringInvoiceDetail
import com.bizarreelectronics.crm.data.remote.dto.RecurringInvoiceItem
import com.bizarreelectronics.crm.data.remote.dto.RecurringInvoiceListData
import com.bizarreelectronics.crm.data.remote.dto.CreateRecurringInvoiceRequest
import com.bizarreelectronics.crm.data.remote.dto.PatchRecurringInvoiceRequest
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query

/**
 * §SCAN-478 — Recurring invoice templates.
 *
 * All endpoints are 404-tolerant: callers catch [retrofit2.HttpException] with
 * code 404 and degrade gracefully (empty list / not-available state).
 *
 * Server base path: GET/POST /api/v1/recurring-invoices
 */
interface RecurringInvoicesApi {

    /**
     * List templates. Optional [status] filter: "active" | "paused" | "cancelled".
     * Paginated via [page] (1-based) + [pageSize].
     */
    @GET("recurring-invoices")
    suspend fun listTemplates(
        @Query("page") page: Int = 1,
        @Query("pagesize") pageSize: Int = 25,
        @Query("status") status: String? = null,
    ): ApiResponse<RecurringInvoiceListData>

    /** Full template detail including last 20 run records. */
    @GET("recurring-invoices/{id}")
    suspend fun getTemplate(@Path("id") id: Long): ApiResponse<RecurringInvoiceDetail>

    /**
     * Create a new recurring-invoice template.
     * Requires at least one line item and a valid [CreateRecurringInvoiceRequest.customerId].
     */
    @POST("recurring-invoices")
    suspend fun createTemplate(
        @Body request: CreateRecurringInvoiceRequest,
    ): ApiResponse<RecurringInvoiceDetail>

    /**
     * Partial update: [status], [next_run_at], [notes_template], [line_items].
     * Admin-only on the server.
     */
    @PATCH("recurring-invoices/{id}")
    suspend fun patchTemplate(
        @Path("id") id: Long,
        @Body request: PatchRecurringInvoiceRequest,
    ): ApiResponse<RecurringInvoiceDetail>

    /** Pause an active template (lifecycle transition — audited on server). */
    @POST("recurring-invoices/{id}/pause")
    suspend fun pauseTemplate(@Path("id") id: Long): ApiResponse<RecurringInvoiceDetail>

    /** Resume a paused template. */
    @POST("recurring-invoices/{id}/resume")
    suspend fun resumeTemplate(@Path("id") id: Long): ApiResponse<RecurringInvoiceDetail>

    /** Cancel a template (terminal state — cannot be reversed). */
    @POST("recurring-invoices/{id}/cancel")
    suspend fun cancelTemplate(@Path("id") id: Long): ApiResponse<RecurringInvoiceDetail>
}
