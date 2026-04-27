package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.AppointmentItem
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.Path

interface AppointmentApi {

    @GET("api/v1/appointments")
    suspend fun getAppointments(): ApiResponse<List<AppointmentItem>>

    @GET("api/v1/appointments/{id}")
    suspend fun getAppointment(@Path("id") id: Long): ApiResponse<AppointmentItem>

    /** §10.3 Minimal quick-create. Body must contain at minimum title + start_time + end_time. */
    @POST("api/v1/appointments")
    suspend fun createAppointment(
        @Body body: Map<String, @JvmSuppressWildcards Any?>,
    ): ApiResponse<AppointmentItem>

    @PATCH("api/v1/appointments/{id}")
    suspend fun patchAppointment(
        @Path("id") id: Long,
        @Body body: Map<String, @JvmSuppressWildcards Any?>,
    ): ApiResponse<AppointmentItem>

    @POST("api/v1/appointments/{id}/cancel")
    suspend fun cancelAppointment(
        @Path("id") id: Long,
        @Body body: Map<String, @JvmSuppressWildcards Any?>,
    ): ApiResponse<Unit>

    @POST("api/v1/appointments/{id}/send-reminder")
    suspend fun sendReminder(@Path("id") id: Long): ApiResponse<Unit>
}
