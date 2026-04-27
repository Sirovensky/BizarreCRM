package com.bizarreelectronics.crm.ui.screens.marketing

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.Campaign
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

sealed class AutomationsUiState {
    data object Loading : AutomationsUiState()
    data object NotAvailable : AutomationsUiState()
    /**
     * Loaded: automation campaigns are those with a non-null [Campaign.triggerRuleJson]
     * OR a trigger type (birthday, winback, review_request, churn_warning).
     */
    data class Loaded(val automations: List<Campaign>) : AutomationsUiState()
    data class Error(val message: String) : AutomationsUiState()
}

sealed class AutomationActionState {
    data object Idle : AutomationActionState()
    data object Loading : AutomationActionState()
    data class DispatchSuccess(val result: DispatchResult) : AutomationActionState()
    data class StatusUpdateSuccess(val campaignName: String, val newStatus: String) : AutomationActionState()
    data class Error(val message: String) : AutomationActionState()
}

// ─── ViewModel ────────────────────────────────────────────────────────────────

/**
 * Drives [AutomationsScreen]: list of campaigns that are event- or cron-driven,
 * with activate/pause/run-now controls.
 *
 * The server models automations as campaigns with trigger_rule_json containing
 * either a cron expression or an event descriptor (e.g. `{"event":"ticket_pickup"}`).
 * Types birthday / winback / review_request / churn_warning are all automations.
 *
 * Plan §37.4 ActionPlan.md L2979-L2981.
 */
@HiltViewModel
class AutomationsViewModel @Inject constructor(
    private val repo: MarketingRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow<AutomationsUiState>(AutomationsUiState.Loading)
    val uiState: StateFlow<AutomationsUiState> = _uiState.asStateFlow()

    private val _actionState = MutableStateFlow<AutomationActionState>(AutomationActionState.Idle)
    val actionState: StateFlow<AutomationActionState> = _actionState.asStateFlow()

    // Known automation types (from server CAMPAIGN_TYPES)
    private val automationTypes = setOf(
        "birthday", "winback", "review_request", "churn_warning", "service_subscription"
    )

    init {
        load()
    }

    fun load() {
        viewModelScope.launch {
            _uiState.value = AutomationsUiState.Loading
            try {
                val all = repo.getCampaigns()
                // Filter: automation = non-custom type OR has trigger rule JSON
                val automations = all.filter { c ->
                    c.type in automationTypes || !c.triggerRuleJson.isNullOrBlank()
                }
                _uiState.value = AutomationsUiState.Loaded(automations)
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    _uiState.value = AutomationsUiState.NotAvailable
                } else {
                    _uiState.value = AutomationsUiState.Error(e.message() ?: "Server error (${e.code()})")
                }
            } catch (e: Exception) {
                Timber.e(e, "AutomationsViewModel.load")
                _uiState.value = AutomationsUiState.Error(e.message ?: "Unknown error")
            }
        }
    }

    /** Activate or pause an automation campaign. */
    fun setStatus(campaign: Campaign, active: Boolean) {
        viewModelScope.launch {
            _actionState.value = AutomationActionState.Loading
            try {
                val newStatus = if (active) "active" else "paused"
                repo.updateCampaign(
                    campaign.id,
                    com.bizarreelectronics.crm.data.remote.api.UpdateCampaignRequest(status = newStatus),
                )
                _actionState.value = AutomationActionState.StatusUpdateSuccess(campaign.name, newStatus)
                load()
            } catch (e: HttpException) {
                _actionState.value = AutomationActionState.Error(e.message() ?: "Server error (${e.code()})")
            } catch (e: Exception) {
                Timber.e(e, "AutomationsViewModel.setStatus id=${campaign.id}")
                _actionState.value = AutomationActionState.Error(e.message ?: "Unknown error")
            }
        }
    }

    /** Trigger a campaign dispatch immediately (run-now). */
    fun runNow(campaign: Campaign) {
        viewModelScope.launch {
            _actionState.value = AutomationActionState.Loading
            try {
                val result = repo.runCampaignNow(campaign.id)
                _actionState.value = if (result != null) {
                    AutomationActionState.DispatchSuccess(result)
                } else {
                    AutomationActionState.Error("No dispatch result returned")
                }
                load()
            } catch (e: HttpException) {
                _actionState.value = AutomationActionState.Error(e.message() ?: "Server error (${e.code()})")
            } catch (e: Exception) {
                Timber.e(e, "AutomationsViewModel.runNow id=${campaign.id}")
                _actionState.value = AutomationActionState.Error(e.message ?: "Unknown error")
            }
        }
    }

    fun resetActionState() {
        _actionState.value = AutomationActionState.Idle
    }
}
