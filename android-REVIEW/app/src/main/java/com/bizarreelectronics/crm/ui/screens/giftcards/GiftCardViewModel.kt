package com.bizarreelectronics.crm.ui.screens.giftcards

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.GiftCard
import com.bizarreelectronics.crm.data.remote.api.GiftCardApi
import com.bizarreelectronics.crm.data.remote.api.GiftCardRedeemData
import com.bizarreelectronics.crm.data.remote.api.IssueCreditRequest
import com.bizarreelectronics.crm.data.remote.api.IssueGiftCardRequest
import com.bizarreelectronics.crm.data.remote.api.RedeemGiftCardRequest
import com.bizarreelectronics.crm.data.remote.api.StoreCredit
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import timber.log.Timber
import javax.inject.Inject

// ─── UI state ────────────────────────────────────────────────────────────────

sealed class GiftCardUiState {
    data object Idle : GiftCardUiState()
    data object Loading : GiftCardUiState()
    data object NotAvailable : GiftCardUiState()
    data class CardLookup(val card: GiftCard) : GiftCardUiState()
    data class RedeemSuccess(val result: GiftCardRedeemData) : GiftCardUiState()
    data class IssueSuccess(val card: GiftCard) : GiftCardUiState()
    data class Error(val message: String) : GiftCardUiState()
}

sealed class StoreCreditState {
    data object Idle : StoreCreditState()
    data object Loading : StoreCreditState()
    data class Loaded(val credit: StoreCredit) : StoreCreditState()
    data class Error(val message: String) : StoreCreditState()
}

// ─── ViewModel ───────────────────────────────────────────────────────────────

/**
 * Drives [GiftCardScreen]: issue, lookup, redeem, store-credit balance.
 *
 * 404-tolerant: transitions to [GiftCardUiState.NotAvailable] on first 404.
 * Plan §40 L3060-L3086.
 */
@HiltViewModel
class GiftCardViewModel @Inject constructor(
    private val api: GiftCardApi,
) : ViewModel() {

    private val _uiState = MutableStateFlow<GiftCardUiState>(GiftCardUiState.Idle)
    val uiState: StateFlow<GiftCardUiState> = _uiState.asStateFlow()

    private val _storeCreditState = MutableStateFlow<StoreCreditState>(StoreCreditState.Idle)
    val storeCreditState: StateFlow<StoreCreditState> = _storeCreditState.asStateFlow()

    // ─── Gift card operations ─────────────────────────────────────────────────

    /** Look up a gift card by code / barcode scan (§40.1). */
    fun lookupCard(code: String) {
        viewModelScope.launch {
            _uiState.value = GiftCardUiState.Loading
            try {
                val resp = api.getGiftCard(code)
                val card = resp.data?.card
                _uiState.value = if (card != null) {
                    GiftCardUiState.CardLookup(card)
                } else {
                    GiftCardUiState.Error("Card not found")
                }
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    _uiState.value = GiftCardUiState.NotAvailable
                } else {
                    _uiState.value = GiftCardUiState.Error(
                        e.message() ?: "Server error (${e.code()})"
                    )
                }
            } catch (e: Exception) {
                Timber.e(e, "GiftCardViewModel.lookupCard")
                _uiState.value = GiftCardUiState.Error(e.message ?: "Unknown error")
            }
        }
    }

    /**
     * Issue a new gift card (§40.1).
     *
     * @param amountCents  face value in cents
     * @param code         optional pre-printed barcode; null → server generates
     * @param customerId   optional customer link
     * @param sendDigital  send digital copy via email/SMS
     */
    fun issueGiftCard(
        amountCents: Long,
        code: String? = null,
        customerId: Long? = null,
        sendDigital: Boolean = false,
    ) {
        viewModelScope.launch {
            _uiState.value = GiftCardUiState.Loading
            try {
                val resp = api.issueGiftCard(
                    IssueGiftCardRequest(
                        code = code?.takeIf { it.isNotBlank() },
                        amountCents = amountCents,
                        customerId = customerId,
                        sendDigital = sendDigital,
                    )
                )
                val card = resp.data?.card
                _uiState.value = if (card != null) {
                    GiftCardUiState.IssueSuccess(card)
                } else {
                    GiftCardUiState.Error("Issue returned empty data")
                }
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    _uiState.value = GiftCardUiState.NotAvailable
                } else {
                    _uiState.value = GiftCardUiState.Error(e.message() ?: "Server error")
                }
            } catch (e: Exception) {
                Timber.e(e, "GiftCardViewModel.issueGiftCard")
                _uiState.value = GiftCardUiState.Error(e.message ?: "Unknown error")
            }
        }
    }

    /**
     * Redeem an amount from a gift card (§40.1). Partial redemption supported.
     *
     * @param code        card code / barcode
     * @param amountCents amount to redeem in cents (may be less than balance)
     */
    fun redeemGiftCard(code: String, amountCents: Long) {
        viewModelScope.launch {
            _uiState.value = GiftCardUiState.Loading
            try {
                val resp = api.redeemGiftCard(
                    RedeemGiftCardRequest(code = code, amountCents = amountCents)
                )
                val result = resp.data
                _uiState.value = if (result != null) {
                    GiftCardUiState.RedeemSuccess(result)
                } else {
                    GiftCardUiState.Error("Redeem returned empty data")
                }
            } catch (e: Exception) {
                Timber.e(e, "GiftCardViewModel.redeemGiftCard")
                _uiState.value = GiftCardUiState.Error(e.message ?: "Unknown error")
            }
        }
    }

    // ─── Store credit ─────────────────────────────────────────────────────────

    /**
     * Load store-credit balance for a customer (§40.2).
     */
    fun loadStoreCredit(customerId: Long) {
        viewModelScope.launch {
            _storeCreditState.value = StoreCreditState.Loading
            try {
                val resp = api.getStoreCredit(customerId)
                val credit = resp.data?.credit
                _storeCreditState.value = if (credit != null) {
                    StoreCreditState.Loaded(credit)
                } else {
                    StoreCreditState.Error("No store credit data")
                }
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    // 404 means no store credit record exists (balance = 0) or feature not available
                    _storeCreditState.value = StoreCreditState.Loaded(
                        com.bizarreelectronics.crm.data.remote.api.StoreCredit(
                            customerId = customerId,
                            balanceCents = 0L,
                            updatedAt = null,
                        )
                    )
                } else {
                    _storeCreditState.value = StoreCreditState.Error(
                        e.message() ?: "Server error (${e.code()})"
                    )
                }
            } catch (e: Exception) {
                Timber.e(e, "GiftCardViewModel.loadStoreCredit")
                _storeCreditState.value = StoreCreditState.Error(e.message ?: "Unknown error")
            }
        }
    }

    /**
     * Issue store credit to a customer (§40.2).
     */
    fun issueStoreCredit(customerId: Long, amountCents: Long, reason: String) {
        viewModelScope.launch {
            _storeCreditState.value = StoreCreditState.Loading
            try {
                val resp = api.issueStoreCredit(
                    customerId,
                    IssueCreditRequest(amountCents = amountCents, reason = reason),
                )
                val credit = resp.data?.credit
                _storeCreditState.value = if (credit != null) {
                    StoreCreditState.Loaded(credit)
                } else {
                    StoreCreditState.Error("Issue credit returned empty data")
                }
            } catch (e: Exception) {
                Timber.e(e, "GiftCardViewModel.issueStoreCredit")
                _storeCreditState.value = StoreCreditState.Error(e.message ?: "Unknown error")
            }
        }
    }

    fun reset() {
        _uiState.value = GiftCardUiState.Idle
    }
}
