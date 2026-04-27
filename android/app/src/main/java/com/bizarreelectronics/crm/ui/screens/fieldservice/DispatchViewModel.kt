package com.bizarreelectronics.crm.ui.screens.fieldservice

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.dto.DispatchJobDetail
import com.bizarreelectronics.crm.data.repository.DispatchRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

// ---------------------------------------------------------------------------
// Job status constants (mirrors server-side VALID_JOB_STATUSES)
// ---------------------------------------------------------------------------

object DispatchJobStatus {
    const val UNASSIGNED = "unassigned"
    const val ASSIGNED   = "assigned"
    const val EN_ROUTE   = "en_route"
    const val ON_SITE    = "on_site"
    const val COMPLETED  = "completed"
    const val CANCELED   = "canceled"
    const val DEFERRED   = "deferred"
}

// ---------------------------------------------------------------------------
// UI state
// ---------------------------------------------------------------------------

data class DispatchUiState(
    val jobs: List<DispatchJobDetail> = emptyList(),
    val isLoading: Boolean = false,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val toastMessage: String? = null,
    /** When non-null the cancel confirmation dialog should be shown for this job. */
    val pendingCancelJobId: Long? = null,
    /** When non-null a status transition is in flight for this job (disables action buttons). */
    val transitioningJobId: Long? = null,
)

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

@HiltViewModel
class DispatchViewModel @Inject constructor(
    private val repository: DispatchRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(DispatchUiState())
    val state = _state.asStateFlow()

    private var loadJob: Job? = null

    init {
        load()
    }

    // -----------------------------------------------------------------------
    // Load / refresh
    // -----------------------------------------------------------------------

    fun load() {
        loadJob?.cancel()
        loadJob = viewModelScope.launch {
            _state.update { it.copy(isLoading = true, error = null) }
            runCatching { repository.getTodayJobs() }
                .onSuccess { jobs ->
                    _state.update { it.copy(jobs = jobs, isLoading = false) }
                }
                .onFailure { e ->
                    _state.update {
                        it.copy(
                            isLoading = false,
                            error = e.message ?: "Failed to load jobs",
                        )
                    }
                }
        }
    }

    fun refresh() {
        if (_state.value.isRefreshing) return
        viewModelScope.launch {
            _state.update { it.copy(isRefreshing = true, error = null) }
            runCatching { repository.getTodayJobs() }
                .onSuccess { jobs ->
                    _state.update { it.copy(jobs = jobs, isRefreshing = false) }
                }
                .onFailure { e ->
                    _state.update {
                        it.copy(
                            isRefreshing = false,
                            error = e.message ?: "Refresh failed",
                        )
                    }
                }
        }
    }

    // -----------------------------------------------------------------------
    // Job transitions
    // -----------------------------------------------------------------------

    /**
     * Tech accepts an assigned job — transitions to en_route.
     * Corresponds to: assigned → en_route
     */
    fun acceptJob(jobId: Long, lat: Double? = null, lng: Double? = null) {
        transitionJob(jobId, DispatchJobStatus.EN_ROUTE, lat = lat, lng = lng)
    }

    /**
     * Tech marks arrival — transitions en_route → on_site.
     */
    fun startJob(jobId: Long, lat: Double? = null, lng: Double? = null) {
        transitionJob(jobId, DispatchJobStatus.ON_SITE, lat = lat, lng = lng)
    }

    /**
     * Tech marks job as complete — transitions on_site → completed.
     */
    fun completeJob(jobId: Long, techNotes: String? = null) {
        transitionJob(jobId, DispatchJobStatus.COMPLETED, notes = techNotes)
    }

    // -----------------------------------------------------------------------
    // Cancel flow: two-step (show dialog → confirm)
    // -----------------------------------------------------------------------

    /** Shows the cancel confirmation dialog for [jobId]. */
    fun requestCancelJob(jobId: Long) {
        _state.update { it.copy(pendingCancelJobId = jobId) }
    }

    /** Dismissed without confirming. */
    fun dismissCancelDialog() {
        _state.update { it.copy(pendingCancelJobId = null) }
    }

    /** User confirmed cancel in the dialog. */
    fun confirmCancelJob() {
        val jobId = _state.value.pendingCancelJobId ?: return
        _state.update { it.copy(pendingCancelJobId = null) }
        transitionJob(jobId, DispatchJobStatus.CANCELED)
    }

    // -----------------------------------------------------------------------
    // Internal transition helper
    // -----------------------------------------------------------------------

    private fun transitionJob(
        jobId: Long,
        newStatus: String,
        notes: String? = null,
        lat: Double? = null,
        lng: Double? = null,
    ) {
        if (_state.value.transitioningJobId != null) return
        viewModelScope.launch {
            _state.update { it.copy(transitioningJobId = jobId, error = null) }
            runCatching {
                repository.updateJobStatus(
                    id = jobId,
                    newStatus = newStatus,
                    notes = notes,
                    locationLat = lat,
                    locationLng = lng,
                )
            }
                .onSuccess { updated ->
                    _state.update { s ->
                        s.copy(
                            transitioningJobId = null,
                            jobs = s.jobs.map { if (it.id == updated.id) updated else it },
                            toastMessage = statusToastMessage(newStatus),
                        )
                    }
                }
                .onFailure { e ->
                    Log.w(TAG, "transitionJob($jobId → $newStatus) failed: ${e.message}")
                    _state.update {
                        it.copy(
                            transitioningJobId = null,
                            error = e.message ?: "Status update failed",
                        )
                    }
                }
        }
    }

    private fun statusToastMessage(status: String): String = when (status) {
        DispatchJobStatus.EN_ROUTE   -> "Job accepted — on my way!"
        DispatchJobStatus.ON_SITE    -> "Arrived — job started"
        DispatchJobStatus.COMPLETED  -> "Job completed"
        DispatchJobStatus.CANCELED   -> "Job canceled"
        else                          -> "Job updated"
    }

    // -----------------------------------------------------------------------
    // Misc
    // -----------------------------------------------------------------------

    fun clearToast() {
        _state.update { it.copy(toastMessage = null) }
    }

    fun clearError() {
        _state.update { it.copy(error = null) }
    }

    companion object {
        private const val TAG = "DispatchViewModel"
    }
}
