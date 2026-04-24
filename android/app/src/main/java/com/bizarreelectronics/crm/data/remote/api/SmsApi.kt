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

    /**
     * Schedule send — POST /sms/send?send_at=<iso8601>.
     * 404-tolerant: caller falls back to WorkManager if server returns 404.
     */
    @POST("sms/send")
    suspend fun sendSmsScheduled(
        @Query("send_at") sendAt: String,
        @Body request: Map<String, @JvmSuppressWildcards Any>,
    ): ApiResponse<@JvmSuppressWildcards Any>

    @PATCH("sms/conversations/{phone}/flag")
    suspend fun toggleFlag(@Path("phone") phone: String): ApiResponse<@JvmSuppressWildcards Any>

    /** L1509 — pin a conversation. 404-tolerant: callers catch and ignore. */
    @PATCH("sms/conversations/{phone}/pin")
    suspend fun pinThread(@Path("phone") phone: String): ApiResponse<@JvmSuppressWildcards Any>

    @PATCH("sms/conversations/{phone}/pin")
    suspend fun togglePin(@Path("phone") phone: String): ApiResponse<@JvmSuppressWildcards Any>

    @PATCH("sms/conversations/{phone}/read")
    suspend fun markRead(@Path("phone") phone: String): ApiResponse<Unit>

    /** L1512 — archive a conversation. 404-tolerant. */
    @PATCH("sms/conversations/{phone}/archive")
    suspend fun archiveThread(@Path("phone") phone: String): ApiResponse<@JvmSuppressWildcards Any>

    /** L1512 — assign a conversation to a user. 404-tolerant. */
    @PATCH("sms/conversations/{phone}/assign")
    suspend fun assignThread(
        @Path("phone") phone: String,
        @Body body: Map<String, @JvmSuppressWildcards Any>,
    ): ApiResponse<@JvmSuppressWildcards Any>

    @GET("sms/templates")
    suspend fun getTemplates(): ApiResponse<SmsTemplateListData>
}
