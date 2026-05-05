package com.bizarreelectronics.crm.ui.screens.refunds

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.CreateRefundRequest
import com.bizarreelectronics.crm.data.remote.api.RefundApi
import com.bizarreelectronics.crm.data.remote.api.RefundRow
import com.bizarreelectronics.crm.data.repository.PinRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import timber.log.Timber
import javax.inject.Inject

// ─── UI state ────────────────────────────────────────────────────────────────

sealed class RefundUiState {
    data object Idle : RefundUiState()
    data object Loading : RefundUiState()
    data object NotAvailable : RefundUiState()
    /** Pending refund created; id returned so manager can approve from list. */
    data class Created(val refundId: Long) : RefundUiState()
    data class Error(val message: String) : RefundUiState()
}

sealed class RefundListState {
    data object Loading : RefundListState()
    data object NotAvailable : RefundListState()
    data class Loaded(val refunds: List<RefundRow>) : RefundListState()
    data class Error(val message: String) : RefundListState()
}

// ─── ViewModel ───────────────────────────────────────────────────────────────

/**
 * Drives [RefundScreen]: create, list, approve, and decline refunds.
 *
 * §40.3 — original-tender refund path (card → card, cash → cash, gift → reload)
 * and store-credit alternative. Manager PIN threshold enforcement is handled
 * in the UI layer ([RefundScreen]) — the ViewModel accepts pre-validated input.
 *
 * 404-tolerant: transitions to [RefundUiState.NotAvailable] on first 404.
 */
@HiltViewModel
class RefundViewModel @Inject constructor(
    private val api: RefundApi,
    private val pinRepository: PinRepository,
) : ViewModel() {

    /**
     * Verify a manager PIN against the server (`POST /auth/verify-pin`).
     * Routes through [PinRepository] which already wraps the rate-limited
     * server endpoint — avoids embedding a static PIN in APK bytecode.
     * Returns true only on a confirmed Success result; lockouts/errors/wrong
     * PIN all return false so the dialog can show its generic error state.
     */
    suspend fun verifyManagerPin(pin: String): Boolean =
        pinRepository.verify(pin) is PinRepository.VerifyResult.Success

    private val _uiState = MutableStateFlow<RefundUiState>(RefundUiState.Idle)
    val uiState: StateFlow<RefundUiState> = _uiState.asStateFlow()

    private val _listState = MutableStateFlow<RefundListState>(RefundListState.Loading)
    val listState: StateFlow<RefundListState> = _listState.asStateFlow()

    init {
        loadRefunds()
    }

    // ─── List ─────────────────────────────────────────────────────────────────

    fun loadRefunds() {
        viewModelScope.launch {
            _listState.value = RefundListState.Loading
            try {
                val resp = api.listRefunds()
                val list = resp.data?.refunds ?: emptyList()
                _listState.value = RefundListState.Loaded(list)
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    _listState.value = RefundListState.NotAvailable
                } else {
                    _listState.value = RefundListState.Error(
                        e.message() ?: "Server error (${e.code()})"
                    )
                }
            } catch (e: Exception) {
                Timber.e(e, "RefundViewModel.loadRefunds")
                _listState.value = RefundListState.Error(e.message ?: "Unknown error")
            }
        }
    }

    // ─── Create ───────────────────────────────────────────────────────────────

    /**
     * Create a pending refund.
     *
     * @param invoiceId    optional — attach to a specific invoice
     * @param customerId   required
     * @param amountCents  refund amount in cents (stored as dollars on server)
     * @param type         "refund" | "store_credit" | "credit_note"
     * @param method       "cash" | "card" | "gift_card" | "store_credit" | null
     * @param reason       human-readable reason
     */
    fun createRefund(
        invoiceId: Long?,
        customerId: Long,
        amountCents: Long,
        type: String = "refund",
        method: String? = null,
        reason: String? = null,
    ) {
        viewModelScope.launch {
            _uiState.value = RefundUiState.Loading
            try {
                val resp = api.createRefund(
                    CreateRefundRequest(
                        invoiceId = invoiceId,
                        ticketId = null,
                        customerId = customerId,
                        amount = amountCents / 100.0,
                        type = type,
                        reason = reason?.takeIf { it.isNotBlank() },
                        method = method?.takeIf { it.isNotBlank() },
                    )
                )
                val id = resp.data?.id
                _uiState.value = if (id != null) {
                    RefundUiState.Created(id)
                } else {
                    RefundUiState.Error("Server returned empty response")
                }
            } catch (e: HttpException) {
                when (e.code()) {
                    403 -> _uiState.value = RefundUiState.Error(
                        "Manager or admin role required to create refunds"
                    )
                    404 -> _uiState.value = RefundUiState.NotAvailable
                    409 -> _uiState.value = RefundUiState.Error(
                        "Refund amount exceeds available balance"
                    )
                    else -> _uiState.value = RefundUiState.Error(
                        e.message() ?: "Server error (${e.code()})"
                    )
                }
            } catch (e: Exception) {
                Timber.e(e, "RefundViewModel.createRefund")
                _uiState.value = RefundUiState.Error(e.message ?: "Unknown error")
            }
        }
    }

    // ─── Approve / Decline ────────────────────────────────────────────────────

    fun approveRefund(id: Long) {
        viewModelScope.launch {
            try {
                api.approveRefund(id)
                loadRefunds()
            } catch (e: HttpException) {
                _uiState.value = RefundUiState.Error(
                    e.message() ?: "Approve failed (${e.code()})"
                )
            } catch (e: Exception) {
                Timber.e(e, "RefundViewModel.approveRefund")
                _uiState.value = RefundUiState.Error(e.message ?: "Approve failed")
            }
        }
    }

    fun declineRefund(id: Long) {
        viewModelScope.launch {
            try {
                api.declineRefund(id)
                loadRefunds()
            } catch (e: HttpException) {
                _uiState.value = RefundUiState.Error(
                    e.message() ?: "Decline failed (${e.code()})"
                )
            } catch (e: Exception) {
                Timber.e(e, "RefundViewModel.declineRefund")
                _uiState.value = RefundUiState.Error(e.message ?: "Decline failed")
            }
        }
    }

    fun reset() {
        _uiState.value = RefundUiState.Idle
    }
}
