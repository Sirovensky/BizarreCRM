package com.bizarreelectronics.crm.data.repository

import android.util.Log
import com.bizarreelectronics.crm.data.remote.api.DispatchApi
import com.bizarreelectronics.crm.data.remote.dto.DispatchJobDetail
import com.bizarreelectronics.crm.data.remote.dto.RouteOptimizeRequest
import com.bizarreelectronics.crm.data.remote.dto.RouteOptimizeResult
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Repository for Field Service / Dispatch.
 *
 * Scope: Android technician-facing job list, accept/start/complete lifecycle,
 * and location ping forwarding. The ping path is best-effort — failures are
 * logged and swallowed so the foreground service does not crash.
 *
 * NOTE: No offline queue here. Job status transitions require server
 * confirmation so they fail fast when the server is unreachable; the caller
 * should show an error message and let the tech retry manually.
 */
@Singleton
class DispatchRepository @Inject constructor(
    private val api: DispatchApi,
    private val serverMonitor: ServerReachabilityMonitor,
) {

    /** Returns today's job list for the logged-in technician (role-scoped on server). */
    suspend fun getTodayJobs(): List<DispatchJobDetail> {
        val today = java.time.LocalDate.now().toString()       // YYYY-MM-DD
        val response = api.getJobs(
            mapOf("from_date" to today, "to_date" to today, "pagesize" to "100"),
        )
        return response.data?.jobs ?: emptyList()
    }

    /** Returns the full job list without date filter (e.g. for "upcoming" view). */
    suspend fun getAllMyJobs(): List<DispatchJobDetail> {
        val response = api.getJobs(mapOf("pagesize" to "100"))
        return response.data?.jobs ?: emptyList()
    }

    /** Returns a single job by ID. */
    suspend fun getJob(id: Long): DispatchJobDetail {
        val response = api.getJob(id)
        return response.data ?: error("Job $id not found")
    }

    /**
     * Transitions a job to [newStatus].
     *
     * Valid transitions driven by the server state machine:
     *   assigned  → en_route  (tech accepts / "On my way")
     *   en_route  → on_site   (tech starts work / "I've arrived")
     *   on_site   → completed (tech completes job)
     *   any open  → canceled  (tech cancels — server allows this)
     *
     * [locationLat] / [locationLng] are optional and recorded in dispatch_status_history
     * when provided. The server validates ranges.
     *
     * Returns the updated job detail fetched after the transition.
     */
    suspend fun updateJobStatus(
        id: Long,
        newStatus: String,
        notes: String? = null,
        locationLat: Double? = null,
        locationLng: Double? = null,
    ): DispatchJobDetail {
        val body = buildMap<String, Any?> {
            put("status", newStatus)
            if (!notes.isNullOrBlank()) put("notes", notes)
            if (locationLat != null && locationLng != null) {
                put("location_lat", locationLat)
                put("location_lng", locationLng)
            }
        }
        val response = api.updateJobStatus(id, body)
        if (!response.success) {
            throw Exception(response.message ?: "Status update failed")
        }
        // Re-fetch the job so the caller gets a fresh DispatchJobDetail.
        return getJob(id)
    }

    /**
     * §59.2 Route Optimization.
     *
     * Calls POST /api/v1/field-service/routes/optimize with the supplied job list
     * and returns the server's greedy nearest-neighbor reordering.
     *
     * Manager / admin only — server returns 403 for other roles; the caller
     * should surface a permission-denied message.
     *
     * Does NOT persist the new order — caller must reorder the local list and
     * optionally POST /routes to save it.
     *
     * @param technicianId  user ID of the technician whose route to optimise.
     * @param routeDate     date in YYYY-MM-DD format.
     * @param jobs          current job list; only non-terminal jobs with valid
     *                      (lat, lng) are included (others are appended at end).
     * @return              [RouteOptimizeResult] with proposed_order + distance.
     * @throws Exception    on network error, 403 (not manager), 429 (rate limit),
     *                      or if no eligible jobs remain after filtering.
     */
    suspend fun optimizeRoute(
        technicianId: Long,
        routeDate: String,
        jobs: List<DispatchJobDetail>,
    ): RouteOptimizeResult {
        // Only include open jobs that have coordinates — server rejects jobs with
        // null lat/lng and we want the call to succeed even in mixed lists.
        val terminalStatuses = setOf("completed", "canceled", "deferred")
        val eligible = jobs.filter { it.status !in terminalStatuses && it.lat != null && it.lng != null }
        if (eligible.isEmpty()) {
            throw IllegalStateException("No open jobs with coordinates to optimise")
        }
        val request = RouteOptimizeRequest(
            technicianId = technicianId,
            routeDate    = routeDate,
            jobIds       = eligible.map { it.id },
        )
        val response = api.optimizeRoute(request)
        if (!response.success || response.data == null) {
            throw Exception(response.message ?: "Route optimisation failed")
        }
        return response.data
    }

    /**
     * Sends a GPS ping for the current tech's position.
     *
     * This is a status update on the most recent non-completed, non-canceled job
     * assigned to the tech, re-using the existing POST /jobs/:id/status endpoint.
     * Failures are swallowed — GPS pings are best-effort and should never block UI.
     *
     * NOTE: If the server later adds a dedicated /location-ping endpoint this
     * method should be updated to use it instead.
     *
     * NOTE: GPS pings only work when there is a current open job. If no job is
     * active (jobId == null) the ping is silently dropped.
     */
    suspend fun pingLocation(jobId: Long, lat: Double, lng: Double) {
        if (!serverMonitor.isEffectivelyOnline.value) {
            Log.d(TAG, "pingLocation: server offline — skipping ping for job $jobId")
            return
        }
        try {
            val body = mapOf<String, Any?>(
                "status" to "en_route",      // Keep same status; server records location in history
                "location_lat" to lat,
                "location_lng" to lng,
            )
            // NOTE: This will 400 if the job is not in en_route status. That is acceptable —
            // the ping carries location data that gets logged even on a same-status transition,
            // and if the status changed the tech should not be pinging anyway. The caller catches.
            api.updateJobStatus(jobId, body)
        } catch (e: Exception) {
            Log.w(TAG, "pingLocation: failed for job $jobId — ${e.message}")
        }
    }

    companion object {
        private const val TAG = "DispatchRepository"
    }
}
