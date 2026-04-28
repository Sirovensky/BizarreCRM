package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.EmployeeDetailDto
import com.bizarreelectronics.crm.data.remote.dto.ForgotPinTriggerRequest
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path

/**
 * §14.3 — Employee-scoped API endpoints added for breaks + timesheet.
 *
 * Break endpoints (L1626):
 *   POST /employees/:id/break-start  — start a break for the given employee
 *   POST /employees/:id/break-end    — end the current break
 *
 * Timeclock admin endpoints (L1628/L1629):
 *   POST /timeclock/entries/:id      — admin edit of a specific time entry
 *   GET  /timeclock/weekly           — weekly hours grid (Mon-Sun) for one employee
 *
 * Admin actions (L1621/L1622):
 *   POST /employees/:id/reset-pin    — admin resets an employee's PIN
 *   POST /employees/:id/deactivate   — admin deactivates an employee
 *
 * Performance + commission stubs (L1617/L1618):
 *   GET  /employees/:id/performance  — tickets-closed / avg-time-to-close / revenue
 *   GET  /employees/:id/commissions  — month-to-date commission total
 *
 * All endpoints return { success, data? } — 404 from the server is tolerated;
 * callers guard with runCatching and show stub data on failure.
 */
interface EmployeeApi {

    // region — breaks

    @POST("employees/{id}/break-start")
    suspend fun startBreak(
        @Path("id") employeeId: Long,
        @Body body: Map<String, String> = emptyMap(),
    ): ApiResponse<@JvmSuppressWildcards Any>

    @POST("employees/{id}/break-end")
    suspend fun endBreak(
        @Path("id") employeeId: Long,
        @Body body: Map<String, String> = emptyMap(),
    ): ApiResponse<@JvmSuppressWildcards Any>

    // endregion

    // region — admin actions

    @POST("employees/{id}/reset-pin")
    suspend fun resetPin(
        @Path("id") employeeId: Long,
        @Body body: Map<String, String> = emptyMap(),
    ): ApiResponse<@JvmSuppressWildcards Any>

    @POST("employees/{id}/deactivate")
    suspend fun deactivate(
        @Path("id") employeeId: Long,
        @Body body: Map<String, String> = emptyMap(),
    ): ApiResponse<@JvmSuppressWildcards Any>

    /**
     * §2.15 L388 — manager dispatches a PIN-reset email on behalf of a staff member.
     *
     * POST /employees/:id/forgot-pin/trigger
     *   Server uses the employee's stored email address and dispatches the same
     *   reset-token link that self-service sends. 404 tolerated — email server
     *   may be absent on self-hosted tenants; callers guard with runCatching.
     */
    @POST("employees/{id}/forgot-pin/trigger")
    suspend fun triggerForgotPin(
        @Path("id") employeeId: Long,
        @Body body: ForgotPinTriggerRequest = ForgotPinTriggerRequest(),
    ): ApiResponse<@JvmSuppressWildcards Any>

    // endregion

    // region — employee detail

    /**
     * §3.11 — Fetch full employee detail including [current_clock_entry].
     * Self-service: admin or self only; non-privileged callers receive a
     * public-profile response without the clock array ([currentClockEntry]
     * will be null in that case — tile stays in "Clocked in" state without
     * a timestamp).
     * 404 tolerated — callers guard with runCatching.
     */
    @GET("employees/{id}")
    suspend fun getEmployee(
        @Path("id") employeeId: Long,
    ): ApiResponse<EmployeeDetailDto>

    // endregion

    // region — timeclock admin

    /** Edit a time entry. Body keys: start_time, end_time (ISO 8601 strings). */
    @POST("timeclock/entries/{id}")
    suspend fun editTimeEntry(
        @Path("id") entryId: Long,
        @Body body: Map<String, String>,
    ): ApiResponse<@JvmSuppressWildcards Any>

    /**
     * Weekly timesheet for one employee.
     * Query param ?employee_id=<id> expected by server; Retrofit adds via @GET URL.
     * Returns e.g. { data: { mon: 8.0, tue: 7.5, ... , totalHours: 40.0 } }
     */
    @GET("timeclock/weekly")
    suspend fun getWeeklyTimesheet(
        @retrofit2.http.Query("employee_id") employeeId: Long,
    ): ApiResponse<@JvmSuppressWildcards Any>

    // endregion

    // region — performance + commissions (stubs)

    /**
     * Performance stats for one employee.
     * Expected response shape: { ticketsClosed, avgTimeToCloseMinutes, revenueCents }
     * 404 tolerated — VM stubs zeros.
     */
    @GET("employees/{id}/performance")
    suspend fun getPerformance(
        @Path("id") employeeId: Long,
    ): ApiResponse<@JvmSuppressWildcards Any>

    /**
     * Month-to-date commission total.
     * Expected response shape: { commissionCents }
     * 404 tolerated — VM stubs 0.
     */
    @GET("employees/{id}/commissions")
    suspend fun getCommissions(
        @Path("id") employeeId: Long,
    ): ApiResponse<@JvmSuppressWildcards Any>

    /**
     * §14.7 — Leaderboard: all-employee performance summary.
     * GET /employees/performance/all
     * Returns a list of rows: { id, first_name, last_name, role,
     *   total_tickets, closed_tickets, total_revenue, avg_ticket_value, avg_repair_hours }
     * 404 tolerated — caller shows empty state.
     */
    @GET("employees/performance/all")
    suspend fun getPerformanceAll(): ApiResponse<@JvmSuppressWildcards Any>

    // endregion
}
