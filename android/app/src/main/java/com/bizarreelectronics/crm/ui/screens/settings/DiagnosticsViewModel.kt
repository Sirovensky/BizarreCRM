package com.bizarreelectronics.crm.ui.screens.settings

import android.app.Application
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.util.AppError
import com.bizarreelectronics.crm.util.DbExporter
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.IOException
import javax.inject.Inject

/**
 * State emitted by [DiagnosticsViewModel] for the export operation.
 *
 * [plan:L185] — ActionPlan §1.3 line 185.
 */
sealed class ExportState {
    /** No export in progress or result pending. */
    data object Idle : ExportState()

    /**
     * Export is running. [bytesWritten] is the cumulative bytes written so far;
     * may be zero if the database files haven't been read yet.
     */
    data class InProgress(val bytesWritten: Long) : ExportState()

    /** Export completed successfully. */
    data class Success(val uri: Uri, val sizeBytes: Long) : ExportState()

    /** Export failed; [error] carries a user-friendly [AppError.Storage] entry. */
    data class Error(val error: AppError) : ExportState()
}

/**
 * ViewModel for [DiagnosticsScreen].
 *
 * Exposes [exportState] as a [StateFlow] so the screen can observe progress
 * and result without coupling to coroutine lifecycle directly.
 *
 * Uses [AndroidViewModel] (rather than plain [ViewModel]) so it can access
 * [Application.contentResolver] and [Application.getDatabasePath] without
 * requiring a [Context] parameter on [export], which would risk leaking an
 * Activity context across configuration changes.
 *
 * [plan:L185] — ActionPlan §1.3 line 185.
 */
@HiltViewModel
class DiagnosticsViewModel @Inject constructor(
    application: Application,
) : AndroidViewModel(application) {

    private val _exportState = MutableStateFlow<ExportState>(ExportState.Idle)
    val exportState: StateFlow<ExportState> = _exportState.asStateFlow()

    /**
     * Launches the database export into the SAF [uri] chosen by the user.
     *
     * The operation runs on [Dispatchers.IO]. Progress is reported via
     * [ExportState.InProgress] updates. On completion the state transitions
     * to [ExportState.Success] or [ExportState.Error].
     *
     * A null [uri] is treated as a user cancellation and leaves the state as
     * [ExportState.Idle].
     */
    fun export(uri: Uri?) {
        if (uri == null) return // user dismissed the SAF picker
        if (_exportState.value is ExportState.InProgress) return // guard against double-tap

        _exportState.value = ExportState.InProgress(bytesWritten = 0L)

        viewModelScope.launch {
            val result = runExport(uri)
            _exportState.value = result
        }
    }

    /** Resets state back to [ExportState.Idle] so the user can retry or dismiss. */
    fun resetState() {
        _exportState.value = ExportState.Idle
    }

    // ── internals ────────────────────────────────────────────────────────────

    private suspend fun runExport(uri: Uri): ExportState = withContext(Dispatchers.IO) {
        try {
            val app = getApplication<Application>()
            val dbFile = app.getDatabasePath(DB_NAME)
            val databasesDir = dbFile.parentFile
                ?: return@withContext ExportState.Error(
                    AppError.Storage("Cannot locate databases directory on this device.")
                )

            val totalBytes = DbExporter.export(
                databasesDir = databasesDir,
                dbName = DB_NAME,
                resolver = app.contentResolver,
                destUri = uri,
                onProgress = { written ->
                    _exportState.value = ExportState.InProgress(bytesWritten = written)
                },
            )

            ExportState.Success(uri = uri, sizeBytes = totalBytes)
        } catch (e: SecurityException) {
            ExportState.Error(
                AppError.Storage("Permission denied writing to the selected location: ${e.message}")
            )
        } catch (e: IOException) {
            ExportState.Error(
                AppError.Storage("I/O error during export: ${e.message}")
            )
        } catch (e: IllegalStateException) {
            ExportState.Error(
                AppError.Storage("Could not open output stream for the selected file: ${e.message}")
            )
        }
    }

    private companion object {
        const val DB_NAME = "bizarre-crm.db"
    }
}
