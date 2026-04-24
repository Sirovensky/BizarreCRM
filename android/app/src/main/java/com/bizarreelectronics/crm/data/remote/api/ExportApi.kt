package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path

/**
 * §51 — Data Export API
 *
 * Server endpoints:
 *   POST /exports/start          — enqueue an export job; returns { job_id }
 *   GET  /exports/:id/status     — poll until { status: "ready", download_url }
 *   GET  /exports/:id/download   — (direct download, handled via browser/DownloadManager)
 *
 * All endpoints are 404-tolerant: callers guard with HttpException.code() == 404
 * and show an "export not configured" empty state.
 *
 * Role gate: manager+ for exports. The server enforces this; the client also
 * hides the screen for staff users (see DataExportViewModel.canExport).
 */
interface ExportApi {

    /**
     * Request an export job.
     *
     * Body fields:
     *   entity_types   — list of: customers | tickets | invoices | inventory | expenses
     *   format         — csv | json | xlsx
     *   date_from      — ISO-8601 date or null
     *   date_to        — ISO-8601 date or null
     *   active_only    — boolean
     *   email          — boolean (also email the archive to admin)
     *
     * Returns { job_id: String }
     */
    @POST("exports/start")
    suspend fun startExport(
        @Body body: Map<String, @JvmSuppressWildcards Any>,
    ): ApiResponse<@JvmSuppressWildcards Any>

    /**
     * Poll the status of a running export job.
     * Returns { status: queued|running|ready|error, progress: Int,
     *           download_url: String?, error_message: String? }
     */
    @GET("exports/{id}/status")
    suspend fun getExportStatus(
        @Path("id") jobId: String,
    ): ApiResponse<@JvmSuppressWildcards Any>
}
