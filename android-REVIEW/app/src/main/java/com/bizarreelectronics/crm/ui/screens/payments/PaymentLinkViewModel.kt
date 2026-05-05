package com.bizarreelectronics.crm.ui.screens.payments

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.CreatePaymentLinkRequest
import com.bizarreelectronics.crm.data.remote.api.PaymentLinkApi
import com.bizarreelectronics.crm.data.remote.api.PaymentLinkData
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import javax.inject.Inject

// ── UI state ──────────────────────────────────────────────────────────────────

data class PaymentLinkCreateState(
    val amountText: String = "",
    val memo: String = "",
    val customerId: Long? = null,
    val customerName: String = "",
    val expiresInDays: Int = 7,
    val partialAllowed: Boolean = false,
    val isLoading: Boolean = false,
    val createdLink: PaymentLinkData? = null,
    val error: String? = null,
    /** true when server returns 404 — feature not deployed on this tenant */
    val notConfigured: Boolean = false,
)

data class PaymentLinkListState(
    val links: List<PaymentLinkData> = emptyList(),
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val selectedStatus: String = "All",   // All | Pending | Paid | Expired | Cancelled
    val error: String? = null,
    val notConfigured: Boolean = false,
    val actionMessage: String? = null,
)

// ── ViewModel ─────────────────────────────────────────────────────────────────

@HiltViewModel
class PaymentLinkViewModel @Inject constructor(
    private val paymentLinkApi: PaymentLinkApi,
) : ViewModel() {

    // Create-link state
    private val _createState = MutableStateFlow(PaymentLinkCreateState())
    val createState = _createState.asStateFlow()

    // List state
    private val _listState = MutableStateFlow(PaymentLinkListState())
    val listState = _listState.asStateFlow()

    // ── Create form ──────────────────────────────────────────────────────────

    fun onAmountChanged(v: String) { _createState.value = _createState.value.copy(amountText = v) }
    fun onMemoChanged(v: String) { _createState.value = _createState.value.copy(memo = v) }
    fun onCustomerSelected(id: Long, name: String) {
        _createState.value = _createState.value.copy(customerId = id, customerName = name)
    }
    fun onExpiryDaysChanged(days: Int) { _createState.value = _createState.value.copy(expiresInDays = days) }
    fun onPartialAllowedChanged(v: Boolean) { _createState.value = _createState.value.copy(partialAllowed = v) }

    fun createLink() {
        val s = _createState.value
        val amountDollars = s.amountText.toBigDecimalOrNull()
        if (amountDollars == null || amountDollars <= java.math.BigDecimal.ZERO) {
            _createState.value = s.copy(error = "Enter a valid amount")
            return
        }
        val amountCents = (amountDollars * java.math.BigDecimal(100)).toLong()

        viewModelScope.launch {
            _createState.value = s.copy(isLoading = true, error = null)
            runCatching {
                paymentLinkApi.createLink(
                    CreatePaymentLinkRequest(
                        amount_cents = amountCents,
                        customer_id = s.customerId,
                        memo = s.memo.ifBlank { null },
                        expires_at = expiryIso(s.expiresInDays),
                        partial_allowed = s.partialAllowed,
                    )
                )
            }.onSuccess { resp ->
                _createState.value = _createState.value.copy(
                    isLoading = false,
                    createdLink = resp.data,
                )
            }.onFailure { e ->
                val is404 = (e as? HttpException)?.code() == 404
                _createState.value = _createState.value.copy(
                    isLoading = false,
                    notConfigured = is404,
                    error = if (is404) null else (e.message ?: "Failed to create payment link"),
                )
            }
        }
    }

    fun clearCreatedLink() {
        _createState.value = _createState.value.copy(createdLink = null)
    }

    fun clearError() {
        _createState.value = _createState.value.copy(error = null)
    }

    // ── List ─────────────────────────────────────────────────────────────────

    fun loadLinks() {
        viewModelScope.launch {
            _listState.value = _listState.value.copy(isLoading = true, error = null)
            val filters = buildMap<String, String> {
                val status = _listState.value.selectedStatus
                if (status != "All") put("status", status.lowercase())
            }
            runCatching { paymentLinkApi.listLinks(filters) }
                .onSuccess { resp ->
                    _listState.value = _listState.value.copy(
                        isLoading = false,
                        isRefreshing = false,
                        links = resp.data?.items ?: emptyList(),
                    )
                }
                .onFailure { e ->
                    val is404 = (e as? HttpException)?.code() == 404
                    _listState.value = _listState.value.copy(
                        isLoading = false,
                        isRefreshing = false,
                        notConfigured = is404,
                        error = if (is404) null else (e.message ?: "Failed to load payment links"),
                    )
                }
        }
    }

    fun refresh() {
        _listState.value = _listState.value.copy(isRefreshing = true)
        loadLinks()
    }

    fun onStatusFilterChanged(status: String) {
        _listState.value = _listState.value.copy(selectedStatus = status)
        loadLinks()
    }

    fun voidLink(id: Long) {
        viewModelScope.launch {
            runCatching { paymentLinkApi.voidLink(id) }
                .onSuccess {
                    _listState.value = _listState.value.copy(actionMessage = "Payment link voided")
                    loadLinks()
                }
                .onFailure { e ->
                    val is404 = (e as? HttpException)?.code() == 404
                    _listState.value = _listState.value.copy(
                        actionMessage = if (is404) "Void not supported on this server"
                        else "Failed to void link",
                    )
                }
        }
    }

    fun resendLink(id: Long) {
        viewModelScope.launch {
            runCatching { paymentLinkApi.resendLink(id) }
                .onSuccess {
                    _listState.value = _listState.value.copy(actionMessage = "Payment request resent")
                }
                .onFailure {
                    _listState.value = _listState.value.copy(actionMessage = "Failed to resend")
                }
        }
    }

    fun remindCustomer(id: Long) {
        viewModelScope.launch {
            runCatching { paymentLinkApi.remindCustomer(id) }
                .onSuccess {
                    _listState.value = _listState.value.copy(actionMessage = "Reminder sent")
                }
                .onFailure {
                    _listState.value = _listState.value.copy(actionMessage = "Failed to send reminder")
                }
        }
    }

    fun clearActionMessage() {
        _listState.value = _listState.value.copy(actionMessage = null)
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private fun expiryIso(days: Int): String {
        val cal = java.util.Calendar.getInstance().apply { add(java.util.Calendar.DAY_OF_YEAR, days) }
        return java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", java.util.Locale.US)
            .apply { timeZone = java.util.TimeZone.getTimeZone("UTC") }
            .format(cal.time)
    }

    init { loadLinks() }
}
