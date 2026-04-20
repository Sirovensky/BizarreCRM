package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.InvoiceDetailData
import com.bizarreelectronics.crm.data.remote.dto.InvoiceListData
import com.bizarreelectronics.crm.data.remote.dto.RecordPaymentRequest
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.QueryMap

interface InvoiceApi {

    @GET("invoices")
    suspend fun getInvoices(@QueryMap filters: Map<String, String> = emptyMap()): ApiResponse<InvoiceListData>

    @GET("invoices/{id}")
    suspend fun getInvoice(@Path("id") id: Long): ApiResponse<InvoiceDetailData>

    @POST("invoices/{id}/payments")
    suspend fun recordPayment(@Path("id") id: Long, @Body request: RecordPaymentRequest): ApiResponse<InvoiceDetailData>

    @POST("invoices/{id}/void")
    suspend fun voidInvoice(@Path("id") id: Long): ApiResponse<Unit>
}
