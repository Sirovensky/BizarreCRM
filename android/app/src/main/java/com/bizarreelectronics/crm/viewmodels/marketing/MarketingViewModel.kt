package com.bizarreelectronics.crm.viewmodels.marketing

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.CampaignDto
import com.bizarreelectronics.crm.data.remote.api.CampaignRunResult
import com.bizarreelectronics.crm.data.remote.api.CampaignStatsData
import com.bizarreelectronics.crm.data.remote.api.CreateCampaignRequest
import com.bizarreelectronics.crm.data.remote.api.CreateSegmentRequest
import com.bizarreelectronics.crm.data.remote.api.SegmentDto
import com.bizarreelectronics.crm.data.repository.MarketingRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject

// ─── UI state ──────────────────────────────────────────────────────────────────

data class MarketingUiState(
    val campaigns: List<CampaignDto> = emptyList(),
    val segments: List<SegmentDto> = emptyList(),
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,

    /** Selected status filter tab; "All" means no filter. */
    val selectedStatusTab: String = "All",

    /** Result card after a successful dispatch. Cleared by [clearDispatchResult]. */
    val lastDispatchResult: CampaignRunResult? = null,

    /** Stats for the currently-open campaign detail card. */
    val openCampaignStats: CampaignStatsData? = null,

    /** Non-null when a toast/snackbar message is pending. */
    val toastMessage: String? = null,

    /** Recipient-count preview before confirming a send. */
    val pendingSendPreviewCount: Int? = null,
    val pendingSendCampaignId: Long? = null,
)

/** Status tabs displayed on the campaign list screen. */
val CAMPAIGN_STATUS_TABS = listOf("All", "Draft", "Active", "Paused", "Archived")

// ─── ViewModel ────────────────────────────────────────────────────────────────

/**
 * ViewModel for §37 Marketing & Growth.
 *
 * Owns campaign list, segment list, send dispatch, and per-campaign stats.
 * The UI (MarketingScreen) reads from [state] and calls event functions.
 *
 * Send flow:
 *   1. User taps "Send to segment" → calls [requestSend].
 *   2. [requestSend] fetches recipient preview count → sets
 *      [MarketingUiState.pendingSendCampaignId] + [pendingSendPreviewCount].
 *   3. UI shows ConfirmDialog with recipient count.
 *   4. User confirms → [confirmSend] → dispatches → clears pending state,
 *      sets [lastDispatchResult].
 *   5. User cancels → [cancelSend] → clears pending state.
 *
 * Plan §37 (ActionPlan.md lines 3255-3360).
 */
@HiltViewModel
class MarketingViewModel @Inject constructor(
    private val repository: MarketingRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(MarketingUiState())
    val state = _state.asStateFlow()

    init {
        load()
    }

    // ── Public: load ──────────────────────────────────────────────────────────

    fun load() {
        viewModelScope.launch {
            _state.value = _state.value.copy(
                isLoading = _state.value.campaigns.isEmpty(),
                error = null,
            )
            try {
                val campaigns = repository.getCampaigns()
                val segments = repository.getSegments()
                _state.value = _state.value.copy(
                    campaigns = campaigns,
                    segments = segments,
                    isLoading = false,
                    isRefreshing = false,
                )
            } catch (e: Exception) {
                Timber.w(e, "MarketingViewModel.load failed")
                _state.value = _state.value.copy(
                    isLoading = false,
                    isRefreshing = false,
                    error = e.message ?: "Failed to load marketing data",
                )
            }
        }
    }

    fun refresh() {
        _state.value = _state.value.copy(isRefreshing = true, error = null)
        load()
    }

    fun selectStatusTab(tab: String) {
        _state.value = _state.value.copy(selectedStatusTab = tab)
    }

    // ── Public: campaigns ─────────────────────────────────────────────────────

    fun createCampaign(request: CreateCampaignRequest, onSuccess: () -> Unit) {
        viewModelScope.launch {
            try {
                repository.createCampaign(request)
                onSuccess()
                refresh()
            } catch (e: Exception) {
                Timber.w(e, "createCampaign failed")
                _state.value = _state.value.copy(
                    toastMessage = e.message ?: "Failed to create campaign",
                )
            }
        }
    }

    fun archiveCampaign(id: Long) {
        viewModelScope.launch {
            try {
                repository.patchCampaign(id, mapOf("status" to "archived"))
                refresh()
            } catch (e: Exception) {
                Timber.w(e, "archiveCampaign failed")
                _state.value = _state.value.copy(
                    toastMessage = e.message ?: "Failed to archive campaign",
                )
            }
        }
    }

    fun loadCampaignStats(campaignId: Long) {
        viewModelScope.launch {
            try {
                val stats = repository.getCampaignStats(campaignId)
                _state.value = _state.value.copy(openCampaignStats = stats)
            } catch (e: Exception) {
                Timber.w(e, "loadCampaignStats failed")
            }
        }
    }

    fun clearCampaignStats() {
        _state.value = _state.value.copy(openCampaignStats = null)
    }

    // ── Send flow ─────────────────────────────────────────────────────────────

    /**
     * Step 1 of the send flow: fetch preview recipient count, then set
     * [MarketingUiState.pendingSendCampaignId] so the UI shows ConfirmDialog.
     */
    fun requestSend(campaignId: Long) {
        viewModelScope.launch {
            try {
                val preview = repository.previewCampaign(campaignId)
                _state.value = _state.value.copy(
                    pendingSendCampaignId = campaignId,
                    pendingSendPreviewCount = preview?.totalRecipients,
                )
            } catch (e: Exception) {
                Timber.w(e, "requestSend preview failed")
                // Still open the confirm dialog; count will be null (unknown).
                _state.value = _state.value.copy(
                    pendingSendCampaignId = campaignId,
                    pendingSendPreviewCount = null,
                )
            }
        }
    }

    /**
     * Step 3 of the send flow: user confirmed — dispatch the campaign.
     */
    fun confirmSend() {
        val id = _state.value.pendingSendCampaignId ?: return
        cancelSend()
        viewModelScope.launch {
            try {
                val result = repository.runCampaignNow(id)
                _state.value = _state.value.copy(
                    lastDispatchResult = result,
                    toastMessage = "Sent to ${result.sent} recipients",
                )
                refresh()
            } catch (e: Exception) {
                Timber.w(e, "confirmSend failed")
                _state.value = _state.value.copy(
                    toastMessage = e.message ?: "Dispatch failed",
                )
            }
        }
    }

    /** User cancelled the send confirm dialog. */
    fun cancelSend() {
        _state.value = _state.value.copy(
            pendingSendCampaignId = null,
            pendingSendPreviewCount = null,
        )
    }

    fun clearDispatchResult() {
        _state.value = _state.value.copy(lastDispatchResult = null)
    }

    fun clearToast() {
        _state.value = _state.value.copy(toastMessage = null)
    }

    // ── Public: segments ──────────────────────────────────────────────────────

    fun createSegment(name: String, description: String?, onSuccess: () -> Unit) {
        viewModelScope.launch {
            try {
                repository.createSegment(
                    CreateSegmentRequest(
                        name = name.trim(),
                        description = description?.trim()?.ifBlank { null },
                    )
                )
                onSuccess()
                refresh()
            } catch (e: Exception) {
                Timber.w(e, "createSegment failed")
                _state.value = _state.value.copy(
                    toastMessage = e.message ?: "Failed to create segment",
                )
            }
        }
    }

    fun deleteSegment(id: Long) {
        viewModelScope.launch {
            try {
                repository.deleteSegment(id)
                refresh()
            } catch (e: Exception) {
                Timber.w(e, "deleteSegment failed")
                _state.value = _state.value.copy(
                    toastMessage = e.message ?: "Failed to delete segment",
                )
            }
        }
    }
}
