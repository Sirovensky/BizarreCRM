package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.CreateTicketRequest
import com.bizarreelectronics.crm.data.remote.dto.InvoiceDetail
import com.bizarreelectronics.crm.data.remote.dto.TicketDetail
import com.bizarreelectronics.crm.data.remote.dto.TicketListData
import com.bizarreelectronics.crm.data.remote.dto.TicketNote
import com.bizarreelectronics.crm.data.remote.dto.UpdateTicketRequest
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.PUT
import retrofit2.http.Path
import retrofit2.http.QueryMap

interface TicketApi {

    @GET("tickets")
    suspend fun getTickets(@QueryMap filters: Map<String, String> = emptyMap()): ApiResponse<TicketListData>

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

    @PATCH("tickets/{id}/pin")
    suspend fun togglePin(@Path("id") id: Long): ApiResponse<TicketDetail>

    @POST("tickets/{id}/convert-to-invoice")
    suspend fun convertToInvoice(@Path("id") id: Long): ApiResponse<InvoiceDetail>

    // Star endpoint not available on server — feature removed
    // @PATCH("tickets/{id}/star")
    // suspend fun toggleStar(@Path("id") id: Long): ApiResponse<TicketDetail>
}
