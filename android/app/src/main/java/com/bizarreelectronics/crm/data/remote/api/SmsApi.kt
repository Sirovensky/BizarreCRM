package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.SmsConversationListData
import com.bizarreelectronics.crm.data.remote.dto.SmsTemplateListData
import com.bizarreelectronics.crm.data.remote.dto.SmsThreadData
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query

interface SmsApi {

    @GET("sms/conversations")
    suspend fun getConversations(
        @Query("keyword") keyword: String? = null
    ): ApiResponse<SmsConversationListData>

    @GET("sms/conversations/{phone}")
    suspend fun getThread(
        @Path("phone") phone: String
    ): ApiResponse<SmsThreadData>

    @POST("sms/send")
    suspend fun sendSms(
        @Body request: Map<String, @JvmSuppressWildcards Any>
    ): ApiResponse<@JvmSuppressWildcards Any>

    @PATCH("sms/conversations/{phone}/flag")
    suspend fun toggleFlag(@Path("phone") phone: String): ApiResponse<@JvmSuppressWildcards Any>

    @PATCH("sms/conversations/{phone}/pin")
    suspend fun togglePin(@Path("phone") phone: String): ApiResponse<@JvmSuppressWildcards Any>

    @PATCH("sms/conversations/{phone}/read")
    suspend fun markRead(@Path("phone") phone: String): ApiResponse<Unit>

    @GET("sms/templates")
    suspend fun getTemplates(): ApiResponse<SmsTemplateListData>
}
