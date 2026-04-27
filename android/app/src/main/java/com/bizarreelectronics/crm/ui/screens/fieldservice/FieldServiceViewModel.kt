package com.bizarreelectronics.crm.ui.screens.fieldservice

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.FieldServiceApi
import com.bizarreelectronics.crm.data.remote.dto.DispatchJobListData
import com.bizarreelectronics.crm.data.remote.dto.UpdateDispatchJobRequest
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import retrofit2.HttpException
import javax.inject.Inject

/**
 * FieldServiceViewModel — §59 Field-Service / Dispatch
 *
 * Loads the technician's dispatch job list and orchestrates:
 * - §59.1 List view: jobs loaded from [FieldServiceApi.getJobs], sorted by
 *   ETA + priority for list display. Map-view data (lat/lon) is in the same
 *   job objects but rendered by [FieldServiceScreen] as a NOTE-defer map stub.
 * - §59.2 Route optimization: calls [FieldServiceApi.optimizeRoute] and
 *   reorders [FieldServiceUiState.jobs] by the returned job ID sequence.
 * - §59.4 Job status transitions: "On my way" → `en_route`, "Mark on-site" →
 *   `on_site`, "Mark complete" → `completed`, "Cancel job" → `cancelled`.
 *
 * All server endpoints are 404-tolerant (server routes not yet deployed).
 * Offline support: shows [FieldServiceUiState.offline] banner; list is empty
 * until connectivity is restored (Room cache for dispatch jobs is Phase-7 work).
 */
@HiltViewModel
class FieldServiceViewModel @Inject constructor(
    private val fieldServiceApi: FieldServiceApi,
    private val serverMonitor: ServerReachabilityMonitor,
) : ViewModel() {

    private val _state = MutableStateFlow(FieldServiceUiState())
    val state = _state.asStateFlow()

    init {
        loadJobs()
    }

    // ─── §59.1 Load job list ──────────────────────────────────────────────────

    /** Load (or refresh) the dispatch job list from the server. */
    fun loadJobs() {
        if (!serverMonitor.isEffectivelyOnline.value) {
            _state.update { it.copy(isLoading = false, offline = true) }
            return
        }
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, error = null, offline = false) }
            try {
                val response = fieldServiceApi.getJobs()
                val jobs = (response.data?.jobs ?: emptyList())
                    .sortedWith(compareBy(
                        { it.etaMinutes ?: Int.MAX_VALUE },
                        { it.priority ?: Int.MAX_VALUE },
                    ))
                _state.update { it.copy(isLoading = false, jobs = jobs) }
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    // Server endpoint not yet deployed — degrade gracefully.
                    _state.update { it.copy(isLoading = false, jobs = emptyList()) }
                } else {
                    _state.update {
                        it.copy(isLoading = false, error = "Failed to load jobs (${e.code()})")
                    }
                }
            } catch (e: Exception) {
                _state.update {
                    it.copy(isLoading = false, error = e.message ?: "Failed to load jobs")
                }
            }
        }
    }

    // ─── §59.2 Route optimization ─────────────────────────────────────────────

    /**
     * Request an optimized route ordering from the server.
     *
     * On success, reorders the current job list to match the server's suggested
     * sequence. 404-tolerant: if the endpoint isn't deployed, list order is
     * unchanged and a toast informs the technician.
     */
    fun optimizeRoute() {
        if (!serverMonitor.isEffectivelyOnline.value) {
            _state.update { it.copy(snackMessage = "Route optimization requires a connection") }
            return
        }
        viewModelScope.launch {
            _state.update { it.copy(isOptimizing = true) }
            try {
                val response = fieldServiceApi.optimizeRoute()
                val orderedIds = response.data?.jobIds ?: emptyList()
                if (orderedIds.isNotEmpty()) {
                    val currentJobs = _state.value.jobs
                    val idToJob = currentJobs.associateBy { it.id }
                    val reordered = orderedIds.mapNotNull { idToJob[it] } +
                        currentJobs.filter { it.id !in orderedIds }
                    _state.update {
                        it.copy(
                            isOptimizing = false,
                            jobs = reordered,
                            snackMessage = "Route optimized",
                        )
                    }
                } else {
                    _state.update {
                        it.copy(isOptimizing = false, snackMessage = "No route changes needed")
                    }
                }
            } catch (e: HttpException) {
                val msg = if (e.code() == 404) {
                    "Route optimization not available on this server"
                } else {
                    "Optimization failed (${e.code()})"
                }
                _state.update { it.copy(isOptimizing = false, snackMessage = msg) }
            } catch (e: Exception) {
                _state.update {
                    it.copy(
                        isOptimizing = false,
                        snackMessage = e.message ?: "Optimization failed",
                    )
                }
            }
        }
    }

    // ─── §59.4 Status transitions ─────────────────────────────────────────────

    /**
     * Mark job as "On my way" → status `en_route`.
     *
     * Called when tech taps "On my way" on a job card (§59.3).
     * Optimistic update applied immediately; server call fires in the background.
     */
    fun markEnRoute(jobId: Long) = updateJobStatus(jobId, "en_route", "On my way!")

    /**
     * Mark job as on-site → status `on_site`.
     *
     * Called after ConfirmDialog "Mark on-site" confirmation.
     */
    fun markOnSite(jobId: Long) = updateJobStatus(jobId, "on_site", "Marked on-site")

    /**
     * Mark job as complete → status `completed`.
     *
     * Called after ConfirmDialog "Mark complete" confirmation.
     */
    fun markComplete(jobId: Long) = updateJobStatus(jobId, "completed", "Job marked complete")

    /**
     * Cancel job → status `cancelled`.
     *
     * Called after ConfirmDialog "Cancel job" confirmation (destructive).
     */
    fun cancelJob(jobId: Long) = updateJobStatus(jobId, "cancelled", "Job cancelled")

    private fun updateJobStatus(jobId: Long, newStatus: String, successMessage: String) {
        // Optimistic update: change status locally first for instant feedback.
        _state.update { s ->
            s.copy(jobs = s.jobs.map { j ->
                if (j.id == jobId) j.copy(status = newStatus) else j
            })
        }
        viewModelScope.launch {
            try {
                fieldServiceApi.updateJob(
                    jobId = jobId,
                    body = UpdateDispatchJobRequest(status = newStatus),
                )
                _state.update { it.copy(snackMessage = successMessage) }
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    // Server endpoint not deployed — local optimistic update stands.
                    _state.update { it.copy(snackMessage = successMessage) }
                } else {
                    // Revert optimistic change on server error.
                    loadJobs()
                    _state.update {
                        it.copy(snackMessage = "Status update failed (${e.code()})")
                    }
                }
            } catch (e: Exception) {
                loadJobs()
                _state.update {
                    it.copy(snackMessage = e.message ?: "Status update failed")
                }
            }
        }
    }

    fun clearSnackMessage() = _state.update { it.copy(snackMessage = null) }
}

/**
 * UI state for [FieldServiceScreen].
 *
 * @param jobs          Ordered list of today's dispatch jobs (ETA + priority sorted).
 * @param isLoading     True while the initial or refresh fetch is in flight.
 * @param error         Non-null when a recoverable fetch error occurred.
 * @param offline       True when the server is unreachable.
 * @param isOptimizing  True while route optimization is in progress.
 * @param snackMessage  Transient snackbar message (status updates, optimization).
 */
data class FieldServiceUiState(
    val jobs: List<DispatchJobListData.DispatchJob> = emptyList(),
    val isLoading: Boolean = true,
    val error: String? = null,
    val offline: Boolean = false,
    val isOptimizing: Boolean = false,
    val snackMessage: String? = null,
)
