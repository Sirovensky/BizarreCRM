package com.bizarreelectronics.crm.ui.screens.pos

import android.util.Log
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.google.gson.annotations.SerializedName
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import retrofit2.HttpException
import retrofit2.http.Body
import retrofit2.http.POST
import javax.inject.Inject

// ─── Client-side DTO for the not-yet-deployed SMS receipt endpoint ────────────

data class SendReceiptSmsRequest(
    @SerializedName("invoice_id") val invoiceId: Long,
    @SerializedName("phone") val phone: String,
)

/** Retrofit interface stub — server endpoint POS-SMS-001 not yet deployed. */
interface ReceiptNotificationApi {
    @POST("notifications/send-receipt-sms")
    suspend fun sendReceiptSms(@Body request: SendReceiptSmsRequest): ApiResponse<Unit>
}

// ─── UI state ─────────────────────────────────────────────────────────────────

data class PosReceiptUiState(
    val orderId: String = "",
    val invoiceId: Long? = null,
    val totalCents: Long = 0L,
    val customerName: String = "",
    val customerPhone: String? = null,
    val customerEmail: String? = null,
    val linkedTicketId: Long? = null,
    val trackingUrl: String? = null,
    val smsSentState: SendState = SendState.IDLE,
    val emailSentState: SendState = SendState.IDLE,
    val snackbarMessage: String? = null,
)

enum class SendState { IDLE, SENDING, SENT, ERROR }

@HiltViewModel
class PosReceiptViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val coordinator: PosCoordinator,
    private val receiptApi: ReceiptNotificationApi,
) : ViewModel() {

    private val _uiState = MutableStateFlow(PosReceiptUiState())
    val uiState: StateFlow<PosReceiptUiState> = _uiState.asStateFlow()

    init {
        val orderIdArg = savedStateHandle.get<String>("orderId") ?: ""
        viewModelScope.launch {
            coordinator.session.collect { session ->
                _uiState.update {
                    it.copy(
                        orderId = session.completedOrderId ?: orderIdArg,
                        invoiceId = session.completedInvoiceId,
                        totalCents = session.totalCents,
                        customerName = session.customer?.name ?: "",
                        customerPhone = session.customer?.phone,
                        customerEmail = session.customer?.email,
                        linkedTicketId = session.linkedTicketId,
                        trackingUrl = session.trackingUrl
                            ?: session.completedOrderId?.let { id -> "/track/$id" },
                    )
                }
            }
        }
    }

    fun sendSms() {
        val phone = _uiState.value.customerPhone ?: return
        val invoiceId = _uiState.value.invoiceId ?: return
        _uiState.update { it.copy(smsSentState = SendState.SENDING) }

        viewModelScope.launch {
            runCatching {
                receiptApi.sendReceiptSms(SendReceiptSmsRequest(invoiceId = invoiceId, phone = phone))
            }.onSuccess { resp ->
                _uiState.update {
                    it.copy(smsSentState = SendState.SENT, snackbarMessage = "SMS sent to $phone")
                }
            }.onFailure { e ->
                val is404 = e is HttpException && e.code() == 404
                if (is404) {
                    // POS-SMS-001: endpoint not yet deployed on this server version
                    Log.w("PosReceipt", "receipt_sms_unavailable: server returned 404 for send-receipt-sms")
                    _uiState.update {
                        it.copy(
                            smsSentState = SendState.ERROR,
                            snackbarMessage = "SMS receipt not yet available",
                        )
                    }
                } else {
                    _uiState.update {
                        it.copy(smsSentState = SendState.ERROR, snackbarMessage = "SMS failed: ${e.message}")
                    }
                }
            }
        }
    }

    fun sendEmail() {
        // Email receipt is handled server-side on invoice finalize (POS-RECEIPT-001).
        // The Android app shows sent state optimistically; real confirmation via webhook.
        _uiState.update { it.copy(emailSentState = SendState.SENT, snackbarMessage = "Email queued") }
    }

    fun clearSnackbar() = _uiState.update { it.copy(snackbarMessage = null) }

    fun startNewSale() = coordinator.resetSession()
}
