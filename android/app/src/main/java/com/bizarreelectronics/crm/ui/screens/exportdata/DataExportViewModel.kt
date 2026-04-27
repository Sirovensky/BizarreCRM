package com.bizarreelectronics.crm.ui.screens.exportdata

import android.content.Context
import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.ExportApi
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import retrofit2.HttpException
import javax.inject.Inject

// ── Domain types ──────────────────────────────────────────────────────────────

enum class ExportEntity(val label: String, val apiValue: String) {
    CUSTOMERS("Customers", "customers"),
    TICKETS("Tickets", "tickets"),
    INVOICES("Invoices", "invoices"),
    INVENTORY("Inventory", "inventory"),
    EXPENSES("Expenses", "expenses"),
    EMPLOYEES("Employees", "employees"),
}

enum class ExportFormat(val label: String, val apiValue: String, val mimeType: String) {
    CSV("CSV", "csv", "text/csv"),
    JSON("JSON", "json", "application/json"),
    XLSX("Excel (XLSX)", "xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"),
}

enum class ExportJobStatus { QUEUED, RUNNING, READY, ERROR }

data class DataExportUiState(
    val selectedEntities: Set<ExportEntity> = setOf(ExportEntity.CUSTOMERS, ExportEntity.TICKETS),
    val selectedFormat: ExportFormat = ExportFormat.CSV,
    val dateFrom: String = "",   // ISO-8601 date string, empty = no filter
    val dateTo: String = "",
    val activeOnly: Boolean = false,
    val emailOnReady: Boolean = false,
    val jobId: String? = null,
    val jobStatus: ExportJobStatus = ExportJobStatus.QUEUED,
    val progress: Int = 0,
    val downloadUrl: String? = null,
    val isLoading: Boolean = false,
    val isPollActive: Boolean = false,
    /** True while streaming the export archive to the SAF URI. */
    val isDownloading: Boolean = false,
    val error: String? = null,
    val serverUnsupported: Boolean = false,
    /** True if the signed-in user is manager or above. */
    val canExport: Boolean = false,
    val toastMessage: String? = null,
    /** True while the "Cancel export?" ConfirmDialog is visible. */
    val showCancelConfirm: Boolean = false,
)

/**
 * §51 — Data Export ViewModel
 *
 * Role gate: manager+ for exports (staff cannot export).
 * 404-tolerant: server not implementing the exports API → serverUnsupported = true.
 *
 * Flow:
 *  1. User configures entities, format, date range.
 *  2. [requestExport] → POST /exports/start → jobId.
 *  3. Poll GET /exports/:id/status every 3 s until status == "ready".
 *  4. Expose [downloadUrl]; UI triggers SAF ACTION_CREATE_DOCUMENT.
 */
@HiltViewModel
class DataExportViewModel @Inject constructor(
    private val exportApi: ExportApi,
    private val authPreferences: AuthPreferences,
    private val serverMonitor: ServerReachabilityMonitor,
    private val okHttpClient: OkHttpClient,
) : ViewModel() {

    private val _state = MutableStateFlow(DataExportUiState())
    val state = _state.asStateFlow()

    private var pollJob: Job? = null

    private val canExport: Boolean
        get() = authPreferences.userRole?.lowercase() in setOf("manager", "admin", "owner")

    init {
        _state.value = _state.value.copy(canExport = canExport)
    }

    // ── Configuration mutations ────────────────────────────────────────────────

    fun toggleEntity(entity: ExportEntity) {
        val current = _state.value.selectedEntities
        val updated = if (entity in current) current - entity else current + entity
        _state.value = _state.value.copy(selectedEntities = updated.ifEmpty { setOf(entity) })
    }

    fun setFormat(format: ExportFormat) {
        _state.value = _state.value.copy(selectedFormat = format)
    }

    fun setDateFrom(date: String) {
        _state.value = _state.value.copy(dateFrom = date, error = null)
    }

    fun setDateTo(date: String) {
        _state.value = _state.value.copy(dateTo = date, error = null)
    }

    fun setActiveOnly(value: Boolean) {
        _state.value = _state.value.copy(activeOnly = value)
    }

    fun setEmailOnReady(value: Boolean) {
        _state.value = _state.value.copy(emailOnReady = value)
    }

    fun clearToast() {
        _state.value = _state.value.copy(toastMessage = null)
    }

    fun resetJob() {
        pollJob?.cancel()
        _state.value = _state.value.copy(
            jobId = null,
            jobStatus = ExportJobStatus.QUEUED,
            progress = 0,
            downloadUrl = null,
            isLoading = false,
            isPollActive = false,
            isDownloading = false,
            error = null,
            showCancelConfirm = false,
        )
    }

    // ── Cancel export ──────────────────────────────────────────────────────────

    /** Show the "Cancel export?" confirmation dialog. */
    fun promptCancelExport() {
        _state.value = _state.value.copy(showCancelConfirm = true)
    }

    /** User dismissed the cancel dialog without confirming. */
    fun dismissCancelExport() {
        _state.value = _state.value.copy(showCancelConfirm = false)
    }

    /** User confirmed cancellation — stop polling and reset to config form. */
    fun confirmCancelExport() {
        resetJob()
    }

    // ── SAF download ───────────────────────────────────────────────────────────

    /**
     * §51.3 — Stream the export archive from [downloadUrl] into [destUri] using
     * the existing authenticated OkHttpClient so that the auth interceptor adds
     * the Bearer token automatically.
     *
     * Written to the SAF URI via [Context.contentResolver] so no external storage
     * permission is required (ACTION_CREATE_DOCUMENT hands us the URI).
     */
    fun downloadTo(context: Context, destUri: Uri) {
        val url = _state.value.downloadUrl ?: return
        viewModelScope.launch {
            _state.value = _state.value.copy(isDownloading = true, error = null)
            try {
                withContext(Dispatchers.IO) {
                    val request = Request.Builder().url(url).build()
                    okHttpClient.newCall(request).execute().use { response ->
                        if (!response.isSuccessful) {
                            throw IllegalStateException("Download failed: HTTP ${response.code}")
                        }
                        val body = response.body
                            ?: throw IllegalStateException("Empty response body")
                        context.contentResolver.openOutputStream(destUri)?.use { out ->
                            body.byteStream().copyTo(out)
                        } ?: throw IllegalStateException("Could not open output stream")
                    }
                }
                _state.value = _state.value.copy(
                    isDownloading = false,
                    toastMessage = "Export saved.",
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isDownloading = false,
                    error = e.message ?: "Download failed",
                )
            }
        }
    }

    // ── Export request ─────────────────────────────────────────────────────────

    fun requestExport() {
        if (!serverMonitor.isEffectivelyOnline.value) {
            _state.value = _state.value.copy(error = "Device is offline")
            return
        }
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                val body = buildMap<String, Any> {
                    put("entity_types", _state.value.selectedEntities.map { it.apiValue })
                    put("format", _state.value.selectedFormat.apiValue)
                    put("active_only", _state.value.activeOnly)
                    put("email", _state.value.emailOnReady)
                    val from = _state.value.dateFrom.trim()
                    if (from.isNotBlank()) put("date_from", from)
                    val to = _state.value.dateTo.trim()
                    if (to.isNotBlank()) put("date_to", to)
                }
                val response = exportApi.startExport(body)
                val jobId = ((response.data as? Map<*, *>)?.get("job_id") as? String)
                    ?: throw IllegalStateException("Server did not return job_id")

                _state.value = _state.value.copy(
                    isLoading = false,
                    jobId = jobId,
                    isPollActive = true,
                    jobStatus = ExportJobStatus.QUEUED,
                )
                startPolling(jobId)
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    _state.value = _state.value.copy(isLoading = false, serverUnsupported = true)
                } else {
                    _state.value = _state.value.copy(
                        isLoading = false,
                        error = "Export request failed (${e.code()})",
                    )
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = e.message ?: "Export failed",
                )
            }
        }
    }

    // ── Polling ────────────────────────────────────────────────────────────────

    private fun startPolling(jobId: String) {
        pollJob?.cancel()
        pollJob = viewModelScope.launch {
            while (true) {
                delay(POLL_INTERVAL_MS)
                try {
                    val response = exportApi.getExportStatus(jobId)
                    val data = response.data as? Map<*, *> ?: break
                    val statusStr = (data["status"] as? String)?.uppercase() ?: "RUNNING"
                    val status = runCatching { ExportJobStatus.valueOf(statusStr) }
                        .getOrDefault(ExportJobStatus.RUNNING)
                    val progress = (data["progress"] as? Number)?.toInt() ?: 0
                    val downloadUrl = data["download_url"] as? String
                    _state.value = _state.value.copy(
                        jobStatus = status,
                        progress = progress,
                        downloadUrl = downloadUrl,
                    )
                    when (status) {
                        ExportJobStatus.READY -> {
                            _state.value = _state.value.copy(
                                isPollActive = false,
                                toastMessage = "Export ready — tap Download to save.",
                            )
                            break
                        }
                        ExportJobStatus.ERROR -> {
                            val msg = (data["error_message"] as? String) ?: "Export failed on server."
                            _state.value = _state.value.copy(
                                isPollActive = false,
                                error = msg,
                            )
                            break
                        }
                        else -> Unit // keep polling
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

    companion object {
        private const val POLL_INTERVAL_MS = 3_000L
    }
}
