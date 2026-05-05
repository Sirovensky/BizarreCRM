package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST

/**
 * §50 — Data Import API
 *
 * Wires to the real server endpoints under `/api/v1/import/`:
 *
 *   POST /import/repairdesk/start      – start RepairDesk import (api_key + entities)
 *   GET  /import/repairdesk/status     – poll RepairDesk progress
 *   POST /import/repairshopr/start     – start RepairShopr import (api_key + subdomain + entities)
 *   GET  /import/repairshopr/status    – poll RepairShopr progress
 *   POST /import/myrepairapp/start     – start MyRepairApp import (api_key + entities)
 *   GET  /import/myrepairapp/status    – poll MyRepairApp progress
 *   POST /customers/import-csv         – bulk-insert customer rows (pre-parsed JSON)
 *   POST /inventory/import-csv         – bulk-insert inventory rows (pre-parsed JSON)
 *
 * NOTE — unified /imports/start + /imports/:id/status endpoints DO NOT EXIST on the
 * server. The server uses per-source endpoints; CSV imports require client-side parsing
 * and JSON body submission (see DataImportViewModel).
 *
 * All endpoints are 404-tolerant: callers guard with HttpException.code() == 404
 * and set serverUnsupported = true in the VM.
 *
 * Role gate: admin only (server enforces; VM also hides for non-admin).
 */
interface ImportApi {

    // ── RepairDesk ────────────────────────────────────────────────────────────

    /**
     * Start a RepairDesk import job.
     *
     * Body: { api_key: String, entities: [String] }
     * Returns { message, runs: [{ id, source, entity_type, status }] }
     */
    @POST("import/repairdesk/start")
    suspend fun startRepairDeskImport(
        @Body body: RepairDeskStartRequest,
    ): ApiResponse<@JvmSuppressWildcards Any>

    /**
     * Poll RepairDesk import status.
     * Returns { is_active, overall: { imported, skipped, errors, total_records }, runs[], checkpoints{} }
     */
    @GET("import/repairdesk/status")
    suspend fun getRepairDeskStatus(): ApiResponse<@JvmSuppressWildcards Any>

    // ── RepairShopr ───────────────────────────────────────────────────────────

    /**
     * Start a RepairShopr import job.
     *
     * Body: { api_key: String, subdomain: String, entities: [String] }
     * Returns { message, runs: [{ id, source, entity_type, status }] }
     */
    @POST("import/repairshopr/start")
    suspend fun startRepairShoprImport(
        @Body body: RepairShoprStartRequest,
    ): ApiResponse<@JvmSuppressWildcards Any>

    /**
     * Poll RepairShopr import status.
     * Returns { is_active, overall: { imported, skipped, errors, total_records }, runs[], checkpoints{} }
     */
    @GET("import/repairshopr/status")
    suspend fun getRepairShoprStatus(): ApiResponse<@JvmSuppressWildcards Any>

    // ── MyRepairApp ───────────────────────────────────────────────────────────

    /**
     * Start a MyRepairApp import job.
     *
     * Body: { api_key: String, entities: [String] }
     * Returns { message, runs: [{ id, source, entity_type, status }] }
     */
    @POST("import/myrepairapp/start")
    suspend fun startMraImport(
        @Body body: MraStartRequest,
    ): ApiResponse<@JvmSuppressWildcards Any>

    /**
     * Poll MyRepairApp import status.
     * Returns { is_active, overall: { imported, skipped, errors, total_records }, runs[], checkpoints{} }
     */
    @GET("import/myrepairapp/status")
    suspend fun getMraStatus(): ApiResponse<@JvmSuppressWildcards Any>

    // ── Generic CSV (customer rows) ───────────────────────────────────────────

    /**
     * Bulk-insert customer rows from a client-parsed CSV.
     * The client parses the CSV with [com.bizarreelectronics.crm.util.CsvParser],
     * maps columns, then posts the JSON array here.
     *
     * Body: { items: [{ first_name, last_name, email, phone, ... }], skip_duplicates: Boolean }
     * Returns { created, skipped, errors: [{ row, error }] }
     * Max 500 rows per request.
     */
    @POST("customers/import-csv")
    suspend fun importCustomerCsv(
        @Body body: CustomerCsvImportRequest,
    ): ApiResponse<@JvmSuppressWildcards Any>

    /**
     * Bulk-insert inventory rows from a client-parsed CSV.
     *
     * Body: { items: [{ name, sku, cost_price, retail_price, in_stock, ... }] }
     * Returns { created, errors: [{ row, error }] }
     * Max 500 rows per request.
     */
    @POST("inventory/import-csv")
    suspend fun importInventoryCsv(
        @Body body: InventoryCsvImportRequest,
    ): ApiResponse<@JvmSuppressWildcards Any>
}

// ── Request DTOs ──────────────────────────────────────────────────────────────

data class RepairDeskStartRequest(
    val api_key: String,
    val entities: List<String>,
)

data class RepairShoprStartRequest(
    val api_key: String,
    val subdomain: String,
    val entities: List<String>,
)

data class MraStartRequest(
    val api_key: String,
    val entities: List<String>,
)

data class CustomerCsvImportRequest(
    val items: List<Map<String, Any?>>,
    val skip_duplicates: Boolean = true,
)

data class InventoryCsvImportRequest(
    val items: List<Map<String, Any?>>,
)
