package com.bizarreelectronics.crm.ui.screens.marketing

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.CreateSegmentRequest
import com.bizarreelectronics.crm.data.remote.api.CustomerSegment
import com.bizarreelectronics.crm.data.remote.api.SegmentMembersData
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

sealed class SegmentsUiState {
    data object Loading : SegmentsUiState()
    data object NotAvailable : SegmentsUiState()
    data class Loaded(val segments: List<CustomerSegment>) : SegmentsUiState()
    data class Error(val message: String) : SegmentsUiState()
}

sealed class SegmentActionState {
    data object Idle : SegmentActionState()
    data object Loading : SegmentActionState()
    data class Success(val message: String) : SegmentActionState()
    data class Error(val message: String) : SegmentActionState()
}

sealed class SegmentSizeState {
    data object Idle : SegmentSizeState()
    data object Loading : SegmentSizeState()
    data class Loaded(val data: SegmentMembersData) : SegmentSizeState()
    data class Error(val message: String) : SegmentSizeState()
}

// ─── ViewModel ────────────────────────────────────────────────────────────────

/**
 * Drives [SegmentsScreen]: list all segments, create new segment, refresh
 * membership, and preview segment size.
 *
 * Plan §37.3 ActionPlan.md L2974-L2977.
 */
@HiltViewModel
class SegmentsViewModel @Inject constructor(
    private val repo: MarketingRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow<SegmentsUiState>(SegmentsUiState.Loading)
    val uiState: StateFlow<SegmentsUiState> = _uiState.asStateFlow()

    private val _actionState = MutableStateFlow<SegmentActionState>(SegmentActionState.Idle)
    val actionState: StateFlow<SegmentActionState> = _actionState.asStateFlow()

    private val _sizeState = MutableStateFlow<SegmentSizeState>(SegmentSizeState.Idle)
    val sizeState: StateFlow<SegmentSizeState> = _sizeState.asStateFlow()

    init {
        load()
    }

    fun load() {
        viewModelScope.launch {
            _uiState.value = SegmentsUiState.Loading
            try {
                val segments = repo.getSegments()
                _uiState.value = SegmentsUiState.Loaded(segments)
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    _uiState.value = SegmentsUiState.NotAvailable
                } else {
                    _uiState.value = SegmentsUiState.Error(e.message() ?: "Server error (${e.code()})")
                }
            } catch (e: Exception) {
                Timber.e(e, "SegmentsViewModel.load")
                _uiState.value = SegmentsUiState.Error(e.message ?: "Unknown error")
            }
        }
    }

    /** Create a new segment with the given rule JSON (§37.3). */
    fun createSegment(name: String, description: String?, ruleJson: String) {
        viewModelScope.launch {
            _actionState.value = SegmentActionState.Loading
            try {
                val seg = repo.createSegment(
                    CreateSegmentRequest(
                        name = name,
                        description = description?.takeIf { it.isNotBlank() },
                        ruleJson = ruleJson,
                        isAuto = 0,
                    )
                )
                if (seg != null) {
                    _actionState.value = SegmentActionState.Success("Segment \"${seg.name}\" created")
                    load()
                } else {
                    _actionState.value = SegmentActionState.Error("Server returned empty response")
                }
            } catch (e: HttpException) {
                _actionState.value = SegmentActionState.Error(e.message() ?: "Server error (${e.code()})")
            } catch (e: Exception) {
                Timber.e(e, "SegmentsViewModel.createSegment")
                _actionState.value = SegmentActionState.Error(e.message ?: "Unknown error")
            }
        }
    }

    /** Re-evaluate segment rule and update member count (§37.3). */
    fun refreshSegment(id: Long) {
        viewModelScope.launch {
            _actionState.value = SegmentActionState.Loading
            try {
                val seg = repo.refreshSegment(id)
                _actionState.value = SegmentActionState.Success(
                    "Refreshed — ${seg?.memberCount ?: 0} members"
                )
                load()
            } catch (e: HttpException) {
                _actionState.value = SegmentActionState.Error(e.message() ?: "Server error (${e.code()})")
            } catch (e: Exception) {
                Timber.e(e, "SegmentsViewModel.refreshSegment id=$id")
                _actionState.value = SegmentActionState.Error(e.message ?: "Unknown error")
            }
        }
    }

    /** Load segment size preview (§37.3). */
    fun loadSizePreview(id: Long) {
        viewModelScope.launch {
            _sizeState.value = SegmentSizeState.Loading
            try {
                val data = repo.getSegmentMembers(id)
                if (data != null) {
                    _sizeState.value = SegmentSizeState.Loaded(data)
                } else {
                    _sizeState.value = SegmentSizeState.Error("No data")
                }
            } catch (e: Exception) {
                Timber.e(e, "SegmentsViewModel.loadSizePreview id=$id")
                _sizeState.value = SegmentSizeState.Error(e.message ?: "Unknown error")
            }
        }
    }

    fun resetActionState() {
        _actionState.value = SegmentActionState.Idle
    }

    fun resetSizeState() {
        _sizeState.value = SegmentSizeState.Idle
    }
}
