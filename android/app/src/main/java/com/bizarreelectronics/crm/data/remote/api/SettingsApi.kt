package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.ConditionCheckItem
import com.bizarreelectronics.crm.data.remote.dto.CreateEmployeeRequest
import com.bizarreelectronics.crm.data.remote.dto.EmployeeListItem
import com.bizarreelectronics.crm.data.remote.dto.StatusListData
import com.bizarreelectronics.crm.data.remote.dto.TaxClassListData
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path

interface SettingsApi {

    @GET("settings/config")
    suspend fun getConfig(): ApiResponse<Map<String, String>>

    @GET("settings/tax-classes")
    suspend fun getTaxClasses(): ApiResponse<TaxClassListData>

    @GET("settings/statuses")
    suspend fun getStatuses(): ApiResponse<StatusListData>

    @GET("employees")
    suspend fun getEmployees(): ApiResponse<List<EmployeeListItem>>

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
}
