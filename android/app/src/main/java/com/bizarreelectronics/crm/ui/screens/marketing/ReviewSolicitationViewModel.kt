package com.bizarreelectronics.crm.ui.screens.marketing

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.DispatchResult
import com.bizarreelectronics.crm.data.repository.MarketingRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import timber.log.Timber
import javax.inject.Inject

// ─── UI state ─────────────────────────────────────────────────────────────────

sealed class ReviewSolicitationUiState {
    data object Idle : ReviewSolicitationUiState()
    data object Sending : ReviewSolicitationUiState()
    data class Success(val result: DispatchResult) : ReviewSolicitationUiState()
    data class NoCampaign(val message: String) : ReviewSolicitationUiState()
    data class Error(val message: String) : ReviewSolicitationUiState()
}

// ─── ViewModel ────────────────────────────────────────────────────────────────

/**
 * Drives [ReviewSolicitationScreen]: trigger a review-request SMS after
 * a ticket is closed.
 *
 * Calls POST /campaigns/review-request/trigger which finds the active
 * `review_request` campaign and sends it to the ticket's customer.
 *
 * Partial implementation — server sends SMS with `{{review_link}}` merge tag.
 * NPS scoring and detractor-vs-promoter routing are deferred (no server
 * endpoints exist for NPS response ingestion or conditional routing).
 *
 * Plan §37.5 ActionPlan.md L2983-L2985.
 */
@HiltViewModel
class ReviewSolicitationViewModel @Inject constructor(
    private val repo: MarketingRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow<ReviewSolicitationUiState>(ReviewSolicitationUiState.Idle)
    val uiState: StateFlow<ReviewSolicitationUiState> = _uiState.asStateFlow()

    /**
     * Send a review-request SMS for the given ticket.
     * Server no-ops gracefully if no active review_request campaign exists.
     */
    fun triggerReviewRequest(ticketId: Long) {
        viewModelScope.launch {
            _uiState.value = ReviewSolicitationUiState.Sending
            try {
                val result = repo.triggerReviewRequest(ticketId)
                if (result != null && result.sent > 0) {
                    _uiState.value = ReviewSolicitationUiState.Success(result)
                } else if (result != null && result.sent == 0 && result.attempted == 0) {
                    _uiState.value = ReviewSolicitationUiState.NoCampaign(
                        "No active review-request campaign. Activate one in Automations first."
                    )
                } else {
                    _uiState.value = ReviewSolicitationUiState.Success(
                        result ?: DispatchResult(0, 0, 0, 0)
                    )
                }
            } catch (e: HttpException) {
                _uiState.value = ReviewSolicitationUiState.Error(
                    e.message() ?: "Server error (${e.code()})"
                )
            } catch (e: Exception) {
                Timber.e(e, "ReviewSolicitationViewModel.triggerReviewRequest ticketId=$ticketId")
                _uiState.value = ReviewSolicitationUiState.Error(e.message ?: "Unknown error")
            }
        }
    }

    fun reset() {
        _uiState.value = ReviewSolicitationUiState.Idle
    }
}
