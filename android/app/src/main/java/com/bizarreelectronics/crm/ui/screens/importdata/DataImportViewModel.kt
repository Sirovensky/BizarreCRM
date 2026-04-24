package com.bizarreelectronics.crm.ui.screens.importdata

import android.content.Context
import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.ImportApi
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.MultipartBody
import okhttp3.RequestBody.Companion.toRequestBody
import retrofit2.HttpException
import javax.inject.Inject

// ── Domain types ──────────────────────────────────────────────────────────────

enum class ImportSource(val label: String, val apiType: String) {
    REPAIR_DESK("RepairDesk CSV", "repairdesk_csv"),
    SHOPR("Shopr CSV", "shopr_csv"),
    MRA("MRA", "mra"),
    GENERIC_CSV("Generic CSV", "generic_csv"),
}

enum class ImportScope(val label: String, val apiValue: String) {
    CUSTOMERS("Customers", "customers"),
    TICKETS("Tickets", "tickets"),
    INVOICES("Invoices", "invoices"),
    INVENTORY("Inventory", "inventory"),
    EMPLOYEES("Employees", "employees"),
}

enum class ImportStep { SOURCE, FILE, SCOPE, COLUMN_MAP, PREVIEW, PROGRESS, DONE, ERROR }

enum class ImportJobStatus { QUEUED, RUNNING, DONE, ERROR }

/** One row parsed from the server's /imports/preview response. */
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
    val fileUri: Uri? = null,
    val fileName: String = "",
    val columnMappings: List<ColumnMapping> = emptyList(),
    val preview: PreviewData = PreviewData(),
    val isDryRun: Boolean = false,
    val progress: ImportProgress = ImportProgress(),
    val jobId: String? = null,
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
 * Wizard steps: SOURCE → FILE → SCOPE → COLUMN_MAP → PREVIEW → PROGRESS → DONE
 *
 * Role gate: admin only. Non-admin users see an "access denied" empty state.
 * 404-tolerant: if the server doesn't have the imports API, sets serverUnsupported=true.
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

    fun goBack() {
        val prev = when (_state.value.step) {
            ImportStep.FILE       -> ImportStep.SOURCE
            ImportStep.SCOPE      -> ImportStep.FILE
            ImportStep.COLUMN_MAP -> ImportStep.SCOPE
            ImportStep.PREVIEW    -> ImportStep.COLUMN_MAP
            else                  -> ImportStep.SOURCE
        }
        _state.value = _state.value.copy(step = prev, error = null)
    }

    fun clearToast() {
        _state.value = _state.value.copy(toastMessage = null)
    }

    // ── Preview (dry-run parse) ───────────────────────────────────────────────

    fun loadPreview() {
        val uri = _state.value.fileUri ?: return
        if (!serverMonitor.isEffectivelyOnline.value) {
            _state.value = _state.value.copy(error = "Device is offline")
            return
        }
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                val bytes = context.contentResolver.openInputStream(uri)?.readBytes()
                    ?: throw IllegalStateException("Cannot read file")
                val filePart = MultipartBody.Part.createFormData(
                    "file", _state.value.fileName,
                    bytes.toRequestBody("text/csv".toMediaTypeOrNull()),
                )
                val typePart = _state.value.selectedSource.apiType
                    .toRequestBody("text/plain".toMediaTypeOrNull())
                val limitPart = "20".toRequestBody("text/plain".toMediaTypeOrNull())

                val response = importApi.previewImport(typePart, filePart, limitPart)
                val data = response.data as? Map<*, *>
                @Suppress("UNCHECKED_CAST")
                val columns = (data?.get("columns") as? List<String>) ?: emptyList()
                @Suppress("UNCHECKED_CAST")
                val rows = (data?.get("rows") as? List<List<String>>) ?: emptyList()
                val preview = PreviewData(columns = columns, rows = rows)
                // Auto-populate column mappings from server-detected columns
                val mappings = columns.map { col -> ColumnMapping(sourceColumn = col, crmField = "") }
                _state.value = _state.value.copy(
                    isLoading = false,
                    preview = preview,
                    columnMappings = mappings,
                    step = ImportStep.COLUMN_MAP,
                )
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    _state.value = _state.value.copy(isLoading = false, serverUnsupported = true)
                } else {
                    _state.value = _state.value.copy(
                        isLoading = false,
                        error = "Preview failed (${e.code()})",
                    )
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = e.message ?: "Preview failed",
                )
            }
        }
    }

    // ── Import execution ──────────────────────────────────────────────────────

    /** Start a dry run (validate only, no DB writes). */
    fun startDryRun() {
        startImportJob(dryRun = true)
    }

    /** Commit the actual import after dry-run passes. */
    fun commitImport() {
        startImportJob(dryRun = false)
    }

    private fun startImportJob(dryRun: Boolean) {
        val uri = _state.value.fileUri ?: return
        if (!serverMonitor.isEffectivelyOnline.value) {
            _state.value = _state.value.copy(error = "Device is offline")
            return
        }
        viewModelScope.launch {
            _state.value = _state.value.copy(
                isLoading = true,
                error = null,
                isDryRun = dryRun,
                step = ImportStep.PROGRESS,
                progress = ImportProgress(status = ImportJobStatus.QUEUED),
            )
            try {
                val bytes = context.contentResolver.openInputStream(uri)?.readBytes()
                    ?: throw IllegalStateException("Cannot read file")
                val filePart = MultipartBody.Part.createFormData(
                    "file", _state.value.fileName,
                    bytes.toRequestBody("text/csv".toMediaTypeOrNull()),
                )
                val typePart = _state.value.selectedSource.apiType
                    .toRequestBody("text/plain".toMediaTypeOrNull())
                val mappingJson = buildMappingJson(_state.value.columnMappings)
                    .toRequestBody("application/json".toMediaTypeOrNull())
                val dryRunPart = (if (dryRun) "true" else "false")
                    .toRequestBody("text/plain".toMediaTypeOrNull())
                val scopePart = _state.value.selectedScopes.joinToString(",") { it.apiValue }
                    .toRequestBody("text/plain".toMediaTypeOrNull())

                val response = importApi.startImport(typePart, filePart, mappingJson, dryRunPart, scopePart)
                val jobId = ((response.data as? Map<*, *>)?.get("job_id") as? String)
                    ?: throw IllegalStateException("Server did not return job_id")

                _state.value = _state.value.copy(isLoading = false, jobId = jobId)
                startPolling(jobId)
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    _state.value = _state.value.copy(
                        isLoading = false, serverUnsupported = true, step = ImportStep.ERROR,
                    )
                } else {
                    _state.value = _state.value.copy(
                        isLoading = false,
                        error = "Import failed to start (${e.code()})",
                        step = ImportStep.ERROR,
                    )
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = e.message ?: "Import failed to start",
                    step = ImportStep.ERROR,
                )
            }
        }
    }

    private fun startPolling(jobId: String) {
        pollJob?.cancel()
        pollJob = viewModelScope.launch {
            while (true) {
                delay(POLL_INTERVAL_MS)
                try {
                    val response = importApi.getImportStatus(jobId)
                    val data = response.data as? Map<*, *> ?: break
                    val statusStr = (data["status"] as? String)?.uppercase() ?: "RUNNING"
                    val status = runCatching { ImportJobStatus.valueOf(statusStr) }
                        .getOrDefault(ImportJobStatus.RUNNING)
                    val progress = ImportProgress(
                        status = status,
                        imported = (data["imported"] as? Number)?.toInt() ?: 0,
                        skipped = (data["skipped"] as? Number)?.toInt() ?: 0,
                        errors = (data["errors"] as? Number)?.toInt() ?: 0,
                        total = (data["total"] as? Number)?.toInt() ?: 0,
                        currentStep = (data["current_step"] as? String) ?: "",
                        errorCsvUrl = data["error_csv_url"] as? String,
                    )
                    _state.value = _state.value.copy(progress = progress)
                    if (status == ImportJobStatus.DONE || status == ImportJobStatus.ERROR) {
                        _state.value = _state.value.copy(
                            step = if (status == ImportJobStatus.DONE) ImportStep.DONE else ImportStep.ERROR,
                        )
                        break
                    }
                } catch (_: Exception) {
                    // Transient network error — keep polling
                }
            }
        }
    }

    override fun onCleared() {
        super.onCleared()
        pollJob?.cancel()
    }

    fun reset() {
        pollJob?.cancel()
        _state.value = DataImportUiState(isAdmin = isAdmin)
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun buildMappingJson(mappings: List<ColumnMapping>): String {
        val entries = mappings
            .filter { it.crmField.isNotBlank() }
            .joinToString(",") { m ->
                val src = m.sourceColumn.replace("\"", "\\\"")
                val crm = m.crmField.replace("\"", "\\\"")
                "\"$src\":\"$crm\""
            }
        return "{$entries}"
    }

    companion object {
        private const val POLL_INTERVAL_MS = 3_000L
    }
}
