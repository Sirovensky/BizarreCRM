package com.bizarreelectronics.crm.ui.screens.importdata

import android.content.Context
import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.CustomerCsvImportRequest
import com.bizarreelectronics.crm.data.remote.api.ImportApi
import com.bizarreelectronics.crm.data.remote.api.InventoryCsvImportRequest
import com.bizarreelectronics.crm.data.remote.api.MraStartRequest
import com.bizarreelectronics.crm.data.remote.api.RepairDeskStartRequest
import com.bizarreelectronics.crm.data.remote.api.RepairShoprStartRequest
import com.bizarreelectronics.crm.data.sync.ImportPollingWorker
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import javax.inject.Inject

// ── Domain types ──────────────────────────────────────────────────────────────

enum class ImportSource(val label: String, val needsCredentials: Boolean) {
    REPAIR_DESK("RepairDesk", needsCredentials = true),
    SHOPR("RepairShopr", needsCredentials = true),
    MRA("MyRepairApp", needsCredentials = true),
    GENERIC_CSV("Generic CSV", needsCredentials = false),
}

enum class ImportScope(val label: String, val apiValue: String) {
    CUSTOMERS("Customers", "customers"),
    TICKETS("Tickets", "tickets"),
    INVOICES("Invoices", "invoices"),
    INVENTORY("Inventory", "inventory"),
    EMPLOYEES("Employees", "employees"),
}

enum class ImportStep { SOURCE, CREDENTIALS, FILE, SCOPE, COLUMN_MAP, PREVIEW, PROGRESS, DONE, ERROR }

enum class ImportJobStatus { QUEUED, RUNNING, DONE, ERROR }

/** One row parsed from a CSV file on-device. */
data class PreviewData(
    val columns: List<String> = emptyList(),
    val rows: List<List<String>> = emptyList(),
)

/** A source→CRM field mapping entry. */
data class ColumnMapping(
    val sourceColumn: String,
    val crmField: String,   // empty string = skip column
)

data class ImportProgress(
    val status: ImportJobStatus = ImportJobStatus.QUEUED,
    val imported: Int = 0,
    val skipped: Int = 0,
    val errors: Int = 0,
    val total: Int = 0,
    val currentStep: String = "",
    val errorCsvUrl: String? = null,
)

data class DataImportUiState(
    val step: ImportStep = ImportStep.SOURCE,
    val selectedSource: ImportSource = ImportSource.GENERIC_CSV,
    val selectedScopes: Set<ImportScope> = setOf(ImportScope.CUSTOMERS),
    // Credentials (API-key sources only)
    val apiKey: String = "",
    val subdomain: String = "",   // RepairShopr only
    // CSV file (GENERIC_CSV only)
    val fileUri: Uri? = null,
    val fileName: String = "",
    // Column mapping / preview
    val columnMappings: List<ColumnMapping> = emptyList(),
    val preview: PreviewData = PreviewData(),
    // Progress
    val isDryRun: Boolean = false,
    val progress: ImportProgress = ImportProgress(),
    // Misc
    val isLoading: Boolean = false,
    val error: String? = null,
    val serverUnsupported: Boolean = false,
    /** True only when the signed-in user is an admin. */
    val isAdmin: Boolean = false,
    val toastMessage: String? = null,
)

/**
 * §50 — Data Import ViewModel
 *
 * Wizard steps:
 *   SOURCE → CREDENTIALS (API-key sources) or FILE (CSV) → SCOPE → COLUMN_MAP (CSV only)
 *   → PREVIEW (CSV only) → PROGRESS → DONE/ERROR
 *
 * For API-key sources (RepairDesk / RepairShopr / MRA):
 *   - User enters credentials in the CREDENTIALS step.
 *   - The server starts a background import job; we poll /status every 3 s.
 *   - ImportPollingWorker is also enqueued so the progress notification survives
 *     the user leaving the screen.
 *
 * For GENERIC_CSV:
 *   - User picks a file via SAF (ACTION_OPEN_DOCUMENT).
 *   - We parse it client-side with CsvParser (up to 500 rows).
 *   - User maps columns in COLUMN_MAP step.
 *   - Preview first 20 rows in PREVIEW step.
 *   - On commit: send parsed JSON to POST /customers/import-csv or /inventory/import-csv.
 *
 * 404-tolerant: any 404 from the server sets serverUnsupported = true.
 * Role gate: admin only. Non-admin users see "Access denied" empty state.
 */
@HiltViewModel
class DataImportViewModel @Inject constructor(
    private val importApi: ImportApi,
    private val authPreferences: AuthPreferences,
    private val serverMonitor: ServerReachabilityMonitor,
    @ApplicationContext private val context: Context,
) : ViewModel() {

    private val _state = MutableStateFlow(DataImportUiState())
    val state = _state.asStateFlow()

    private var pollJob: Job? = null

    private val isAdmin: Boolean
        get() = authPreferences.userRole?.lowercase() in setOf("admin", "owner")

    init {
        _state.value = _state.value.copy(isAdmin = isAdmin)
    }

    // ── Step navigation ───────────────────────────────────────────────────────

    fun selectSource(source: ImportSource) {
        _state.value = _state.value.copy(selectedSource = source)
    }

    fun onApiKeyChanged(value: String) {
        _state.value = _state.value.copy(apiKey = value, error = null)
    }

    fun onSubdomainChanged(value: String) {
        _state.value = _state.value.copy(subdomain = value, error = null)
    }

    fun onFileSelected(uri: Uri, displayName: String) {
        _state.value = _state.value.copy(fileUri = uri, fileName = displayName, error = null)
    }

    fun toggleScope(scope: ImportScope) {
        val current = _state.value.selectedScopes
        val updated = if (scope in current) current - scope else current + scope
        _state.value = _state.value.copy(selectedScopes = updated.ifEmpty { setOf(scope) })
    }

    fun updateMapping(index: Int, crmField: String) {
        val updated = _state.value.columnMappings.mapIndexed { i, m ->
            if (i == index) m.copy(crmField = crmField) else m
        }
        _state.value = _state.value.copy(columnMappings = updated)
    }

    fun goToStep(step: ImportStep) {
        _state.value = _state.value.copy(step = step, error = null)
    }

    /** Called when the user presses "Continue" on the SOURCE step. */
    fun continueFromSource() {
        val src = _state.value.selectedSource
        val next = if (src.needsCredentials) ImportStep.CREDENTIALS else ImportStep.FILE
        _state.value = _state.value.copy(step = next, error = null)
    }

    /** Called when the user presses "Continue" on the CREDENTIALS step. */
    fun continueFromCredentials() {
        val s = _state.value
        if (s.apiKey.isBlank()) {
            _state.value = s.copy(error = "API key is required")
            return
        }
        if (s.selectedSource == ImportSource.SHOPR && s.subdomain.isBlank()) {
            _state.value = s.copy(error = "Subdomain is required for RepairShopr")
            return
        }
        // For API-key sources there is no file to pick — go straight to SCOPE
        _state.value = _state.value.copy(step = ImportStep.SCOPE, error = null)
    }

    /** Called when the user presses "Detect Columns" after picking a CSV file. */
    fun loadCsvPreview() {
        val uri = _state.value.fileUri ?: return
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                val bytes = context.contentResolver.openInputStream(uri)?.readBytes()
                    ?: throw IllegalStateException("Cannot read file")
                val text = bytes.toString(Charsets.UTF_8)
                val lines = text.lines().filter { it.isNotBlank() }
                if (lines.size < 2) throw IllegalStateException("CSV must have a header row and at least one data row")
                val columns = parseCsvLine(lines[0])
                val previewRows = lines.drop(1).take(PREVIEW_LIMIT).map { parseCsvLine(it) }
                val preview = PreviewData(columns = columns, rows = previewRows)
                val mappings = columns.map { col -> ColumnMapping(sourceColumn = col, crmField = "") }
                _state.value = _state.value.copy(
                    isLoading = false,
                    preview = preview,
                    columnMappings = mappings,
                    step = ImportStep.COLUMN_MAP,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(isLoading = false, error = e.message ?: "Failed to parse CSV")
            }
        }
    }

    fun goBack() {
        val prev = when (_state.value.step) {
            ImportStep.CREDENTIALS -> ImportStep.SOURCE
            ImportStep.FILE        -> ImportStep.SOURCE
            ImportStep.SCOPE       -> if (_state.value.selectedSource.needsCredentials) ImportStep.CREDENTIALS else ImportStep.FILE
            ImportStep.COLUMN_MAP  -> ImportStep.SCOPE
            ImportStep.PREVIEW     -> ImportStep.COLUMN_MAP
            else                   -> ImportStep.SOURCE
        }
        _state.value = _state.value.copy(step = prev, error = null)
    }

    fun clearToast() {
        _state.value = _state.value.copy(toastMessage = null)
    }

    // ── Import execution ──────────────────────────────────────────────────────

    /**
     * Start the import job on the server (API-key sources) or submit CSV rows (GENERIC_CSV).
     */
    fun commitImport() {
        if (!serverMonitor.isEffectivelyOnline.value) {
            _state.value = _state.value.copy(error = "Device is offline")
            return
        }
        when (_state.value.selectedSource) {
            ImportSource.REPAIR_DESK -> startApiImport(ImportSource.REPAIR_DESK)
            ImportSource.SHOPR       -> startApiImport(ImportSource.SHOPR)
            ImportSource.MRA         -> startApiImport(ImportSource.MRA)
            ImportSource.GENERIC_CSV -> submitCsvImport()
        }
    }

    /** Alias kept for PREVIEW step "Import Now" button. */
    fun startDryRun() {
        // CSV sources: dry-run is just the PREVIEW already shown.
        // API sources: there is no dry-run — commit directly.
        commitImport()
    }

    // ── API-key import (RepairDesk / RepairShopr / MRA) ───────────────────────

    private fun startApiImport(source: ImportSource) {
        val s = _state.value
        val entities = s.selectedScopes.map { it.apiValue }
        viewModelScope.launch {
            _state.value = _state.value.copy(
                isLoading = true,
                error = null,
                isDryRun = false,
                step = ImportStep.PROGRESS,
                progress = ImportProgress(status = ImportJobStatus.QUEUED),
            )
            try {
                when (source) {
                    ImportSource.REPAIR_DESK ->
                        importApi.startRepairDeskImport(RepairDeskStartRequest(s.apiKey.trim(), entities))
                    ImportSource.SHOPR ->
                        importApi.startRepairShoprImport(RepairShoprStartRequest(s.apiKey.trim(), s.subdomain.trim(), entities))
                    ImportSource.MRA ->
                        importApi.startMraImport(MraStartRequest(s.apiKey.trim(), entities))
                    ImportSource.GENERIC_CSV -> throw IllegalStateException("Not an API-key source")
                }
                _state.value = _state.value.copy(isLoading = false)
                startPolling(source)
                // Enqueue WorkManager background poller so notification fires even if screen is left.
                ImportPollingWorker.enqueue(context, source.name)
            } catch (e: HttpException) {
                val step = if (e.code() == 404) {
                    _state.value = _state.value.copy(isLoading = false, serverUnsupported = true)
                    ImportStep.ERROR
                } else {
                    ImportStep.ERROR
                }
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = if (e.code() == 404) null else "Import failed to start (${e.code()})",
                    step = step,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = e.message ?: "Import failed to start",
                    step = ImportStep.ERROR,
                )
            }
        }
    }

    private fun startPolling(source: ImportSource) {
        pollJob?.cancel()
        pollJob = viewModelScope.launch {
            while (true) {
                delay(POLL_INTERVAL_MS)
                try {
                    val response = when (source) {
                        ImportSource.REPAIR_DESK -> importApi.getRepairDeskStatus()
                        ImportSource.SHOPR       -> importApi.getRepairShoprStatus()
                        ImportSource.MRA         -> importApi.getMraStatus()
                        ImportSource.GENERIC_CSV -> break
                    }
                    val data = response.data as? Map<*, *> ?: break
                    val isActive = (data["is_active"] as? Boolean) ?: false
                    val overall = data["overall"] as? Map<*, *>

                    val importedCount = (overall?.get("imported") as? Number)?.toInt() ?: 0
                    val skippedCount  = (overall?.get("skipped") as? Number)?.toInt() ?: 0
                    val errorsCount   = (overall?.get("errors") as? Number)?.toInt() ?: 0
                    val totalRecords  = (overall?.get("total_records") as? Number)?.toInt() ?: 0

                    // Derive overall status from run list
                    @Suppress("UNCHECKED_CAST")
                    val runs = data["runs"] as? List<Map<*, *>> ?: emptyList()
                    val allDone = runs.isNotEmpty() && runs.all { r ->
                        val st = r["status"] as? String ?: ""
                        st == "completed" || st == "failed" || st == "cancelled"
                    }
                    val anyFailed = runs.any { r -> r["status"] == "failed" }

                    val jobStatus = when {
                        isActive -> ImportJobStatus.RUNNING
                        allDone && anyFailed -> ImportJobStatus.ERROR
                        allDone -> ImportJobStatus.DONE
                        else -> ImportJobStatus.RUNNING
                    }

                    // currentStep: find first running entity
                    val currentEntity = runs.firstOrNull { r -> r["status"] == "running" }
                        ?.get("entity_type") as? String ?: ""

                    val progress = ImportProgress(
                        status = jobStatus,
                        imported = importedCount,
                        skipped = skippedCount,
                        errors = errorsCount,
                        total = totalRecords,
                        currentStep = currentEntity,
                    )
                    _state.value = _state.value.copy(progress = progress)

                    if (jobStatus == ImportJobStatus.DONE || jobStatus == ImportJobStatus.ERROR) {
                        _state.value = _state.value.copy(
                            step = if (jobStatus == ImportJobStatus.DONE) ImportStep.DONE else ImportStep.ERROR,
                            error = if (jobStatus == ImportJobStatus.ERROR) "Import completed with errors — check server import history." else null,
                        )
                        break
                    }
                } catch (_: Exception) {
                    // Transient network error — keep polling
                }
            }
        }
    }

    // ── Generic CSV import ────────────────────────────────────────────────────

    private fun submitCsvImport() {
        val uri = _state.value.fileUri ?: return
        val scopes = _state.value.selectedScopes
        viewModelScope.launch {
            _state.value = _state.value.copy(
                isLoading = true,
                error = null,
                isDryRun = false,
                step = ImportStep.PROGRESS,
                progress = ImportProgress(status = ImportJobStatus.RUNNING),
            )
            try {
                val bytes = context.contentResolver.openInputStream(uri)?.readBytes()
                    ?: throw IllegalStateException("Cannot read file")
                val text = bytes.toString(Charsets.UTF_8)
                val lines = text.lines().filter { it.isNotBlank() }
                if (lines.size < 2) throw IllegalStateException("CSV must have a header row and at least one data row")

                val columns = parseCsvLine(lines[0])
                val mappings = _state.value.columnMappings

                // Build column index → crmField lookup
                val fieldByIndex = columns.indices.associate { i ->
                    i to (mappings.getOrNull(i)?.crmField ?: "")
                }.filter { it.value.isNotBlank() }

                val rows = lines.drop(1).map { parseCsvLine(it) }
                if (rows.isEmpty()) throw IllegalStateException("CSV contains no data rows")
                if (rows.size > 500) throw IllegalStateException("Maximum 500 rows per import. Found ${rows.size}.")

                val items: List<Map<String, Any?>> = rows.map { cells ->
                    buildMap {
                        fieldByIndex.forEach { (idx, crmField) ->
                            val key = crmField.substringAfter('.')  // "customer.first_name" → "first_name"
                            put(key, cells.getOrElse(idx) { "" }.takeIf { it.isNotBlank() })
                        }
                    }
                }

                // Determine which endpoint to hit from the selected scope
                val isInventoryScope = scopes.any { it == ImportScope.INVENTORY }

                val (imported, skipped, errors) = if (isInventoryScope) {
                    val resp = importApi.importInventoryCsv(InventoryCsvImportRequest(items))
                    val data = resp.data as? Map<*, *>
                    Triple(
                        (data?.get("created") as? Number)?.toInt() ?: 0,
                        0,
                        ((data?.get("errors") as? List<*>)?.size) ?: 0,
                    )
                } else {
                    val resp = importApi.importCustomerCsv(CustomerCsvImportRequest(items, skip_duplicates = true))
                    val data = resp.data as? Map<*, *>
                    Triple(
                        (data?.get("created") as? Number)?.toInt() ?: 0,
                        (data?.get("skipped") as? Number)?.toInt() ?: 0,
                        ((data?.get("errors") as? List<*>)?.size) ?: 0,
                    )
                }

                val progress = ImportProgress(
                    status = ImportJobStatus.DONE,
                    imported = imported,
                    skipped = skipped,
                    errors = errors,
                    total = rows.size,
                )
                _state.value = _state.value.copy(
                    isLoading = false,
                    progress = progress,
                    step = if (errors > 0 && imported == 0) ImportStep.ERROR else ImportStep.DONE,
                    error = if (errors > 0 && imported == 0) "$errors rows failed — no rows imported." else null,
                )
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    _state.value = _state.value.copy(isLoading = false, serverUnsupported = true, step = ImportStep.ERROR)
                } else {
                    _state.value = _state.value.copy(
                        isLoading = false,
                        error = "CSV import failed (${e.code()})",
                        step = ImportStep.ERROR,
                    )
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = e.message ?: "CSV import failed",
                    step = ImportStep.ERROR,
                )
            }
        }
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    override fun onCleared() {
        super.onCleared()
        pollJob?.cancel()
    }

    fun reset() {
        pollJob?.cancel()
        _state.value = DataImportUiState(isAdmin = isAdmin)
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    companion object {
        private const val POLL_INTERVAL_MS = 3_000L
        private const val PREVIEW_LIMIT = 20

        /**
         * Minimal RFC-4180-compatible CSV line parser.
         * Handles quoted fields, escaped double-quotes, and trims leading BOM.
         */
        fun parseCsvLine(line: String): List<String> {
            val stripped = line.trimStart('﻿')
            val result = mutableListOf<String>()
            var i = 0
            val sb = StringBuilder()
            while (i < stripped.length) {
                when {
                    stripped[i] == '"' -> {
                        i++ // skip opening quote
                        while (i < stripped.length) {
                            if (stripped[i] == '"') {
                                if (i + 1 < stripped.length && stripped[i + 1] == '"') {
                                    sb.append('"'); i += 2
                                } else {
                                    i++; break // closing quote
                                }
                            } else {
                                sb.append(stripped[i++])
                            }
                        }
                        // skip comma after closing quote
                        if (i < stripped.length && stripped[i] == ',') i++
                        result.add(sb.toString()); sb.clear()
                    }
                    stripped[i] == ',' -> {
                        result.add(sb.toString()); sb.clear(); i++
                    }
                    else -> sb.append(stripped[i++])
                }
            }
            result.add(sb.toString())
            return result
        }
    }
}
