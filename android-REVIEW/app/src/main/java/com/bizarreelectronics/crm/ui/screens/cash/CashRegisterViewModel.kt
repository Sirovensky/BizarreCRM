package com.bizarreelectronics.crm.ui.screens.cash

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.CashRegisterApi
import com.bizarreelectronics.crm.data.remote.api.CashShift
import com.bizarreelectronics.crm.data.remote.api.CloseShiftRequest
import com.bizarreelectronics.crm.data.remote.api.OpenShiftRequest
import com.bizarreelectronics.crm.data.remote.api.PayInOutRequest
import com.bizarreelectronics.crm.data.remote.api.ZReport
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import timber.log.Timber
import javax.inject.Inject

// ─── UI state ────────────────────────────────────────────────────────────────

sealed class CashRegisterUiState {
    data object Loading : CashRegisterUiState()
    data object NotAvailable : CashRegisterUiState()
    /** No shift is currently open — show "Open shift" dialog. */
    data object NoShift : CashRegisterUiState()
    /** A shift is open — show the running totals panel. */
    data class ShiftOpen(val shift: CashShift) : CashRegisterUiState()
    /** Z-report produced after closing a shift. */
    data class ZReportReady(val report: ZReport) : CashRegisterUiState()
    data class Error(val message: String) : CashRegisterUiState()
}

sealed class ShiftActionState {
    data object Idle : ShiftActionState()
    data object Loading : ShiftActionState()
    data class Error(val message: String) : ShiftActionState()
}

// ─── ViewModel ───────────────────────────────────────────────────────────────

/**
 * Drives [CashRegisterScreen]: shift open/close, X-report, pay-in/out.
 *
 * 404-tolerant: transitions to [CashRegisterUiState.NotAvailable] when the
 * server doesn't implement the cash-register endpoints.
 *
 * Plan §39 L3027-L3058.
 */
@HiltViewModel
class CashRegisterViewModel @Inject constructor(
    private val api: CashRegisterApi,
) : ViewModel() {

    private val _uiState = MutableStateFlow<CashRegisterUiState>(CashRegisterUiState.Loading)
    val uiState: StateFlow<CashRegisterUiState> = _uiState.asStateFlow()

    private val _actionState = MutableStateFlow<ShiftActionState>(ShiftActionState.Idle)
    val actionState: StateFlow<ShiftActionState> = _actionState.asStateFlow()

    init {
        loadCurrentShift()
    }

    fun loadCurrentShift() {
        viewModelScope.launch {
            _uiState.value = CashRegisterUiState.Loading
            try {
                val resp = api.getCurrentShift()
                val shift = resp.data?.shift
                _uiState.value = if (shift != null && shift.status == "open") {
                    CashRegisterUiState.ShiftOpen(shift)
                } else {
                    CashRegisterUiState.NoShift
                }
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    _uiState.value = CashRegisterUiState.NotAvailable
                } else {
                    _uiState.value = CashRegisterUiState.Error(
                        e.message() ?: "Server error (${e.code()})"
                    )
                }
            } catch (e: Exception) {
                Timber.e(e, "CashRegisterViewModel.loadCurrentShift")
                _uiState.value = CashRegisterUiState.Error(e.message ?: "Unknown error")
            }
        }
    }

    /**
     * Open a new cash shift (§39.1).
     *
     * @param registerId       device register identifier (e.g. "REG-01")
     * @param startingCashCents counted opening cash in cents
     */
    fun openShift(registerId: String, startingCashCents: Long) {
        viewModelScope.launch {
            _actionState.value = ShiftActionState.Loading
            try {
                val resp = api.openShift(
                    OpenShiftRequest(
                        registerId = registerId,
                        startingCashCents = startingCashCents,
                    )
                )
                val shift = resp.data?.shift
                _actionState.value = ShiftActionState.Idle
                _uiState.value = if (shift != null) {
                    CashRegisterUiState.ShiftOpen(shift)
                } else {
                    CashRegisterUiState.Error("Open shift returned empty data")
                }
            } catch (e: HttpException) {
                _actionState.value = ShiftActionState.Error(
                    e.message() ?: "Server error (${e.code()})"
                )
            } catch (e: Exception) {
                Timber.e(e, "CashRegisterViewModel.openShift")
                _actionState.value = ShiftActionState.Error(e.message ?: "Unknown error")
            }
        }
    }

    /**
     * Close the current shift and emit the Z-report (§39.1 / §39.2).
     *
     * @param shiftId           id of the shift to close
     * @param closingCashCents  counted closing cash in cents
     * @param overShortReason   optional reason when over/short exceeds threshold
     */
    fun closeShift(
        shiftId: Long,
        closingCashCents: Long,
        overShortReason: String? = null,
    ) {
        viewModelScope.launch {
            _actionState.value = ShiftActionState.Loading
            try {
                val resp = api.closeShift(
                    shiftId = shiftId,
                    request = CloseShiftRequest(
                        closingCashCents = closingCashCents,
                        overShortReason = overShortReason,
                    ),
                )
                val report = resp.data?.report
                _actionState.value = ShiftActionState.Idle
                _uiState.value = if (report != null) {
                    CashRegisterUiState.ZReportReady(report)
                } else {
                    CashRegisterUiState.Error("Close shift returned empty Z-report")
                }
            } catch (e: HttpException) {
                _actionState.value = ShiftActionState.Error(
                    e.message() ?: "Server error (${e.code()})"
                )
            } catch (e: Exception) {
                Timber.e(e, "CashRegisterViewModel.closeShift")
                _actionState.value = ShiftActionState.Error(e.message ?: "Unknown error")
            }
        }
    }

    /**
     * Fetch an X-report (mid-shift snapshot, §39.3) without closing.
     */
    fun fetchXReport(shiftId: Long) {
        viewModelScope.launch {
            _actionState.value = ShiftActionState.Loading
            try {
                val resp = api.getXReport(shiftId)
                val report = resp.data?.report
                _actionState.value = ShiftActionState.Idle
                if (report != null) {
                    _uiState.value = CashRegisterUiState.ZReportReady(report)
                }
            } catch (e: Exception) {
                Timber.e(e, "CashRegisterViewModel.fetchXReport")
                _actionState.value = ShiftActionState.Error(e.message ?: "Unknown error")
            }
        }
    }

    /**
     * Pay-in: add cash from petty (§39.5).
     */
    fun payIn(shiftId: Long, amountCents: Long, reason: String) {
        performPayInOut(shiftId, amountCents, reason, isPayIn = true)
    }

    /**
     * Pay-out: remove cash from drawer (§39.5).
     */
    fun payOut(shiftId: Long, amountCents: Long, reason: String) {
        performPayInOut(shiftId, amountCents, reason, isPayIn = false)
    }

    private fun performPayInOut(
        shiftId: Long,
        amountCents: Long,
        reason: String,
        isPayIn: Boolean,
    ) {
        viewModelScope.launch {
            _actionState.value = ShiftActionState.Loading
            try {
                val request = PayInOutRequest(amountCents = amountCents, reason = reason)
                val resp = if (isPayIn) api.payIn(shiftId, request) else api.payOut(shiftId, request)
                val shift = resp.data?.shift
                _actionState.value = ShiftActionState.Idle
                if (shift != null) {
                    _uiState.value = CashRegisterUiState.ShiftOpen(shift)
                }
            } catch (e: Exception) {
                Timber.e(e, "CashRegisterViewModel.performPayInOut")
                _actionState.value = ShiftActionState.Error(e.message ?: "Unknown error")
            }
        }
    }

    fun clearActionError() {
        _actionState.value = ShiftActionState.Idle
    }

    /** Reset to NoShift after the Z-report has been viewed/printed. */
    fun dismissZReport() {
        _uiState.value = CashRegisterUiState.NoShift
    }
}
