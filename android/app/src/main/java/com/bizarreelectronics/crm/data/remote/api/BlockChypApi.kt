package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.google.gson.annotations.SerializedName
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.POST

// ─── Request DTOs ─────────────────────────────────────────────────────────────

data class BlockChypTestConnectionRequest(
    @SerializedName("terminalName") val terminalName: String? = null,
)

data class BlockChypProcessPaymentRequest(
    @SerializedName("invoiceId") val invoiceId: Long,
    @SerializedName("tip") val tip: Double? = null,
    @SerializedName("idempotency_key") val idempotencyKey: String,
)

data class BlockChypVoidRequest(
    @SerializedName("paymentId") val paymentId: String,
)

data class BlockChypAdjustTipRequest(
    @SerializedName("transaction_id") val transactionId: String,
    @SerializedName("new_tip") val newTip: Double,
)

data class BlockChypCaptureSignatureRequest(
    @SerializedName("ticketId") val ticketId: Long,
)

// ─── Response DTOs ────────────────────────────────────────────────────────────

data class BlockChypTestConnectionData(
    val success: Boolean,
    val connected: Boolean = false,
    val terminalName: String? = null,
)

data class BlockChypChargeData(
    val success: Boolean = false,
    val replayed: Boolean = false,
    @SerializedName("transactionId") val transactionId: String? = null,
    @SerializedName("transaction_ref") val transactionRef: String? = null,
    @SerializedName("authCode") val authCode: String? = null,
    @SerializedName("cardType") val cardType: String? = null,
    @SerializedName("last4") val last4: String? = null,
    val amount: Double? = null,
    @SerializedName("receiptSuggestions") val receiptSuggestions: Map<String, Any>? = null,
    // pending_reconciliation path
    val status: String? = null,
    val message: String? = null,
)

data class BlockChypVoidData(
    @SerializedName("paymentId") val paymentId: Long? = null,
    @SerializedName("transactionId") val transactionId: String? = null,
    @SerializedName("signatureFileDeleted") val signatureFileDeleted: Boolean = false,
)

data class BlockChypAdjustTipData(
    val success: Boolean = false,
    val code: String? = null,
    val message: String? = null,
)

data class BlockChypSignatureData(
    val success: Boolean = false,
    @SerializedName("signatureFile") val signatureFile: String? = null,
    @SerializedName("signatureFilePath") val signatureFilePath: String? = null,
    // base64 PNG data URL returned by the server when tc is enabled
    @SerializedName("base64DataUrl") val base64DataUrl: String? = null,
)

data class BlockChypStatusData(
    val enabled: Boolean = false,
    @SerializedName("terminalName") val terminalName: String? = null,
    @SerializedName("tcEnabled") val tcEnabled: Boolean = false,
    @SerializedName("promptForTip") val promptForTip: Boolean = false,
    @SerializedName("autoCloseTicket") val autoCloseTicket: Boolean = false,
    // Extended status from terminal firmware query (populated by test-connection)
    @SerializedName("firmwareVersion") val firmwareVersion: String? = null,
    val online: Boolean = false,
)

// ─── API interface ─────────────────────────────────────────────────────────────

/**
 * Retrofit interface for the BlockChyp server-proxy endpoints.
 *
 * All calls route through the CRM server — the Android app never talks to
 * BlockChyp hardware directly. The server holds the SDK credentials and
 * terminal config.
 *
 * Phase 4 — BlockChyp Android SDK + SignatureRouter.
 */
interface BlockChypApi {

    @POST("blockchyp/test-connection")
    suspend fun testConnection(
        @Body request: BlockChypTestConnectionRequest,
    ): ApiResponse<BlockChypTestConnectionData>

    /**
     * Process a card payment. Caller must supply an Idempotency-Key header
     * containing a stable per-attempt token to prevent double-charges on retry.
     * Server returns 409 if a charge is in-flight or if the failed-key is replayed.
     */
    @POST("blockchyp/process-payment")
    suspend fun processPayment(
        @Header("Idempotency-Key") idempotencyKey: String,
        @Body request: BlockChypProcessPaymentRequest,
    ): ApiResponse<BlockChypChargeData>

    @POST("blockchyp/void-payment")
    suspend fun voidPayment(
        @Body request: BlockChypVoidRequest,
    ): ApiResponse<BlockChypVoidData>

    @POST("blockchyp/adjust-tip")
    suspend fun adjustTip(
        @Body request: BlockChypAdjustTipRequest,
    ): ApiResponse<BlockChypAdjustTipData>

    /** Captures signature before a ticket ID is assigned (pre-ticket check-in flow). */
    @POST("blockchyp/capture-checkin-signature")
    suspend fun captureCheckInSignature(): ApiResponse<BlockChypSignatureData>

    /** Captures signature after a ticket exists (post-creation sign). */
    @POST("blockchyp/capture-signature")
    suspend fun captureSignature(
        @Body request: BlockChypCaptureSignatureRequest,
    ): ApiResponse<BlockChypSignatureData>

    @GET("blockchyp/status")
    suspend fun getStatus(): ApiResponse<BlockChypStatusData>
}
