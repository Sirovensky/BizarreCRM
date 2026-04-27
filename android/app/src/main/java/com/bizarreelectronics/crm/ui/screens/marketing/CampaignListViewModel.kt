package com.bizarreelectronics.crm.ui.screens.marketing

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.Campaign
import com.bizarreelectronics.crm.data.remote.api.CampaignStatsData
import com.bizarreelectronics.crm.data.repository.MarketingRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import timber.log.Timber
import javax.inject.Inject

// ─── UI state ────────────────────────────────────────────────────────────────

sealed class CampaignListUiState {
    data object Loading : CampaignListUiState()
    data object NotAvailable : CampaignListUiState()
    data class Loaded(val campaigns: List<Campaign>) : CampaignListUiState()
    data class Error(val message: String) : CampaignListUiState()
}

sealed class CampaignActionState {
    data object Idle : CampaignActionState()
    data object Loading : CampaignActionState()
    data class SendSuccess(val result: String) : CampaignActionState()
    data class Error(val message: String) : CampaignActionState()
}

// ─── ViewModel ───────────────────────────────────────────────────────────────

/**
 * Drives [CampaignListScreen]: status-tab filtered list of campaigns with
 * per-campaign metrics (sends / replies / converted).
 *
 * Plan §37.1 ActionPlan.md L2963-L2965.
 */
@HiltViewModel
class CampaignListViewModel @Inject constructor(
    private val repo: MarketingRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow<CampaignListUiState>(CampaignListUiState.Loading)
    val uiState: StateFlow<CampaignListUiState> = _uiState.asStateFlow()

    private val _actionState = MutableStateFlow<CampaignActionState>(CampaignActionState.Idle)
    val actionState: StateFlow<CampaignActionState> = _actionState.asStateFlow()

    /** Currently selected status tab filter (null = all). */
    private val _statusFilter = MutableStateFlow<String?>(null)
    val statusFilter: StateFlow<String?> = _statusFilter.asStateFlow()

    // All campaigns; filtered for display by [uiState] computation.
    private var allCampaigns: List<Campaign> = emptyList()

    init {
        load()
    }

    fun load() {
        viewModelScope.launch {
            _uiState.value = CampaignListUiState.Loading
            try {
                allCampaigns = repo.getCampaigns()
                applyFilter()
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    _uiState.value = CampaignListUiState.NotAvailable
                } else {
                    _uiState.value = CampaignListUiState.Error(
                        e.message() ?: "Server error (${e.code()})"
                    )
                }
            } catch (e: Exception) {
                Timber.e(e, "CampaignListViewModel.load")
                _uiState.value = CampaignListUiState.Error(e.message ?: "Unknown error")
            }
        }
    }

    fun setStatusFilter(status: String?) {
        _statusFilter.value = status
        applyFilter()
    }

    private fun applyFilter() {
        val filter = _statusFilter.value
        val filtered = if (filter == null) allCampaigns
        else allCampaigns.filter { it.status == filter }
        _uiState.value = CampaignListUiState.Loaded(filtered)
    }

    /**
     * Send a campaign immediately via POST /campaigns/:id/run-now (§37.1 / §37.2).
     * Caller should show ConfirmDialog before invoking.
     */
    fun runCampaignNow(campaign: Campaign) {
        viewModelScope.launch {
            _actionState.value = CampaignActionState.Loading
            try {
                val result = repo.runCampaignNow(campaign.id)
                val msg = if (result != null)
                    "Sent ${result.sent} / ${result.attempted} messages"
                else "Campaign dispatched"
                _actionState.value = CampaignActionState.SendSuccess(msg)
                load() // refresh counts
            } catch (e: HttpException) {
                _actionState.value = CampaignActionState.Error(
                    e.message() ?: "Server error (${e.code()})"
                )
            } catch (e: Exception) {
                Timber.e(e, "CampaignListViewModel.runCampaignNow id=${campaign.id}")
                _actionState.value = CampaignActionState.Error(e.message ?: "Unknown error")
            }
        }
    }

    fun resetActionState() {
        _actionState.value = CampaignActionState.Idle
    }
}
