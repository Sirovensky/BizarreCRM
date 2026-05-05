package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.AppointmentDetail
import com.bizarreelectronics.crm.data.remote.dto.AppointmentListData
import com.bizarreelectronics.crm.data.remote.dto.CreateAppointmentRequest
import com.bizarreelectronics.crm.data.remote.dto.CreateLeadRequest
import com.bizarreelectronics.crm.data.remote.dto.LeadDetail
import com.bizarreelectronics.crm.data.remote.dto.LeadListData
import com.bizarreelectronics.crm.data.remote.dto.LeadReminder
import com.bizarreelectronics.crm.data.remote.dto.UpdateLeadRequest
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.PUT
import retrofit2.http.Path
import retrofit2.http.QueryMap

interface LeadApi {

    @GET("leads")
    suspend fun getLeads(@QueryMap filters: Map<String, String> = emptyMap()): ApiResponse<LeadListData>

    @GET("leads/{id}")
    suspend fun getLead(@Path("id") id: Long): ApiResponse<LeadDetail>

    @POST("leads")
    suspend fun createLead(@Body request: CreateLeadRequest): ApiResponse<LeadDetail>

    @PUT("leads/{id}")
    suspend fun updateLead(@Path("id") id: Long, @Body request: UpdateLeadRequest): ApiResponse<LeadDetail>

    @DELETE("leads/{id}")
    suspend fun deleteLead(@Path("id") id: Long): ApiResponse<Unit>

    @POST("leads/{id}/convert")
    suspend fun convertLead(@Path("id") id: Long): ApiResponse<@JvmSuppressWildcards Map<String, Any>>

    /**
     * Convert lead to customer (ActionPlan §9 L1399).
     * Copies lead fields to a new customer record and archives the lead.
     * 404-tolerant: callers should handle [retrofit2.HttpException] with code 404.
     */
    @POST("leads/{id}/convert-to-customer")
    suspend fun convertToCustomer(@Path("id") id: Long): ApiResponse<@JvmSuppressWildcards Map<String, Any>>

    /**
     * Convert lead to estimate (ActionPlan §9 L1400).
     * Returns a prefilled estimate detail so the caller can navigate to EstimateCreate.
     * 404-tolerant: callers should handle [retrofit2.HttpException] with code 404.
     */
    @POST("leads/{id}/convert-to-estimate")
    suspend fun convertToEstimate(@Path("id") id: Long): ApiResponse<@JvmSuppressWildcards Map<String, Any>>

    @POST("leads/{id}/reminder")
    suspend fun createReminder(@Path("id") id: Long, @Body body: Map<String, @JvmSuppressWildcards Any>): ApiResponse<LeadReminder>

    @GET("leads/{id}/reminders")
    suspend fun getReminders(@Path("id") id: Long): ApiResponse<List<LeadReminder>>

    @GET("leads/appointments")
    suspend fun getAppointments(@QueryMap filters: Map<String, String> = emptyMap()): ApiResponse<AppointmentListData>

    @POST("leads/appointments")
    suspend fun createAppointment(@Body request: CreateAppointmentRequest): ApiResponse<AppointmentDetail>

    @PUT("leads/appointments/{id}")
    suspend fun updateAppointment(@Path("id") id: Long, @Body request: CreateAppointmentRequest): ApiResponse<AppointmentDetail>
}
