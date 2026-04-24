package com.bizarreelectronics.crm.ui.screens.estimates

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.entities.EstimateEntity
import com.bizarreelectronics.crm.data.remote.api.EstimateApi
import com.bizarreelectronics.crm.data.remote.api.EstimateVersion
import com.bizarreelectronics.crm.data.repository.EstimateRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import retrofit2.HttpException
import javax.inject.Inject

data class EstimateDetailUiState(
    val estimate: EstimateEntity? = null,
    val isLoading: Boolean = true,
    val error: String? = null,
    val actionMessage: String? = null,
    val isActionInProgress: Boolean = false,
    val convertedTicketId: Long? = null,
    // AND-20260414-M7: bump after a successful delete so the screen can
    // navigate back via a LaunchedEffect — keeps the click handler free of
    // navigation side effects and mirrors how InvoiceDetail uses a counter
    // to close its payment dialog.
    val deletedCounter: Int = 0,
    // L1335 — versioning
    val versions: List<EstimateVersion> = emptyList(),
    val selectedVersionIndex: Int = 0,
    // L1331/1332 — approve/reject pending dialogs
    val showApproveConfirm: Boolean = false,
    val showRejectDialog: Boolean = false,
    val rejectReason: String = "",
    // L1334 — convert-to-invoice converted id
    val convertedInvoiceId: Long? = null,
)

@HiltViewModel
class EstimateDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val estimateRepository: EstimateRepository,
    private val estimateApi: EstimateApi,
) : ViewModel() {

    private val estimateId: Long = savedStateHandle.get<String>("id")?.toLongOrNull() ?: 0L

    private val _state = MutableStateFlow(EstimateDetailUiState())
    val state = _state.asStateFlow()

    private var collectJob: Job? = null

    init {
        loadEstimate()
        loadVersions()
    }

    fun loadEstimate() {
        collectJob?.cancel()
        collectJob = viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            estimateRepository.getEstimate(estimateId)
                .catch { e ->
                    _state.value = _state.value.copy(
                        isLoading = false,
                        error = e.message ?: "Failed to load estimate",
                    )
                }
                .collectLatest { entity ->
                    _state.value = _state.value.copy(
                        estimate = entity,
                        isLoading = false,
                    )
                }
        }
    }

    // ── L1335 Versioning ─────────────────────────────────────────────────────

    fun loadVersions() {
        viewModelScope.launch {
            runCatching { estimateApi.getVersions(estimateId) }
                .onSuccess { response ->
                    _state.value = _state.value.copy(
                        versions = response.data ?: emptyList(),
                    )
                }
                .onFailure { e ->
                    // 404 = server doesn't support versions yet — silently use empty list
                    if (e is HttpException && e.code() == 404) {
                        _state.value = _state.value.copy(versions = emptyList())
                    }
                    // Other errors also silently ignored for versions (non-critical)
                }
        }
    }

    fun onVersionSelected(index: Int) {
        _state.value = _state.value.copy(selectedVersionIndex = index)
    }

    // ── L1333 Convert to Ticket ───────────────────────────────────────────────

    fun convertToTicket() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isActionInProgress = true)
            try {
                val ticketId = estimateRepository.convertEstimate(estimateId)
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = if (ticketId != null) "Converted to ticket #$ticketId" else "Estimate converted",
                    convertedTicketId = ticketId,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = e.message ?: "Failed to convert estimate. You must be online.",
                )
            }
        }
    }

    // ── L1334 Convert to Invoice ─────────────────────────────────────────────

    fun convertToInvoice() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isActionInProgress = true)
            runCatching { estimateApi.convertToInvoice(estimateId) }
                .onSuccess { response ->
                    val invoiceId = (response.data?.get("invoiceId") as? Number)?.toLong()
                    _state.value = _state.value.copy(
                        isActionInProgress = false,
                        actionMessage = if (invoiceId != null) "Converted to invoice #$invoiceId" else "Converted to invoice",
                        convertedInvoiceId = invoiceId,
                    )
                }
                .onFailure { e ->
                    val msg = if (e is HttpException && e.code() == 404) {
                        "Convert to invoice not available yet"
                    } else {
                        e.message ?: "Failed to convert to invoice"
                    }
                    _state.value = _state.value.copy(isActionInProgress = false, actionMessage = msg)
                }
        }
    }

    // ── L1330 Send ────────────────────────────────────────────────────────────

    fun sendViaSms() = send("sms")

    fun sendViaEmail() = send("email")

    private fun send(method: String) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isActionInProgress = true)
            try {
                estimateRepository.sendEstimate(estimateId, method)
                val label = if (method == "sms") "SMS" else "email"
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Estimate sent via $label",
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = e.message ?: "Failed to send estimate. You must be online.",
                )
            }
        }
    }

    // ── L1331 Approve ─────────────────────────────────────────────────────────

    fun onApproveRequested() {
        _state.value = _state.value.copy(showApproveConfirm = true)
    }

    fun onApproveDismissed() {
        _state.value = _state.value.copy(showApproveConfirm = false)
    }

    fun approveEstimate() {
        _state.value = _state.value.copy(showApproveConfirm = false, isActionInProgress = true)
        viewModelScope.launch {
            runCatching { estimateApi.approveEstimate(estimateId) }
                .onSuccess {
                    _state.value = _state.value.copy(
                        isActionInProgress = false,
                        actionMessage = "Estimate approved",
                    )
                    loadEstimate()
                }
                .onFailure { e ->
                    val msg = if (e is HttpException && e.code() == 404) {
                        "Approve not available yet"
                    } else {
                        e.message ?: "Failed to approve estimate"
                    }
                    _state.value = _state.value.copy(isActionInProgress = false, actionMessage = msg)
                }
        }
    }

    // ── L1332 Reject ──────────────────────────────────────────────────────────

    fun onRejectRequested() {
        _state.value = _state.value.copy(showRejectDialog = true, rejectReason = "")
    }

    fun onRejectDismissed() {
        _state.value = _state.value.copy(showRejectDialog = false, rejectReason = "")
    }

    fun onRejectReasonChanged(reason: String) {
        _state.value = _state.value.copy(rejectReason = reason)
    }

    fun rejectEstimate() {
        val reason = _state.value.rejectReason.trim()
        if (reason.isBlank()) {
            _state.value = _state.value.copy(actionMessage = "Rejection reason is required")
            return
        }
        _state.value = _state.value.copy(showRejectDialog = false, isActionInProgress = true)
        viewModelScope.launch {
            runCatching {
                estimateApi.rejectEstimate(estimateId, mapOf("reason" to reason))
            }
                .onSuccess {
                    _state.value = _state.value.copy(
                        isActionInProgress = false,
                        actionMessage = "Estimate rejected",
                        rejectReason = "",
                    )
                    loadEstimate()
                }
                .onFailure { e ->
                    val msg = if (e is HttpException && e.code() == 404) {
                        "Reject not available yet"
                    } else {
                        e.message ?: "Failed to reject estimate"
                    }
                    _state.value = _state.value.copy(isActionInProgress = false, actionMessage = msg)
                }
        }
    }

    // ── Delete ────────────────────────────────────────────────────────────────

    fun delete() {
        if (_state.value.isActionInProgress) return
        viewModelScope.launch {
            _state.value = _state.value.copy(isActionInProgress = true)
            try {
                estimateRepository.deleteEstimate(estimateId)
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Estimate deleted",
                    deletedCounter = _state.value.deletedCounter + 1,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = e.message ?: "Failed to delete estimate",
                )
            }
        }
    }

    // ── State helpers ─────────────────────────────────────────────────────────

    fun clearActionMessage() {
        _state.value = _state.value.copy(actionMessage = null)
    }

    fun clearConvertedTicket() {
        _state.value = _state.value.copy(convertedTicketId = null)
    }

    fun clearConvertedInvoice() {
        _state.value = _state.value.copy(convertedInvoiceId = null)
    }
}
