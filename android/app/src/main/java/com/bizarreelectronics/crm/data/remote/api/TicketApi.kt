package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.CreateTicketDeviceRequest
import com.bizarreelectronics.crm.data.remote.dto.CreateTicketRequest
import com.bizarreelectronics.crm.data.remote.dto.InvoiceDetail
import com.bizarreelectronics.crm.data.remote.dto.TicketDetail
import com.bizarreelectronics.crm.data.remote.dto.TicketDevice
import com.bizarreelectronics.crm.data.remote.dto.TicketDevicePart
import com.bizarreelectronics.crm.data.remote.dto.TicketListData
import com.bizarreelectronics.crm.data.remote.dto.TicketNote
import com.bizarreelectronics.crm.data.remote.dto.TicketPageResponse
import com.bizarreelectronics.crm.data.remote.dto.UpdateTicketDeviceRequest
import com.bizarreelectronics.crm.data.remote.dto.AddTicketPartRequest
import com.bizarreelectronics.crm.data.remote.dto.UpdateTicketRequest
import retrofit2.http.Query
import okhttp3.MultipartBody
import okhttp3.RequestBody
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.Multipart
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.PUT
import retrofit2.http.Part
import retrofit2.http.Path
import retrofit2.http.QueryMap

interface TicketApi {

    @GET("tickets")
    suspend fun getTickets(@QueryMap filters: Map<String, String> = emptyMap()): ApiResponse<TicketListData>

    /**
     * Cursor-based page fetch for Paging3 [TicketRemoteMediator].
     *
     * - [cursor] — opaque token returned by the previous page; omit for the first page.
     * - [limit]  — page size; default 50 matches [PagingConfig.pageSize].
     * - Additional query params from [filters] allow status/assignee/urgency scoping.
     *
     * Response: [TicketPageResponse] with [items], next [cursor], and [serverExhausted] flag.
     */
    @GET("tickets")
    suspend fun getTicketPage(
        @Query("cursor") cursor: String?,
        @Query("limit") limit: Int = 50,
        @QueryMap filters: Map<String, String> = emptyMap(),
    ): ApiResponse<TicketPageResponse>

    @GET("tickets/stats")
    suspend fun getStats(): ApiResponse<@JvmSuppressWildcards Map<String, Any>>

    @GET("tickets/{id}")
    suspend fun getTicket(@Path("id") id: Long): ApiResponse<TicketDetail>

    @POST("tickets")
    suspend fun createTicket(@Body request: CreateTicketRequest): ApiResponse<TicketDetail>

    @PUT("tickets/{id}")
    suspend fun updateTicket(@Path("id") id: Long, @Body request: UpdateTicketRequest): ApiResponse<TicketDetail>

    @DELETE("tickets/{id}")
    suspend fun deleteTicket(@Path("id") id: Long): ApiResponse<Unit>

    @POST("tickets/{id}/notes")
    suspend fun addNote(@Path("id") id: Long, @Body note: Map<String, @JvmSuppressWildcards Any>): ApiResponse<TicketNote>

    @DELETE("tickets/notes/{noteId}")
    suspend fun deleteNote(@Path("noteId") noteId: Long): ApiResponse<@JvmSuppressWildcards Map<String, Any>>

    @PATCH("tickets/{id}/pin")
    suspend fun togglePin(@Path("id") id: Long): ApiResponse<TicketDetail>

    @POST("tickets/{id}/convert-to-invoice")
    suspend fun convertToInvoice(@Path("id") id: Long): ApiResponse<InvoiceDetail>

    // ─── Ticket device CRUD ───

    @POST("tickets/{id}/devices")
    suspend fun addDevice(
        @Path("id") ticketId: Long,
        @Body request: CreateTicketDeviceRequest,
    ): ApiResponse<TicketDevice>

    @PUT("tickets/devices/{deviceId}")
    suspend fun updateDevice(
        @Path("deviceId") deviceId: Long,
        @Body request: UpdateTicketDeviceRequest,
    ): ApiResponse<TicketDevice>

    @DELETE("tickets/devices/{deviceId}")
    suspend fun deleteDevice(@Path("deviceId") deviceId: Long): ApiResponse<@JvmSuppressWildcards Map<String, Any>>

    // ─── Ticket device parts ───

    @POST("tickets/devices/{deviceId}/parts")
    suspend fun addPartToDevice(
        @Path("deviceId") deviceId: Long,
        @Body request: AddTicketPartRequest,
    ): ApiResponse<TicketDevicePart>

    @DELETE("tickets/devices/parts/{partId}")
    suspend fun removePartFromDevice(
        @Path("partId") partId: Long,
    ): ApiResponse<@JvmSuppressWildcards Map<String, Any>>

    // Star endpoint not available on server — feature removed
    // @PATCH("tickets/{id}/star")
    // suspend fun toggleStar(@Path("id") id: Long): ApiResponse<TicketDetail>

    // U3 fix: photo upload endpoint backing PhotoCaptureScreen's gallery picker.
    // Server matches on ticket-level photos (tickets.routes.ts POST /:id/photos).
    // Uses multipart field name "photos" per upload.array('photos', 20).
    // Return type is Unit — the PhotoCaptureViewModel only cares whether the
    // upload succeeded, not the server-assigned photo id(s).
    //
    // bug:gallery-400 fix: server route requires `ticket_device_id` in the
    // request body (line 2422: if (!ticket_device_id) throw AppError('ticket_device_id
    // is required')). Without it the server returns HTTP 400. Added @Part for it.
    @Multipart
    @POST("tickets/{id}/photos")
    suspend fun uploadTicketPhotos(
        @Path("id") ticketId: Long,
        @Part photos: List<MultipartBody.Part>,
        @Part("type") type: RequestBody,
        @Part("ticket_device_id") ticketDeviceId: RequestBody,
    ): ApiResponse<Unit>
}
