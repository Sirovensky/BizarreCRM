package com.bizarreelectronics.crm.ui.screens.giftcards

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.RefundApi
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import timber.log.Timber
import javax.inject.Inject

// ─── UI state ────────────────────────────────────────────────────────────────

sealed class LiabilityState {
    data object Loading : LiabilityState()
    data object NotAvailable : LiabilityState()
    data class Loaded(
        /** Outstanding gift-card balance owed to customers, in cents. §40.4 */
        val giftCardOutstandingCents: Long,
        /** Number of active gift cards contributing to that balance. */
        val activeGiftCardCount: Int,
        /**
         * Store-credit balance owed to customers, in cents.
         *
         * §40.4 — The server does not yet expose a dedicated store-credit
         * aggregate endpoint. This value is fetched from [RefundApi.listRefunds]
         * filtering by type="store_credit" and status="completed" when a dedicated
         * endpoint becomes available. For now it is always 0 until the server
         * exposes GET /store-credit/summary.
         * <!-- NOTE-defer: no GET /store-credit/summary endpoint exists yet -->
         */
        val storeCreditOutstandingCents: Long,
    ) : LiabilityState()
    data class Error(val message: String) : LiabilityState()
}

// ─── ViewModel ───────────────────────────────────────────────────────────────

/**
 * Drives [GiftCardLiabilityScreen].
 *
 * §40.4 — Fetches gift-card summary (outstanding balance + active count) from
 * [RefundApi.listGiftCards] and stub zero for store-credit until a dedicated
 * summary endpoint is available.
 *
 * 404-tolerant: transitions to [LiabilityState.NotAvailable] on 404.
 */
@HiltViewModel
class GiftCardLiabilityViewModel @Inject constructor(
    private val refundApi: RefundApi,
) : ViewModel() {

    private val _state = MutableStateFlow<LiabilityState>(LiabilityState.Loading)
    val state: StateFlow<LiabilityState> = _state.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            _state.value = LiabilityState.Loading
            try {
                // §40.4 — GET /gift-cards returns summary.total_outstanding (float dollars)
                // and active_count.
                val gcResp = refundApi.listGiftCards(status = "active", perPage = 1)
                val summary = gcResp.data?.summary

                val outstandingCents = ((summary?.totalOutstanding ?: 0.0) * 100).toLong()
                val activeCount = summary?.activeCount ?: 0

                // Store-credit aggregate: server has no dedicated summary endpoint yet.
                // Reported as 0 until GET /store-credit/summary lands.
                val storeCreditCents = 0L

                _state.value = LiabilityState.Loaded(
                    giftCardOutstandingCents = outstandingCents,
                    activeGiftCardCount = activeCount,
                    storeCreditOutstandingCents = storeCreditCents,
                )
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    _state.value = LiabilityState.NotAvailable
                } else {
                    _state.value = LiabilityState.Error(
                        e.message() ?: "Server error (${e.code()})"
                    )
                }
            } catch (e: Exception) {
                Timber.e(e, "GiftCardLiabilityViewModel.refresh")
                _state.value = LiabilityState.Error(e.message ?: "Unknown error")
            }
        }
    }
}
