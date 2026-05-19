package com.bizarreelectronics.crm.ui.screens.payments

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.CreatePaymentLinkRequest
import com.bizarreelectronics.crm.data.remote.api.PaymentLinkApi
import com.bizarreelectronics.crm.data.remote.api.PaymentLinkData
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update
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

    fun onAmountChanged(v: String) { _createState.update { it.copy(amountText = v) } }
    fun onMemoChanged(v: String) { _createState.update { it.copy(memo = v) } }
    fun onCustomerSelected(id: Long, name: String) {
        _createState.update { it.copy(customerId = id, customerName = name) }
    }
    fun onExpiryDaysChanged(days: Int) { _createState.update { it.copy(expiresInDays = days) } }
    fun onPartialAllowedChanged(v: Boolean) { _createState.update { it.copy(partialAllowed = v) } }

    fun createLink() {
        val s = _createState.value
        val amountDollars = s.amountText.toBigDecimalOrNull()
        if (amountDollars == null || amountDollars <= java.math.BigDecimal.ZERO) {
            _createState.update { it.copy(error = "Enter a valid amount") }
            return
        }
        // BUGHUNT-2026-05-17: round half-up instead of truncating. BigDecimal
        // .toLong() silently discards fractional cents, so "$5.999" entered
        // in the amount field generated a link for $5.99 instead of $6.00.
        // Always settle to whole cents using bankers'-style rounding before
        // sending to the server.
        val amountCents = amountDollars
            .multiply(java.math.BigDecimal(100))
            .setScale(0, java.math.RoundingMode.HALF_UP)
            .longValueExact()

        viewModelScope.launch {
            _createState.update { it.copy(isLoading = true, error = null) }
            try {
                val resp = paymentLinkApi.createLink(
                    CreatePaymentLinkRequest(
                        amount_cents = amountCents,
                        customer_id = s.customerId,
                        memo = s.memo.ifBlank { null },
                        expires_at = expiryIso(s.expiresInDays),
                        partial_allowed = s.partialAllowed,
                    )
                )
                _createState.update {
                    it.copy(
                        isLoading = false,
                        createdLink = resp.data,
                    )
                }
            } catch (e: CancellationException) {
                // BUGHUNT-2026-05-17: runCatching catches CancellationException
                // (kotlin.Result wraps Throwable). Switched to try/catch with
                // explicit re-throw so back-nav doesn't paint a fake "Failed
                // to create payment link" banner.
                throw e
            } catch (e: Exception) {
                val is404 = (e as? HttpException)?.code() == 404
                _createState.update {
                    it.copy(
                        isLoading = false,
                        notConfigured = is404,
                        error = if (is404) null else (e.message ?: "Failed to create payment link"),
                    )
                }
            }
        }
    }

    fun clearCreatedLink() {
        _createState.update { it.copy(createdLink = null) }
    }

    fun clearError() {
        _createState.update { it.copy(error = null) }
    }

    // ── List ─────────────────────────────────────────────────────────────────

    fun loadLinks() {
        viewModelScope.launch {
            _listState.update { it.copy(isLoading = true, error = null) }
            val filters = buildMap<String, String> {
                val status = _listState.value.selectedStatus
                if (status != "All") put("status", status.lowercase())
            }
            try {
                val resp = paymentLinkApi.listLinks(filters)
                _listState.update {
                    it.copy(
                        isLoading = false,
                        isRefreshing = false,
                        links = resp.data?.items ?: emptyList(),
                    )
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val is404 = (e as? HttpException)?.code() == 404
                _listState.update {
                    it.copy(
                        isLoading = false,
                        isRefreshing = false,
                        notConfigured = is404,
                        error = if (is404) null else (e.message ?: "Failed to load payment links"),
                    )
                }
            }
        }
    }

    fun refresh() {
        _listState.update { it.copy(isRefreshing = true) }
        loadLinks()
    }

    fun onStatusFilterChanged(status: String) {
        _listState.update { it.copy(selectedStatus = status) }
        loadLinks()
    }

    fun voidLink(id: Long) {
        viewModelScope.launch {
            try {
                paymentLinkApi.voidLink(id)
                _listState.update { it.copy(actionMessage = "Payment link voided") }
                loadLinks()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                val is404 = (e as? HttpException)?.code() == 404
                val reason = e.message?.takeIf { it.isNotBlank() }
                _listState.update {
                    it.copy(
                        actionMessage = when {
                            is404 -> "Void not supported on this server"
                            reason != null -> "Failed to void link: $reason"
                            else -> "Failed to void payment link"
                        },
                    )
                }
            }
        }
    }

    fun resendLink(id: Long) {
        viewModelScope.launch {
            try {
                paymentLinkApi.resendLink(id)
                _listState.update { it.copy(actionMessage = "Payment request resent") }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // Surface the underlying failure (network/auth/etc) so the user
                // can act on it instead of staring at a bare "Failed to resend".
                val reason = e.message?.takeIf { it.isNotBlank() }
                _listState.update {
                    it.copy(
                        actionMessage = if (reason != null) "Failed to resend: $reason"
                        else "Failed to resend payment request",
                    )
                }
            }
        }
    }

    fun remindCustomer(id: Long) {
        viewModelScope.launch {
            try {
                paymentLinkApi.remindCustomer(id)
                _listState.update { it.copy(actionMessage = "Reminder sent") }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // Same rationale as resendLink — opaque "Failed" hides the cause.
                val reason = e.message?.takeIf { it.isNotBlank() }
                _listState.update {
                    it.copy(
                        actionMessage = if (reason != null) "Failed to send reminder: $reason"
                        else "Failed to send payment reminder",
                    )
                }
            }
        }
    }

    fun clearActionMessage() {
        _listState.update { it.copy(actionMessage = null) }
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
