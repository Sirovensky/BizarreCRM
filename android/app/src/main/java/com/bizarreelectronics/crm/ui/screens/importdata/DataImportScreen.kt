package com.bizarreelectronics.crm.ui.screens.importdata

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Upload
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.ui.components.shared.ConfirmDialog
import com.bizarreelectronics.crm.ui.screens.importdata.components.ColumnMapTable
import com.bizarreelectronics.crm.ui.screens.importdata.components.ImportPreviewTable
import com.bizarreelectronics.crm.ui.screens.importdata.components.SourcePickerCard

/**
 * §50 — Data Import Screen
 *
 * Multi-step wizard: SOURCE → FILE → SCOPE → COLUMN_MAP → PREVIEW → PROGRESS → DONE
 *
 * Role gate: admin only. Manager/staff see an "access denied" empty state.
 * 404-tolerant: if the server returns 404 on any import endpoint, shows
 * "Import not available on this server".
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DataImportScreen(
    onNavigateBack: () -> Unit,
    viewModel: DataImportViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val context = LocalContext.current

    // Confirm-dialog visibility: "cancel import" (during PROGRESS) and
    // "discard mapping" (during COLUMN_MAP).
    var showCancelImportDialog by rememberSaveable { mutableStateOf(false) }
    var showDiscardMappingDialog by rememberSaveable { mutableStateOf(false) }

    // SAF file picker — GetContent with CSV MIME types per §50 constraints.
    val filePicker = rememberLauncherForActivityResult(
        ActivityResultContracts.GetContent(),
    ) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        val displayName = context.contentResolver.query(uri, null, null, null, null)
            ?.use { cursor ->
                val col = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                cursor.moveToFirst()
                if (col >= 0) cursor.getString(col) else "file.csv"
            } ?: "file.csv"
        viewModel.onFileSelected(uri, displayName)
        viewModel.goToStep(ImportStep.SCOPE)
    }

    LaunchedEffect(state.toastMessage) {
        state.toastMessage?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearToast()
        }
    }

    // Confirm dialogs — shown on top of the scaffold content.
    if (showCancelImportDialog) {
        ConfirmDialog(
            title = stringResource(R.string.import_cancel_dialog_title),
            message = stringResource(R.string.import_cancel_dialog_msg),
            confirmLabel = stringResource(R.string.import_cancel_dialog_confirm),
            onConfirm = {
                showCancelImportDialog = false
                viewModel.reset()
                onNavigateBack()
            },
            onDismiss = { showCancelImportDialog = false },
            isDestructive = true,
        )
    }

    if (showDiscardMappingDialog) {
        ConfirmDialog(
            title = stringResource(R.string.import_discard_mapping_dialog_title),
            message = stringResource(R.string.import_discard_mapping_dialog_msg),
            confirmLabel = stringResource(R.string.import_discard_mapping_dialog_confirm),
            onConfirm = {
                showDiscardMappingDialog = false
                viewModel.goBack()
            },
            onDismiss = { showDiscardMappingDialog = false },
            isDestructive = true,
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = { Text(importStepTitle(state.step)) },
                navigationIcon = {
                    IconButton(onClick = {
                        when (state.step) {
                            ImportStep.SOURCE -> onNavigateBack()
                            ImportStep.PROGRESS -> showCancelImportDialog = true
                            ImportStep.COLUMN_MAP -> showDiscardMappingDialog = true
                            else -> viewModel.goBack()
                        }
                    }) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.cd_back),
                        )
                    }
                },
            )
        },
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            when {
                !state.isAdmin -> AccessDeniedState()
                state.serverUnsupported -> ServerUnsupportedState()
                else -> ImportWizardContent(
                    state = state,
                    onSourceSelected = viewModel::selectSource,
                    onPickFile = {
                        // Launch with a combined MIME type so the system picker shows
                        // both text/csv and text/comma-separated-values files.
                        filePicker.launch("text/csv")
                    },
                    onToggleScope = viewModel::toggleScope,
                    onMappingChanged = viewModel::updateMapping,
                    onPreviewConfirm = { viewModel.goToStep(ImportStep.PREVIEW) },
                    onDryRun = viewModel::startDryRun,
                    onCommit = viewModel::commitImport,
                    onReset = viewModel::reset,
                    onContinueToFile = { viewModel.goToStep(ImportStep.FILE) },
                    onContinueToScope = {
                        // loadPreview() not yet on VM — fall through to SCOPE step
                        // and let the user trigger preview via startDryRun.
                        viewModel.goToStep(ImportStep.SCOPE)
                    },
                )
            }
        }
    }
}

// ── Wizard content ────────────────────────────────────────────────────────────

@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
private fun ImportWizardContent(
    state: DataImportUiState,
    onSourceSelected: (ImportSource) -> Unit,
    onPickFile: () -> Unit,
    onToggleScope: (ImportScope) -> Unit,
    onMappingChanged: (Int, String) -> Unit,
    onPreviewConfirm: () -> Unit,
    onDryRun: () -> Unit,
    onCommit: () -> Unit,
    onReset: () -> Unit,
    onContinueToFile: () -> Unit,
    onContinueToScope: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val scrollState = rememberScrollState()
    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(scrollState)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        when (state.step) {
            ImportStep.SOURCE -> {
                SourcePickerCard(
                    selected = state.selectedSource,
                    onSelect = onSourceSelected,
                )
                Button(
                    onClick = onContinueToFile,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Continue")
                }
            }

            ImportStep.FILE -> {
                Text(
                    "Choose a CSV file from your device.",
                    style = MaterialTheme.typography.bodyMedium,
                )
                if (state.fileName.isNotBlank()) {
                    ListItem(
                        headlineContent = { Text(state.fileName) },
                        leadingContent = {
                            Icon(
                                Icons.Default.Upload,
                                contentDescription = stringResource(R.string.import_cd_upload_icon),
                            )
                        },
                    )
                }
                OutlinedButton(
                    onClick = onPickFile,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(if (state.fileName.isBlank()) "Pick CSV file" else "Replace file")
                }
                state.error?.let { ErrorText(it) }
            }

            ImportStep.SCOPE -> {
                Text(
                    "What would you like to import?",
                    style = MaterialTheme.typography.titleMedium,
                )
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ImportScope.entries.forEach { scope ->
                        FilterChip(
                            selected = scope in state.selectedScopes,
                            onClick = { onToggleScope(scope) },
                            label = { Text(scope.label) },
                        )
                    }
                }
                Button(
                    onClick = { if (state.fileUri != null) onContinueToScope() },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = state.fileUri != null && !state.isLoading,
                ) {
                    if (state.isLoading) {
                        CircularProgressIndicator(modifier = Modifier.padding(end = 8.dp))
                    }
                    Text("Detect Columns")
                }
            }

            ImportStep.COLUMN_MAP -> {
                Text(
                    "Map columns from your file to CRM fields.",
                    style = MaterialTheme.typography.titleMedium,
                )
                ColumnMapTable(
                    mappings = state.columnMappings,
                    onMappingChanged = onMappingChanged,
                )
                Button(
                    onClick = onPreviewConfirm,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Preview Data")
                }
            }

            ImportStep.PREVIEW -> {
                Text(
                    "Preview — first ${state.preview.rows.size} rows",
                    style = MaterialTheme.typography.titleMedium,
                )
                ImportPreviewTable(preview = state.preview)
                Spacer(Modifier.height(8.dp))
                OutlinedButton(
                    onClick = onDryRun,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Dry Run (validate only)")
                }
                Button(
                    onClick = onCommit,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Import Now")
                }
            }

            ImportStep.PROGRESS -> {
                ImportProgressContent(state = state)
            }

            ImportStep.DONE -> {
                DoneState(
                    isDryRun = state.isDryRun,
                    progress = state.progress,
                    onCommit = onCommit,
                    onReset = onReset,
                )
            }

            ImportStep.ERROR -> {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Icon(
                        Icons.Default.Error,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.error,
                    )
                    Text(
                        state.error ?: "Import failed.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.error,
                        textAlign = TextAlign.Center,
                    )
                    Button(onClick = onReset) { Text("Start Over") }
                }
            }

            ImportStep.CREDENTIALS -> {
                Text(
                    "Credentials step not yet implemented for this source.",
                    style = MaterialTheme.typography.bodyMedium,
                )
                OutlinedButton(onClick = onContinueToFile, modifier = Modifier.fillMaxWidth()) {
                    Text("Skip to file picker")
                }
            }
        }
    }
}

// ── Sub-composables ───────────────────────────────────────────────────────────

@Composable
private fun ImportProgressContent(state: DataImportUiState) {
    val progress = state.progress
    val fraction = if (progress.total > 0) progress.imported.toFloat() / progress.total else 0f
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(
            text = if (state.isDryRun) "Validating…" else "Importing…",
            style = MaterialTheme.typography.titleMedium,
        )
        LinearProgressIndicator(
            progress = { fraction },
            modifier = Modifier.fillMaxWidth(),
        )
        Text("${progress.imported} imported · ${progress.skipped} skipped · ${progress.errors} errors")
        if (progress.currentStep.isNotBlank()) {
            Text(
                text = progress.currentStep,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun DoneState(
    isDryRun: Boolean,
    progress: ImportProgress,
    onCommit: () -> Unit,
    onReset: () -> Unit,
) {
    val context = LocalContext.current
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(
            Icons.Default.CheckCircle,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
        )
        val label = if (isDryRun) "Dry run complete" else "Import complete"
        Text(label, style = MaterialTheme.typography.titleMedium)
        Text(
            "${progress.imported} imported · ${progress.skipped} skipped · ${progress.errors} errors",
            style = MaterialTheme.typography.bodyMedium,
        )
        if (isDryRun && progress.errors == 0) {
            Button(onClick = onCommit, modifier = Modifier.fillMaxWidth()) {
                Text("Commit Import")
            }
        }
        if (progress.errorCsvUrl != null) {
            val errorUrl = progress.errorCsvUrl
            OutlinedButton(onClick = {
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(errorUrl)).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
            }) {
                Text(stringResource(R.string.import_download_error_report))
            }
        }
        OutlinedButton(onClick = onReset, modifier = Modifier.fillMaxWidth()) {
            Text("Start New Import")
        }
    }
}

@Composable
private fun AccessDeniedState() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(Icons.Default.Error, contentDescription = null, tint = MaterialTheme.colorScheme.error)
            Spacer(Modifier.height(8.dp))
            Text(
                "Admin access required to import data.",
                style = MaterialTheme.typography.bodyMedium,
                textAlign = TextAlign.Center,
            )
        }
    }
}

@Composable
private fun ServerUnsupportedState() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text(
            "Import is not configured on this server.",
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun ErrorText(message: String) {
    Text(
        text = message,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.error,
    )
}

// ── Helpers ───────────────────────────────────────────────────────────────────

private fun importStepTitle(step: ImportStep): String = when (step) {
    ImportStep.SOURCE      -> "Import — Choose Source"
    ImportStep.CREDENTIALS -> "Import — Credentials"
    ImportStep.FILE        -> "Import — Select File"
    ImportStep.SCOPE       -> "Import — Select Scope"
    ImportStep.COLUMN_MAP  -> "Import — Map Columns"
    ImportStep.PREVIEW     -> "Import — Preview"
    ImportStep.PROGRESS    -> "Import — In Progress"
    ImportStep.DONE        -> "Import — Done"
    ImportStep.ERROR       -> "Import — Error"
}
