package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import retrofit2.http.GET
import retrofit2.http.QueryMap

interface ReportApi {

    @GET("reports/dashboard")
    suspend fun getDashboard(): ApiResponse<Map<String, @JvmSuppressWildcards Any>>

    @GET("reports/needs-attention")
    suspend fun getNeedsAttention(): ApiResponse<Map<String, @JvmSuppressWildcards Any>>

    @GET("reports/sales")
    suspend fun getSalesReport(
        @QueryMap filters: Map<String, String> = emptyMap()
    ): ApiResponse<Map<String, @JvmSuppressWildcards Any>>

    // ── §15 L1735 — tickets report (404 tolerated; stub shown when absent) ───
    @GET("reports/tickets")
    suspend fun getTicketsReport(
        @QueryMap filters: Map<String, String> = emptyMap()
    ): ApiResponse<Map<String, @JvmSuppressWildcards Any>>

    // ── §15 L1743 — inventory report ─────────────────────────────────────────
    @GET("reports/inventory")
    suspend fun getInventoryReport(
        @QueryMap filters: Map<String, String> = emptyMap()
    ): ApiResponse<Map<String, @JvmSuppressWildcards Any>>

    // ── §15 L1747 — tax report ────────────────────────────────────────────────
    @GET("reports/tax")
    suspend fun getTaxReport(
        @QueryMap filters: Map<String, String> = emptyMap()
    ): ApiResponse<Map<String, @JvmSuppressWildcards Any>>

    // ── §15 L1726 — scheduled reports (404 → empty list; stub) ──────────────
    @GET("reports/scheduled")
    suspend fun getScheduledReports(): ApiResponse<List<@JvmSuppressWildcards Any>>
}
