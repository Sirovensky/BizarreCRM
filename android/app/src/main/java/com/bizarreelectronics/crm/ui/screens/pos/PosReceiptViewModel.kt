package com.bizarreelectronics.crm.ui.screens.pos

import android.util.Log
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.ReceiptNotificationApi
import com.bizarreelectronics.crm.data.remote.api.SendReceiptEmailRequest
import com.bizarreelectronics.crm.data.remote.api.SendReceiptSmsRequest
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import retrofit2.HttpException
import javax.inject.Inject

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
    val smsError: String? = null,
    val emailSentState: SendState = SendState.IDLE,
    val emailError: String? = null,
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
                        // Use server-supplied URL when available; fall back to
                        // client-built path only when the server didn't provide one.
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
        _uiState.update { it.copy(smsSentState = SendState.SENDING, smsError = null) }

        viewModelScope.launch {
            runCatching {
                receiptApi.sendReceiptSms(SendReceiptSmsRequest(invoiceId = invoiceId, phone = phone))
            }.onSuccess {
                _uiState.update {
                    it.copy(smsSentState = SendState.SENT, snackbarMessage = "SMS sent to $phone")
                }
            }.onFailure { e ->
                val is404 = e is HttpException && e.code() == 404
                val message = if (is404) {
                    // POS-SMS-001: endpoint not yet deployed on this server version
                    Log.w("PosReceipt", "receipt_sms_unavailable: server returned 404 for send-receipt-sms")
                    "SMS receipt not yet available"
                } else {
                    e.message ?: "SMS failed"
                }
                _uiState.update {
                    it.copy(smsSentState = SendState.ERROR, smsError = message, snackbarMessage = "SMS failed: $message")
                }
            }
        }
    }

    fun sendEmail() {
        val email = _uiState.value.customerEmail ?: return
        val invoiceId = _uiState.value.invoiceId ?: return
        _uiState.update { it.copy(emailSentState = SendState.SENDING, emailError = null) }

        viewModelScope.launch {
            runCatching {
                receiptApi.sendReceiptEmail(SendReceiptEmailRequest(invoiceId = invoiceId, recipientEmail = email))
            }.onSuccess {
                _uiState.update {
                    it.copy(emailSentState = SendState.SENT, snackbarMessage = "Email sent to $email")
                }
            }.onFailure { e ->
                val message = e.message ?: "Email failed"
                _uiState.update {
                    it.copy(emailSentState = SendState.ERROR, emailError = message, snackbarMessage = "Email failed: $message")
                }
            }
        }
    }

    fun clearSnackbar() = _uiState.update { it.copy(snackbarMessage = null) }

    fun startNewSale() = coordinator.resetSession()
}
