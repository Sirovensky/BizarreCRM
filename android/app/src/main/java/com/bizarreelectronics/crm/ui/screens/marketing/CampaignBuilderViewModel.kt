package com.bizarreelectronics.crm.ui.screens.marketing

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.Campaign
import com.bizarreelectronics.crm.data.remote.api.CampaignPreviewData
import com.bizarreelectronics.crm.data.remote.api.CreateCampaignRequest
import com.bizarreelectronics.crm.data.remote.api.CustomerSegment
import com.bizarreelectronics.crm.data.remote.api.UpdateCampaignRequest
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

/** Current wizard step (0-indexed). */
enum class BuilderStep { AUDIENCE, MESSAGE, REVIEW }

sealed class BuilderUiState {
    data object Idle : BuilderUiState()
    data object Saving : BuilderUiState()
    data object NotAvailable : BuilderUiState()
    data class SaveSuccess(val campaign: Campaign) : BuilderUiState()
    data class Error(val message: String) : BuilderUiState()
}

sealed class SegmentLoadState {
    data object Loading : SegmentLoadState()
    data class Loaded(val segments: List<CustomerSegment>) : SegmentLoadState()
    data class Error(val message: String) : SegmentLoadState()
}

sealed class PreviewState {
    data object Idle : PreviewState()
    data object Loading : PreviewState()
    data class Loaded(val preview: CampaignPreviewData) : PreviewState()
    data class Error(val message: String) : PreviewState()
}

// ─── ViewModel ────────────────────────────────────────────────────────────────

/**
 * Drives [CampaignBuilderScreen]: multi-step campaign creation wizard.
 *
 * Steps: Audience (segment) → Message (channel + body) → Review + preview.
 *
 * Plan §37.2 ActionPlan.md L2967-L2972.
 *
 * NOTE: A/B test variant (§37.2) and scheduled/recurring sends (§37.2) are
 * deferred — the server schema has no `variant_b_body`, `scheduled_at`, or
 * `recurring_cron` column in marketing_campaigns. Merge-tags are listed in the
 * UI as a reference chip row.
 */
@HiltViewModel
class CampaignBuilderViewModel @Inject constructor(
    private val repo: MarketingRepository,
) : ViewModel() {

    // ── Wizard state ──────────────────────────────────────────────────────────

    val step = MutableStateFlow(BuilderStep.AUDIENCE)

    // Audience step
    val campaignName = MutableStateFlow("")
    val campaignType = MutableStateFlow("custom")
    val selectedSegmentId = MutableStateFlow<Long?>(null)

    // Message step
    val channel = MutableStateFlow("sms")
    val templateBody = MutableStateFlow("")
    val templateSubject = MutableStateFlow("")

    // ── Remote states ──────────────────────────────────────────────────────────

    private val _builderUiState = MutableStateFlow<BuilderUiState>(BuilderUiState.Idle)
    val builderUiState: StateFlow<BuilderUiState> = _builderUiState.asStateFlow()

    private val _segmentLoadState = MutableStateFlow<SegmentLoadState>(SegmentLoadState.Loading)
    val segmentLoadState: StateFlow<SegmentLoadState> = _segmentLoadState.asStateFlow()

    private val _previewState = MutableStateFlow<PreviewState>(PreviewState.Idle)
    val previewState: StateFlow<PreviewState> = _previewState.asStateFlow()

    // ── Segment picker ────────────────────────────────────────────────────────

    init {
        loadSegments()
    }

    fun loadSegments() {
        viewModelScope.launch {
            _segmentLoadState.value = SegmentLoadState.Loading
            try {
                val segments = repo.getSegments()
                _segmentLoadState.value = SegmentLoadState.Loaded(segments)
            } catch (e: Exception) {
                Timber.e(e, "CampaignBuilderViewModel.loadSegments")
                _segmentLoadState.value = SegmentLoadState.Error(e.message ?: "Unknown error")
            }
        }
    }

    // ── Preview (Review step) ─────────────────────────────────────────────────

    /**
     * Preview audience size + rendered sample messages for a saved campaign.
     * Called in the Review step when the campaign has been saved in draft.
     */
    fun loadPreview(campaignId: Long) {
        viewModelScope.launch {
            _previewState.value = PreviewState.Loading
            try {
                val preview = repo.previewCampaign(campaignId)
                if (preview != null) {
                    _previewState.value = PreviewState.Loaded(preview)
                } else {
                    _previewState.value = PreviewState.Error("Preview unavailable")
                }
            } catch (e: HttpException) {
                _previewState.value = PreviewState.Error(
                    e.message() ?: "Server error (${e.code()})"
                )
            } catch (e: Exception) {
                Timber.e(e, "CampaignBuilderViewModel.loadPreview")
                _previewState.value = PreviewState.Error(e.message ?: "Unknown error")
            }
        }
    }

    // ── Navigation ────────────────────────────────────────────────────────────

    fun goNextStep() {
        val current = step.value
        val next = when (current) {
            BuilderStep.AUDIENCE -> BuilderStep.MESSAGE
            BuilderStep.MESSAGE  -> BuilderStep.REVIEW
            BuilderStep.REVIEW   -> BuilderStep.REVIEW
        }
        step.value = next
    }

    fun goPreviousStep() {
        val current = step.value
        val prev = when (current) {
            BuilderStep.AUDIENCE -> BuilderStep.AUDIENCE
            BuilderStep.MESSAGE  -> BuilderStep.AUDIENCE
            BuilderStep.REVIEW   -> BuilderStep.MESSAGE
        }
        step.value = prev
    }

    // ── Save ──────────────────────────────────────────────────────────────────

    /** Create the campaign in draft status (§37.2). */
    fun saveDraft() {
        viewModelScope.launch {
            _builderUiState.value = BuilderUiState.Saving
            try {
                val campaign = repo.createCampaign(
                    CreateCampaignRequest(
                        name = campaignName.value.trim(),
                        type = campaignType.value,
                        channel = channel.value,
                        templateBody = templateBody.value.trim(),
                        templateSubject = templateSubject.value.takeIf { it.isNotBlank() },
                        segmentId = selectedSegmentId.value,
                    )
                )
                if (campaign != null) {
                    _builderUiState.value = BuilderUiState.SaveSuccess(campaign)
                    loadPreview(campaign.id)
                } else {
                    _builderUiState.value = BuilderUiState.Error("Server returned empty response")
                }
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    _builderUiState.value = BuilderUiState.NotAvailable
                } else {
                    _builderUiState.value = BuilderUiState.Error(
                        e.message() ?: "Server error (${e.code()})"
                    )
                }
            } catch (e: Exception) {
                Timber.e(e, "CampaignBuilderViewModel.saveDraft")
                _builderUiState.value = BuilderUiState.Error(e.message ?: "Unknown error")
            }
        }
    }

    fun resetBuilderState() {
        _builderUiState.value = BuilderUiState.Idle
    }
}
