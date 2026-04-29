package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.ChurnRiskData
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.QueryMap

// ─── DTOs ─────────────────────────────────────────────────────────────────────

/** Frequency options for a scheduled report. */
enum class ScheduleFrequency { DAILY, WEEKLY, MONTHLY }

/**
 * Tenant-level schedule spec sent to POST /reports/scheduled.
 *
 * @param reportType  e.g. "sales", "tickets", "inventory", "tax"
 * @param frequency   DAILY / WEEKLY / MONTHLY
 * @param weekday     0=Sun … 6=Sat — only used when frequency == WEEKLY
 * @param dayOfMonth  1–31 — only used when frequency == MONTHLY
 * @param recipients  comma-separated email string; empty means no email delivery
 * @param emailEnabled   deliver to [recipients] via email
 * @param inAppEnabled   create an in-app notification entry
 * @param fcmEnabled     send an FCM push to all tenant devices
 */
data class ScheduledReportSpec(
    val reportType: String,
    val frequency: ScheduleFrequency,
    val weekday: Int = 1,          // Monday
    val dayOfMonth: Int = 1,
    val recipients: String = "",
    val emailEnabled: Boolean = false,
    val inAppEnabled: Boolean = true,
    val fcmEnabled: Boolean = false,
)

/**
 * A persisted scheduled report row returned by GET /reports/scheduled.
 *
 * Fields mirror the server's JSON; unknown keys are ignored.
 */
data class ScheduledReport(
    val id: String,
    val reportType: String,
    val frequency: String,
    val weekday: Int?,
    val dayOfMonth: Int?,
    val recipients: String,
    val emailEnabled: Boolean,
    val inAppEnabled: Boolean,
    val fcmEnabled: Boolean,
    val paused: Boolean,
)

// ─── API interface ─────────────────────────────────────────────────────────────

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

    // ── §15 L1726 — scheduled reports ────────────────────────────────────────

    /** List all tenant-level schedules. 404 → tolerated as empty list. */
    @GET("reports/scheduled")
    suspend fun getScheduledReports(): ApiResponse<List<@JvmSuppressWildcards Any>>

    /** Create a new scheduled report. */
    @POST("reports/scheduled")
    suspend fun createScheduledReport(
        @Body spec: ScheduledReportSpec,
    ): ApiResponse<Map<String, @JvmSuppressWildcards Any>>

    /** Pause or resume an existing schedule. Body: `{"paused": true|false}`. */
    @PATCH("reports/scheduled/{id}")
    suspend fun patchScheduledReport(
        @Path("id") id: String,
        @Body body: Map<String, @JvmSuppressWildcards Any>,
    ): ApiResponse<Map<String, @JvmSuppressWildcards Any>>

    /** Delete a scheduled report by id. */
    @DELETE("reports/scheduled/{id}")
    suspend fun deleteScheduledReport(
        @Path("id") id: String,
    ): ApiResponse<Map<String, @JvmSuppressWildcards Any>>

    /** Trigger an immediate run of a report type. Body: `{"reportType": "sales"}`. */
    @POST("reports/run-now")
    suspend fun runNow(
        @Body body: Map<String, @JvmSuppressWildcards Any>,
    ): ApiResponse<Map<String, @JvmSuppressWildcards Any>>

    // ── §15.4 — Employee performance report ──────────────────────────────────
    /**
     * Returns per-employee stats for a date range.
     * Expected shape: `{ employees: [{ id, name, tickets_assigned, tickets_closed,
     *   hours_worked, revenue_generated, commission_earned, avg_ticket_value }] }`
     * 404 is tolerated — callers show empty state.
     */
    @GET("reports/employees")
    suspend fun getEmployeesReport(
        @QueryMap filters: Map<String, String> = emptyMap()
    ): ApiResponse<Map<String, @JvmSuppressWildcards Any>>

    // ── §14.7 — Tech leaderboard ─────────────────────────────────────────────
    /**
     * Ranked staff list by tickets closed / revenue / commission.
     * Query param: period = "week" | "month" | "ytd" (default "month").
     * Expected shape: `{ period, leaderboard: [{ rank, employee_id, name, tickets_closed,
     *   revenue_cents, commission_cents }] }`
     * 404 is tolerated — callers show empty-state.
     */
    @GET("reports/tech-leaderboard")
    suspend fun getTechLeaderboard(
        @retrofit2.http.Query("period") period: String = "month",
    ): ApiResponse<Map<String, @JvmSuppressWildcards Any>>

    // ── §45.3 — Churn-risk customer list ─────────────────────────────────────
    /**
     * Returns at-risk customers (no ticket in 90+ days with prior repeat history).
     * 404 tolerated — [atRiskCount] stays null in the Dashboard ViewModel so
     * [ChurnAlertCard] shows "Data unavailable" without crashing.
     *
     * Expected shape:
     * ```json
     * { "at_risk_count": 12,
     *   "customers": [{ id, first_name, last_name, phone, mobile,
     *                   days_since_last_visit, lifetime_value_cents }] }
     * ```
     */
    @GET("reports/churn-risk")
    suspend fun getChurnRisk(): ApiResponse<ChurnRiskData>

    // ── §15.7 — Busy hours heatmap ────────────────────────────────────────────
    /**
     * Returns a 7×24 ticket-volume grid.
     * Expected shape: `{ rows: [[int × 24] × 7] }` where rows[0] = Monday.
     * 404 is tolerated — callers show empty heatmap state.
     */
    @GET("reports/busy-hours-heatmap")
    suspend fun getBusyHoursHeatmap(
        @QueryMap filters: Map<String, String> = emptyMap()
    ): ApiResponse<Map<String, @JvmSuppressWildcards Any>>

    // ── §3.2 L504 — Cash-Trapped inventory report ─────────────────────────────
    /**
     * Returns slow-moving inventory (items not sold in 90+ days with stock > 0).
     *
     * Endpoint: `GET /reports/cash-trapped`
     *
     * Expected shape:
     * ```json
     * { "success": true, "data": {
     *     "total_cash_trapped": 1234.56,
     *     "item_count": 17,
     *     "top_offenders": [
     *       { "id": 1, "name": "...", "value": 99.00, "last_sold": "2025-01-01T..." }
     *     ]
     * } }
     * ```
     *
     * 404 is tolerated — caller emits null so [CashTrappedCard] shows the
     * "Connect Inventory data" stub.
     */
    @GET("reports/cash-trapped")
    suspend fun getCashTrapped(): ApiResponse<CashTrappedData>

    // ── §62.1 Financial Dashboard — P&L snapshot (owner-only) ────────────────
    /**
     * Returns profit-and-loss snapshot for the requested period.
     *
     * Owner-only endpoint — server returns 403 for non-owner roles.
     * Expected shape:
     * ```json
     * { "revenue_cents": 100000, "cogs_cents": 40000,
     *   "gross_margin_cents": 60000, "opex_cents": 20000,
     *   "net_income_cents": 40000, "period_change_pct": 5.2 }
     * ```
     * 404 tolerated — caller shows stub.
     */
    @GET("reports/pl-summary")
    suspend fun getPLSummary(
        @QueryMap filters: Map<String, String> = emptyMap(),
    ): ApiResponse<Map<String, @JvmSuppressWildcards Any>>

    // ── §62.2 Financial Dashboard — Cash flow forecast (owner-only) ──────────
    /**
     * Returns projected cash flow at 30 / 60 / 90 days.
     *
     * Owner-only endpoint — server returns 403 for non-owner roles.
     * Expected shape:
     * ```json
     * { "invoices_due_cents": 50000, "recurring_expenses_cents": 12000,
     *   "projected_30d_cents": 38000, "projected_60d_cents": 62000,
     *   "projected_90d_cents": 87000 }
     * ```
     * 404 tolerated — caller shows stub.
     */
    @GET("reports/cashflow")
    suspend fun getCashFlow(
        @QueryMap filters: Map<String, String> = emptyMap(),
    ): ApiResponse<Map<String, @JvmSuppressWildcards Any>>

    // ── §62.3 Financial Dashboard — Expense/tax breakdown (owner-only) ────────
    /**
     * Returns expense breakdown including tax jurisdiction data.
     *
     * Owner-only endpoint — server returns 403 for non-owner roles.
     * Expected shape:
     * ```json
     * { "jurisdictions": [
     *     { "name": "CA", "collected_cents": 8500,
     *       "remitted_cents": 8500, "is_remitted": true }
     *   ] }
     * ```
     * 404 tolerated — caller shows stub.
     */
    @GET("reports/expense-breakdown")
    suspend fun getExpenseBreakdown(
        @QueryMap filters: Map<String, String> = emptyMap(),
    ): ApiResponse<Map<String, @JvmSuppressWildcards Any>>
}

/**
 * §3.2 L504 — Response shape from `GET /reports/cash-trapped`.
 *
 * @property totalCashTrapped  Total dollar value of slow-moving inventory.
 * @property itemCount         Number of affected items.
 * @property topOffenders      Up to 25 worst offenders sorted by value descending.
 */
data class CashTrappedData(
    @com.google.gson.annotations.SerializedName("total_cash_trapped")
    val totalCashTrapped: Double = 0.0,
    @com.google.gson.annotations.SerializedName("item_count")
    val itemCount: Int = 0,
    @com.google.gson.annotations.SerializedName("top_offenders")
    val topOffenders: List<CashTrappedOffender> = emptyList(),
)

/**
 * §3.2 L504 — A single slow-moving inventory item from the cash-trapped endpoint.
 *
 * @property id        Inventory item id.
 * @property name      Display name.
 * @property value     Dollar value (in_stock × cost_price).
 * @property lastSold  ISO-8601 timestamp of last sale; null = never sold.
 */
data class CashTrappedOffender(
    val id: Long = 0L,
    val name: String = "",
    val value: Double = 0.0,
    @com.google.gson.annotations.SerializedName("last_sold")
    val lastSold: String? = null,
)
