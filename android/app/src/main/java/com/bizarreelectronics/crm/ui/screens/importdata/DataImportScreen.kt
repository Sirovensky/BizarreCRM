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
import androidx.compose.foundation.text.KeyboardOptions
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
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.ui.components.EmptyStateIllustration
import com.bizarreelectronics.crm.ui.screens.importdata.components.ColumnMapTable
import com.bizarreelectronics.crm.ui.screens.importdata.components.ImportPreviewTable
import com.bizarreelectronics.crm.ui.screens.importdata.components.SourcePickerCard

/**
 * §50 — Data Import Screen
 *
 * Multi-step wizard: SOURCE → CREDENTIALS (API-key sources) / FILE (CSV) → SCOPE
 *   → COLUMN_MAP (CSV only) → PREVIEW (CSV only) → PROGRESS → DONE/ERROR
 *
 * Role gate: admin only. Manager/staff see an "access denied" empty state.
 * 404-tolerant: if the server returns 404 on any import endpoint, shows
 * "Import not available on this server".
 *
 * SAF file picker: uses ACTION_OPEN_DOCUMENT with text/csv MIME filter.
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

    // SAF file picker — ACTION_OPEN_DOCUMENT persists a read URI permission.
    val filePicker = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument(),
    ) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        context.contentResolver.takePersistableUriPermission(
            uri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION,
        )
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

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = { Text(importStepTitle(state.step)) },
                navigationIcon = {
                    IconButton(onClick = {
                        if (state.step == ImportStep.SOURCE) onNavigateBack()
                        else viewModel.goBack()
                    }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
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
                    onContinueFromSource = viewModel::continueFromSource,
                    onApiKeyChanged = viewModel::onApiKeyChanged,
                    onSubdomainChanged = viewModel::onSubdomainChanged,
                    onContinueFromCredentials = viewModel::continueFromCredentials,
                    onPickFile = {
                        filePicker.launch(arrayOf("text/csv", "text/comma-separated-values", "*/*"))
                    },
                    onToggleScope = viewModel::toggleScope,
                    onMappingChanged = viewModel::updateMapping,
                    onDetectColumns = viewModel::loadCsvPreview,
                    onPreviewConfirm = { viewModel.goToStep(ImportStep.PREVIEW) },
                    onCommit = viewModel::commitImport,
                    onStartDryRun = viewModel::startDryRun,
                    onReset = viewModel::reset,
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
    onContinueFromSource: () -> Unit,
    onApiKeyChanged: (String) -> Unit,
    onSubdomainChanged: (String) -> Unit,
    onContinueFromCredentials: () -> Unit,
    onPickFile: () -> Unit,
    onToggleScope: (ImportScope) -> Unit,
    onMappingChanged: (Int, String) -> Unit,
    onDetectColumns: () -> Unit,
    onPreviewConfirm: () -> Unit,
    onCommit: () -> Unit,
    onStartDryRun: () -> Unit,
    onReset: () -> Unit,
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

            // ── Step 1: Source ────────────────────────────────────────────────
            ImportStep.SOURCE -> {
                SourcePickerCard(
                    selected = state.selectedSource,
                    onSelect = onSourceSelected,
                )
                Button(
                    onClick = onContinueFromSource,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Continue")
                }
            }

            // ── Step 2: Credentials (API-key sources only) ────────────────────
            ImportStep.CREDENTIALS -> {
                Text(
                    "Enter your ${state.selectedSource.label} credentials.",
                    style = MaterialTheme.typography.bodyMedium,
                )
                OutlinedTextField(
                    value = state.apiKey,
                    onValueChange = onApiKeyChanged,
                    label = { Text("API Key") },
                    singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    modifier = Modifier.fillMaxWidth(),
                )
                if (state.selectedSource == ImportSource.SHOPR) {
                    OutlinedTextField(
                        value = state.subdomain,
                        onValueChange = onSubdomainChanged,
                        label = { Text("Subdomain (e.g. acme)") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                state.error?.let { ErrorText(it) }
                Button(
                    onClick = onContinueFromCredentials,
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !state.isLoading,
                ) {
                    Text("Continue")
                }
            }

            // ── Step 3: File (CSV only) ───────────────────────────────────────
            ImportStep.FILE -> {
                Text(
                    "Choose a CSV file from your device.",
                    style = MaterialTheme.typography.bodyMedium,
                )
                if (state.fileName.isNotBlank()) {
                    ListItem(
                        headlineContent = { Text(state.fileName) },
                        leadingContent = {
                            Icon(Icons.Default.Upload, contentDescription = null)
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

            // ── Step 4: Scope ─────────────────────────────────────────────────
            ImportStep.SCOPE -> {
                Text(
                    "What would you like to import?",
                    style = MaterialTheme.typography.titleMedium,
                )
                val availableScopes = if (state.selectedSource == ImportSource.GENERIC_CSV) {
                    listOf(ImportScope.CUSTOMERS, ImportScope.INVENTORY)
                } else {
                    ImportScope.entries.filter { it != ImportScope.EMPLOYEES || state.selectedSource == ImportSource.REPAIR_DESK }
                }
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    availableScopes.forEach { scope ->
                        FilterChip(
                            selected = scope in state.selectedScopes,
                            onClick = { onToggleScope(scope) },
                            label = { Text(scope.label) },
                        )
                    }
                }

                if (state.selectedSource == ImportSource.GENERIC_CSV) {
                    // CSV path: need to detect columns from the file
                    Button(
                        onClick = {
                            if (state.fileUri != null) onDetectColumns()
                        },
                        modifier = Modifier.fillMaxWidth(),
                        enabled = state.fileUri != null && !state.isLoading,
                    ) {
                        if (state.isLoading) {
                            CircularProgressIndicator(modifier = Modifier.padding(end = 8.dp))
                        }
                        Text("Detect Columns")
                    }
                } else {
                    // API-key path: go straight to PROGRESS
                    Button(
                        onClick = onCommit,
                        modifier = Modifier.fillMaxWidth(),
                        enabled = state.selectedScopes.isNotEmpty() && !state.isLoading,
                    ) {
                        if (state.isLoading) {
                            CircularProgressIndicator(modifier = Modifier.padding(end = 8.dp))
                        }
                        Text("Start Import")
                    }
                }
            }

            // ── Step 5: Column mapping (CSV only) ─────────────────────────────
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

            // ── Step 6: Preview (CSV only) ────────────────────────────────────
            ImportStep.PREVIEW -> {
                Text(
                    "Preview — first ${state.preview.rows.size} rows",
                    style = MaterialTheme.typography.titleMedium,
                )
                ImportPreviewTable(preview = state.preview)
                Spacer(Modifier.height(8.dp))
                OutlinedButton(
                    onClick = onStartDryRun,
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

            // ── Progress ──────────────────────────────────────────────────────
            ImportStep.PROGRESS -> {
                ImportProgressContent(state = state)
            }

            // ── Done ──────────────────────────────────────────────────────────
            ImportStep.DONE -> {
                DoneState(
                    progress = state.progress,
                    onReset = onReset,
                )
            }

            // ── Error ─────────────────────────────────────────────────────────
            ImportStep.ERROR -> {
                EmptyStateIllustration(
                    emoji = "⚠️",
                    title = "Import failed",
                    subtitle = state.error ?: "An unexpected error occurred.",
                    primaryCta = "Start Over",
                    onPrimaryCta = onReset,
                )
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
        if (progress.total > 0) {
            LinearProgressIndicator(
                progress = { fraction },
                modifier = Modifier.fillMaxWidth(),
            )
        } else {
            // Indeterminate while waiting for first status poll
            LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
        }
        Text("${progress.imported} imported · ${progress.skipped} skipped · ${progress.errors} errors")
        if (progress.currentStep.isNotBlank()) {
            Text(
                text = "Currently importing: ${progress.currentStep}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Text(
            text = "You can leave this screen — a notification will appear when the import completes.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun DoneState(
    progress: ImportProgress,
    onReset: () -> Unit,
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(
            Icons.Default.CheckCircle,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
        )
        Text("Import complete", style = MaterialTheme.typography.titleMedium)
        Text(
            "${progress.imported} imported · ${progress.skipped} skipped · ${progress.errors} errors",
            style = MaterialTheme.typography.bodyMedium,
        )
        OutlinedButton(onClick = onReset, modifier = Modifier.fillMaxWidth()) {
            Text("Start New Import")
        }
    }
}

@Composable
private fun AccessDeniedState() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        EmptyStateIllustration(
            emoji = "🔒",
            title = "Admin access required",
            subtitle = "Only administrators can import data.",
            primaryCta = "Go Back",
            onPrimaryCta = {},
        )
    }
}

@Composable
private fun ServerUnsupportedState() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        EmptyStateIllustration(
            emoji = "🔌",
            title = "Import not available",
            subtitle = "This server does not have import endpoints configured.",
            primaryCta = "Go Back",
            onPrimaryCta = {},
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
