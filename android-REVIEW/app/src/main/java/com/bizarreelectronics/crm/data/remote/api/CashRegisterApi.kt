package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.google.gson.annotations.SerializedName
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path

// ─── DTOs ────────────────────────────────────────────────────────────────────

data class CashDenominationCount(
    val denomination: String,          // "100", "50", "20", "10", "5", "1", "0.25", "0.10", "0.05", "0.01"
    val count: Int,
)

data class OpenShiftRequest(
    @SerializedName("register_id")       val registerId: String,
    @SerializedName("starting_cash_cents") val startingCashCents: Long,
    @SerializedName("denomination_counts") val denominationCounts: List<CashDenominationCount> = emptyList(),
)

data class TenderBreakdown(
    val tender: String,                // "cash" | "card" | "gift" | "store_credit"
    @SerializedName("sales_count")    val salesCount: Int,
    @SerializedName("sales_total_cents") val salesTotalCents: Long,
    @SerializedName("refund_count")   val refundCount: Int,
    @SerializedName("refund_total_cents") val refundTotalCents: Long,
)

data class ZReport(
    @SerializedName("shift_id")          val shiftId: Long,
    val cashier: String?,
    @SerializedName("register_id")       val registerId: String?,
    @SerializedName("started_at")        val startedAt: String?,
    @SerializedName("closed_at")         val closedAt: String?,
    @SerializedName("sales_count")       val salesCount: Int,
    @SerializedName("gross_cents")       val grossCents: Long,
    @SerializedName("net_cents")         val netCents: Long,
    @SerializedName("tender_breakdown")  val tenderBreakdown: List<TenderBreakdown>,
    @SerializedName("refunds_count")     val refundsCount: Int,
    @SerializedName("refunds_total_cents") val refundsTotalCents: Long,
    @SerializedName("voids_count")       val voidsCount: Int,
    @SerializedName("tips_cents")        val tipsCents: Long,
    @SerializedName("opening_cash_cents") val openingCashCents: Long,
    @SerializedName("closing_cash_cents") val closingCashCents: Long?,
    @SerializedName("expected_cash_cents") val expectedCashCents: Long,
    @SerializedName("over_short_cents")  val overShortCents: Long,
    @SerializedName("top_items")         val topItems: List<ZReportTopItem>,
)

data class ZReportTopItem(
    val name: String,
    val qty: Int,
    @SerializedName("total_cents") val totalCents: Long,
)

data class ShiftData(
    val shift: CashShift,
)

data class CashShift(
    val id: Long,
    @SerializedName("register_id")        val registerId: String?,
    val cashier: String?,
    val status: String,                   // "open" | "closed"
    @SerializedName("started_at")         val startedAt: String?,
    @SerializedName("closed_at")          val closedAt: String?,
    @SerializedName("starting_cash_cents") val startingCashCents: Long,
    @SerializedName("expected_cash_cents") val expectedCashCents: Long,
    @SerializedName("sales_count")        val salesCount: Int,
    @SerializedName("sales_total_cents")  val salesTotalCents: Long,
)

data class CloseShiftRequest(
    @SerializedName("closing_cash_cents")  val closingCashCents: Long,
    @SerializedName("denomination_counts") val denominationCounts: List<CashDenominationCount> = emptyList(),
    @SerializedName("over_short_reason")   val overShortReason: String? = null,
)

data class ZReportData(val report: ZReport)

data class PayInOutRequest(
    @SerializedName("amount_cents") val amountCents: Long,
    val reason: String,
)

data class PayInOutData(val shift: CashShift)

// ─── API interface ────────────────────────────────────────────────────────────

/**
 * Cash register session + Z-report endpoints.
 *
 * All endpoints are 404-tolerant — callers catch [retrofit2.HttpException] with
 * code 404 and show "Not available on this server" rather than crashing.
 *
 * Plan §39 L3027-L3058.
 */
interface CashRegisterApi {

    /** Get current open shift, if any (§39.1). */
    @GET("cash-register/shift/current")
    suspend fun getCurrentShift(): ApiResponse<ShiftData>

    /** Open a new cash shift (§39.1). */
    @POST("cash-register/shift/open")
    suspend fun openShift(@Body request: OpenShiftRequest): ApiResponse<ShiftData>

    /** Close the current shift and receive the Z-report (§39.1 / §39.2). */
    @POST("cash-register/shift/{id}/close")
    suspend fun closeShift(
        @Path("id") shiftId: Long,
        @Body request: CloseShiftRequest,
    ): ApiResponse<ZReportData>

    /** X-report: mid-shift snapshot without closing (§39.3). */
    @GET("cash-register/shift/{id}/x-report")
    suspend fun getXReport(@Path("id") shiftId: Long): ApiResponse<ZReportData>

    /** Pay-in: add cash from petty (§39.5). */
    @POST("cash-register/shift/{id}/pay-in")
    suspend fun payIn(
        @Path("id") shiftId: Long,
        @Body request: PayInOutRequest,
    ): ApiResponse<PayInOutData>

    /** Pay-out: remove cash from drawer (§39.5). */
    @POST("cash-register/shift/{id}/pay-out")
    suspend fun payOut(
        @Path("id") shiftId: Long,
        @Body request: PayInOutRequest,
    ): ApiResponse<PayInOutData>
}
