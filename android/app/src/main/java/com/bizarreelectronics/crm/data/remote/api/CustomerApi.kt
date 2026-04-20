package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.CreateCustomerNoteRequest
import com.bizarreelectronics.crm.data.remote.dto.CreateCustomerRequest
import com.bizarreelectronics.crm.data.remote.dto.CustomerAnalytics
import com.bizarreelectronics.crm.data.remote.dto.CustomerDetail
import com.bizarreelectronics.crm.data.remote.dto.CustomerListData
import com.bizarreelectronics.crm.data.remote.dto.CustomerListItem
import com.bizarreelectronics.crm.data.remote.dto.CustomerNote
import com.bizarreelectronics.crm.data.remote.dto.TicketListData
import com.bizarreelectronics.crm.data.remote.dto.UpdateCustomerRequest
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.PUT
import retrofit2.http.Path
import retrofit2.http.Query
import retrofit2.http.QueryMap

interface CustomerApi {

    @GET("customers")
    suspend fun getCustomers(@QueryMap filters: Map<String, String> = emptyMap()): ApiResponse<CustomerListData>

    @GET("customers/search")
    suspend fun searchCustomers(@Query("q") query: String): ApiResponse<List<CustomerListItem>>

    @GET("customers/{id}")
    suspend fun getCustomer(@Path("id") id: Long): ApiResponse<CustomerDetail>

    // CROSS50-header: lifetime analytics fetched in parallel with getCustomer so
    // the CustomerDetail header can render ticket_count / lifetime_value /
    // last_visit without waiting on or re-fetching the full detail payload.
    @GET("customers/{id}/analytics")
    suspend fun getAnalytics(@Path("id") id: Long): ApiResponse<CustomerAnalytics>

    // CROSS9a: ticket history section on CustomerDetail. Server returns
    // `{ tickets: [TicketListItem], pagination }` — same shape as the main
    // `GET /tickets` endpoint — so we reuse `TicketListData`. Page size is
    // capped client-side to the first 10 for the detail section.
    @GET("customers/{id}/tickets")
    suspend fun getTickets(
        @Path("id") id: Long,
        @Query("page") page: Int = 1,
        @Query("pagesize") pageSize: Int = 10,
    ): ApiResponse<TicketListData>

    @POST("customers")
    suspend fun createCustomer(@Body request: CreateCustomerRequest): ApiResponse<CustomerDetail>

    @PUT("customers/{id}")
    suspend fun updateCustomer(@Path("id") id: Long, @Body request: UpdateCustomerRequest): ApiResponse<CustomerDetail>

    // CROSS9b: customer notes timeline. GET returns most-recent-first, capped
    // at 500 rows server-side; POST appends a single note (body ≤5000 chars).
    @GET("customers/{id}/notes")
    suspend fun getNotes(@Path("id") id: Long): ApiResponse<List<CustomerNote>>

    @POST("customers/{id}/notes")
    suspend fun postNote(
        @Path("id") id: Long,
        @Body request: CreateCustomerNoteRequest,
    ): ApiResponse<CustomerNote>
}
