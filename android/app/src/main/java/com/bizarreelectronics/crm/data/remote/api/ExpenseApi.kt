package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.CreateExpenseRequest
import com.bizarreelectronics.crm.data.remote.dto.ExpenseDetail
import com.bizarreelectronics.crm.data.remote.dto.ExpenseListData
import com.bizarreelectronics.crm.data.remote.dto.UpdateExpenseRequest
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.PUT
import retrofit2.http.Path
import retrofit2.http.QueryMap

interface ExpenseApi {

    @GET("expenses")
    suspend fun getExpenses(@QueryMap filters: Map<String, String> = emptyMap()): ApiResponse<ExpenseListData>

    @GET("expenses/{id}")
    suspend fun getExpense(@Path("id") id: Long): ApiResponse<ExpenseDetail>

    @POST("expenses")
    suspend fun createExpense(@Body request: CreateExpenseRequest): ApiResponse<ExpenseDetail>

    @PUT("expenses/{id}")
    suspend fun updateExpense(@Path("id") id: Long, @Body request: UpdateExpenseRequest): ApiResponse<ExpenseDetail>

    @DELETE("expenses/{id}")
    suspend fun deleteExpense(@Path("id") id: Long): ApiResponse<Unit>

    /** Approve an expense. 404 is tolerated when the server endpoint is not yet deployed. */
    @POST("expenses/{id}/approve")
    suspend fun approveExpense(
        @Path("id") id: Long,
        @Body comment: String? = null,
    ): ApiResponse<Unit>

    /** Reject an expense. 404 is tolerated when the server endpoint is not yet deployed. */
    @POST("expenses/{id}/reject")
    suspend fun rejectExpense(
        @Path("id") id: Long,
        @Body comment: String? = null,
    ): ApiResponse<Unit>
}
