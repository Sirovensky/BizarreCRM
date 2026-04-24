package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import okhttp3.MultipartBody
import okhttp3.RequestBody
import retrofit2.http.GET
import retrofit2.http.Multipart
import retrofit2.http.POST
import retrofit2.http.Part
import retrofit2.http.Path

/**
 * §50 — Data Import API
 *
 * Server endpoints:
 *   POST /imports/start          — start an import job (multipart: type, file, mapping)
 *   GET  /imports/:id/status     — poll job progress
 *   GET  /imports/:id/errors     — download error-row CSV URL
 *
 * All endpoints are 404-tolerant: callers guard with HttpException.code() == 404
 * and show an "import not configured on this server" empty state.
 *
 * Role gate: admin only. The server enforces this; the client also hides the
 * screen for non-admin users (see DataImportViewModel.isAdmin).
 */
interface ImportApi {

    /**
     * Start an import job.
     *
     * @param type       One of: repairdesk_csv | shopr_csv | mra | generic_csv
     * @param file       The CSV file uploaded via SAF.
     * @param mapping    JSON string: { "source_col": "crm_field", ... }
     * @param dryRun     "true" to validate only (no DB writes); "false" to commit.
     * @param scope      Comma-separated entity types: customers,tickets,invoices,inventory
     *
     * Returns { job_id: String }
     */
    @Multipart
    @POST("imports/start")
    suspend fun startImport(
        @Part("type") type: RequestBody,
        @Part file: MultipartBody.Part,
        @Part("mapping") mapping: RequestBody,
        @Part("dry_run") dryRun: RequestBody,
        @Part("scope") scope: RequestBody,
    ): ApiResponse<@JvmSuppressWildcards Any>

    /**
     * Poll the status of a running import job.
     * Returns { status: queued|running|done|error, imported: Int, skipped: Int, errors: Int,
     *           total: Int, current_step: String, error_csv_url: String? }
     */
    @GET("imports/{id}/status")
    suspend fun getImportStatus(
        @Path("id") jobId: String,
    ): ApiResponse<@JvmSuppressWildcards Any>

    /**
     * Preview the first N rows parsed from the uploaded file (dry-run helper).
     * Returns { columns: [String], rows: [[String]] }
     */
    @Multipart
    @POST("imports/preview")
    suspend fun previewImport(
        @Part("type") type: RequestBody,
        @Part file: MultipartBody.Part,
        @Part("limit") limit: RequestBody,
    ): ApiResponse<@JvmSuppressWildcards Any>
}
