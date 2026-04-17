package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.CreateCustomerRequest
import com.bizarreelectronics.crm.data.remote.dto.CustomerAnalytics
import com.bizarreelectronics.crm.data.remote.dto.CustomerDetail
import com.bizarreelectronics.crm.data.remote.dto.CustomerListData
import com.bizarreelectronics.crm.data.remote.dto.CustomerListItem
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

    @POST("customers")
    suspend fun createCustomer(@Body request: CreateCustomerRequest): ApiResponse<CustomerDetail>

    @PUT("customers/{id}")
    suspend fun updateCustomer(@Path("id") id: Long, @Body request: UpdateCustomerRequest): ApiResponse<CustomerDetail>
}
