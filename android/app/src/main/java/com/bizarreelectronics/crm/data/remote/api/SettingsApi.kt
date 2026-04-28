package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.ConditionCheckItem
import com.bizarreelectronics.crm.data.remote.dto.CreateEmployeeRequest
import com.bizarreelectronics.crm.data.remote.dto.EmployeeListItem
import com.bizarreelectronics.crm.data.remote.dto.StatusListData
import com.bizarreelectronics.crm.data.remote.dto.TaxClassListData
import com.bizarreelectronics.crm.data.remote.dto.TicketStatusItem
import okhttp3.MultipartBody
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.Multipart
import retrofit2.http.POST
import retrofit2.http.PUT
import retrofit2.http.Part
import retrofit2.http.Path

interface SettingsApi {

    @GET("settings/config")
    suspend fun getConfig(): ApiResponse<Map<String, String>>

    @GET("settings/tax-classes")
    suspend fun getTaxClasses(): ApiResponse<TaxClassListData>

    @GET("settings/statuses")
    suspend fun getStatuses(): ApiResponse<StatusListData>

    /**
     * §19.16 — Typed list variant that maps directly to the array the server
     * returns in `data` (flat SQL rows, not wrapped in `{ statuses: [] }`).
     * Used by [com.bizarreelectronics.crm.ui.screens.settings.TicketStatusEditorViewModel].
     * 404-tolerant (returns empty list on any error in the VM).
     */
    @GET("settings/statuses")
    suspend fun getStatusList(): ApiResponse<List<TicketStatusItem>>

    /**
     * §19.16 — Update a single ticket status by id.
     * PUT /settings/statuses/:id (admin-only on server).
     * Body keys: name, color, notify_customer, is_closed, is_cancelled.
     * Returns the updated status row.
     */
    @PUT("settings/statuses/{id}")
    suspend fun putStatus(
        @Path("id") id: Long,
        @Body body: Map<String, @JvmSuppressWildcards Any>,
    ): ApiResponse<TicketStatusItem>

    @GET("employees")
    suspend fun getEmployees(): ApiResponse<List<EmployeeListItem>>

    /** L731 — keyword search for @mention suggestions (debounced). */
    @GET("employees")
    suspend fun searchEmployees(
        @retrofit2.http.Query("keyword") keyword: String,
    ): ApiResponse<List<EmployeeListItem>>

    @POST("settings/users")
    suspend fun createEmployee(
        @Body body: CreateEmployeeRequest,
    ): ApiResponse<EmployeeListItem>

    @POST("employees/{id}/clock-in")
    suspend fun clockIn(
        @Path("id") id: Long,
        @Body body: Map<String, String>,
    ): ApiResponse<@JvmSuppressWildcards Any>

    @POST("employees/{id}/clock-out")
    suspend fun clockOut(
        @Path("id") id: Long,
        @Body body: Map<String, String>,
    ): ApiResponse<@JvmSuppressWildcards Any>

    @GET("settings/condition-checks/{category}")
    suspend fun getConditionChecks(
        @Path("category") category: String
    ): ApiResponse<List<ConditionCheckItem>>

    /**
     * L1981 — Upload a new avatar image for the current user.
     * POST /auth/avatar (multipart/form-data, field name "avatar").
     * Returns the updated UserDto inside ApiResponse.data.
     * 404 is tolerated (endpoint may not exist yet — caller handles gracefully).
     */
    @Multipart
    @POST("auth/avatar")
    suspend fun uploadAvatar(
        @Part avatar: MultipartBody.Part,
    ): ApiResponse<com.bizarreelectronics.crm.data.remote.dto.UserDto>

    /**
     * TAG-PALETTE-001: tenant tag color palette.
     * Returns a map of tag → hex color string defined by shop staff.
     * 404 is tolerated — callers fall back to the 8-hue default cycle.
     */
    @GET("settings/tag-palette")
    suspend fun getTagPalette(): ApiResponse<Map<String, String>>

    /**
     * §14.4 — Assign role / update employee fields.
     * PUT /settings/users/:id (admin-only)
     * Body may contain: role, email, first_name, last_name, is_active, pin, password.
     * 404-tolerant.
     */
    @PUT("settings/users/{id}")
    suspend fun updateEmployee(
        @Path("id") employeeId: Long,
        @Body body: Map<String, @JvmSuppressWildcards Any>,
    ): ApiResponse<@JvmSuppressWildcards Any>

    /** Payment methods admin list (POS settings). */
    @GET("settings/payment-methods")
    suspend fun getPaymentMethods(): ApiResponse<List<Map<String, @JvmSuppressWildcards Any>>>

    /** SMS provider list (SMS settings). */
    @GET("settings/sms-providers")
    suspend fun getSmsProviders(): ApiResponse<List<Map<String, @JvmSuppressWildcards Any>>>

    /** Generic store-level config K/V. */
    @GET("settings/store-config")
    suspend fun getStoreConfig(): ApiResponse<Map<String, String>>

    @PUT("settings/store-config")
    suspend fun putStoreConfig(
        @Body body: Map<String, String>,
    ): ApiResponse<Map<String, String>>
}
