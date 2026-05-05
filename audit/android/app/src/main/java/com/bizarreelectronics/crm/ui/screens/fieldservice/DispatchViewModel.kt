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
import java.time.LocalDate
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
    // ── §59.2 Route optimisation ──────────────────────────────────────────────
    /** True while waiting for POST /routes/optimize to return. */
    val isOptimizing: Boolean = false,
    /**
     * Non-null after a successful optimisation run.
     * Contains the server note (algorithm caveat) + estimated distance.
     * Dismissed by [clearOptimizationBanner].
     */
    val optimizationBanner: OptimizationBanner? = null,
)

/**
 * §59.2 — Shown after a successful route-optimisation call.
 *
 * [distanceKm]    total estimated driving distance returned by the server.
 * [startFromHome] true when the server seeded the route from the tech's home coords.
 * [note]          server-provided algorithm caveat (e.g. "greedy heuristic, not TSP-optimal").
 */
data class OptimizationBanner(
    val distanceKm: Double,
    val startFromHome: Boolean,
    val note: String,
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
    // §59.2 Route optimisation
    // -----------------------------------------------------------------------

    /**
     * Calls POST /api/v1/field-service/routes/optimize with the current job list
     * and reorders [DispatchUiState.jobs] to match the server's proposed sequence.
     *
     * Manager / admin only — server returns 403 for technician-role users;
     * that error surfaces as a snackbar (toastMessage) so the screen stays intact.
     *
     * The call is no-op when:
     *   - optimisation is already in flight ([isOptimizing] == true)
     *   - fewer than 2 open jobs with coordinates in the current list (nothing to sort)
     *
     * On success the job list is reordered in place and [OptimizationBanner] is set
     * with the distance + algorithm note. Non-optimisable jobs (terminal / no-coords)
     * are appended at the end in their original relative order.
     *
     * [technicianId] should be the logged-in user's ID when acting on their own route,
     * or the selected tech's ID when a manager is optimising for someone else.
     * Defaults to -1 which the server will reject with 400; callers should pass the
     * real ID from AuthPreferences.userId.
     */
    fun optimizeRoute(technicianId: Long = -1L) {
        val current = _state.value
        if (current.isOptimizing) return

        viewModelScope.launch {
            _state.update { it.copy(isOptimizing = true, error = null) }
            val today = LocalDate.now().toString()
            runCatching {
                repository.optimizeRoute(
                    technicianId = technicianId,
                    routeDate    = today,
                    jobs         = current.jobs,
                )
            }
                .onSuccess { result ->
                    // Reorder: build a map of id → job for fast lookup, then
                    // emit the proposed_order first, then any remainders.
                    val jobMap = current.jobs.associateBy { it.id }
                    val ordered = result.proposedOrder.mapNotNull { jobMap[it] }
                    val inOrder = ordered.map { it.id }.toSet()
                    val remainder = current.jobs.filter { it.id !in inOrder }
                    val reordered = ordered + remainder
                    _state.update { s ->
                        s.copy(
                            isOptimizing = false,
                            jobs         = reordered,
                            optimizationBanner = OptimizationBanner(
                                distanceKm    = result.totalDistanceKm,
                                startFromHome = result.startFromHome,
                                note          = result.note,
                            ),
                        )
                    }
                    Log.i(TAG, "optimizeRoute: reordered ${ordered.size} jobs, " +
                        "~${result.totalDistanceKm} km (${result.algorithm})")
                }
                .onFailure { e ->
                    Log.w(TAG, "optimizeRoute failed: ${e.message}")
                    _state.update {
                        it.copy(
                            isOptimizing = false,
                            toastMessage  = e.message ?: "Route optimisation failed",
                        )
                    }
                }
        }
    }

    /** Dismisses the post-optimisation info banner. */
    fun clearOptimizationBanner() {
        _state.update { it.copy(optimizationBanner = null) }
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
