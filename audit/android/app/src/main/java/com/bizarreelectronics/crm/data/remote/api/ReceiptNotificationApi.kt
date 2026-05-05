package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.google.gson.annotations.SerializedName
import retrofit2.http.Body
import retrofit2.http.POST

// ─── Request DTOs ─────────────────────────────────────────────────────────────

data class SendReceiptEmailRequest(
    @SerializedName("invoice_id") val invoiceId: Long,
    @SerializedName("recipient_email") val recipientEmail: String,
)

data class SendReceiptSmsRequest(
    @SerializedName("invoice_id") val invoiceId: Long,
    @SerializedName("phone") val phone: String,
)

// ─── API interface ────────────────────────────────────────────────────────────

/**
 * Receipt notification endpoints — email via SMTP and SMS via BizarreSMS.
 *
 * Server routes (notifications.routes.ts):
 *   POST /api/v1/notifications/send-receipt          — POS-RECEIPT-001
 *   POST /api/v1/notifications/send-receipt-sms      — POS-SMS-001
 */
interface ReceiptNotificationApi {

    @POST("notifications/send-receipt")
    suspend fun sendReceiptEmail(@Body request: SendReceiptEmailRequest): ApiResponse<Unit>

    @POST("notifications/send-receipt-sms")
    suspend fun sendReceiptSms(@Body request: SendReceiptSmsRequest): ApiResponse<Unit>
}
