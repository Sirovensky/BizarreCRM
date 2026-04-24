package com.bizarreelectronics.crm.ui.screens.exportdata

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
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
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Error
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel

/**
 * §51 — Data Export Screen
 *
 * UI flow:
 *  1. Entity type multi-select (chips).
 *  2. Format picker (CSV / JSON / XLSX).
 *  3. Date range inputs (optional).
 *  4. Active-only toggle + email-on-ready toggle.
 *  5. "Request Export" → progress bar while polling.
 *  6. When ready → "Download" via SAF ACTION_CREATE_DOCUMENT.
 *
 * Role gate: manager+ only. Staff see "access denied" empty state.
 * 404-tolerant: server not configured → "not available" empty state.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DataExportScreen(
    onNavigateBack: () -> Unit,
    viewModel: DataExportViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val context = LocalContext.current

    // SAF document-create launcher for downloading the export archive
    val saveLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument(state.selectedFormat.mimeType),
    ) { destUri: Uri? ->
        if (destUri == null || state.downloadUrl == null) return@rememberLauncherForActivityResult
        // Trigger the system download manager or copy via stream
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(state.downloadUrl))
        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
        context.startActivity(intent)
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
                title = { Text("Data Export") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
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
                !state.canExport -> ExportAccessDeniedState()
                state.serverUnsupported -> ExportUnsupportedState()
                state.isPollActive || state.jobStatus == ExportJobStatus.READY -> {
                    ExportProgressContent(
                        state = state,
                        onDownload = {
                            val fileName = "export_${state.selectedFormat.apiValue}.${state.selectedFormat.apiValue}"
                            saveLauncher.launch(fileName)
                        },
                        onReset = viewModel::resetJob,
                    )
                }
                else -> ExportConfigContent(
                    state = state,
                    onToggleEntity = viewModel::toggleEntity,
                    onSetFormat = viewModel::setFormat,
                    onSetDateFrom = viewModel::setDateFrom,
                    onSetDateTo = viewModel::setDateTo,
                    onSetActiveOnly = viewModel::setActiveOnly,
                    onSetEmailOnReady = viewModel::setEmailOnReady,
                    onRequestExport = viewModel::requestExport,
                )
            }
        }
    }
}

// ── Configuration form ─────────────────────────────────────────────────────────

@Composable
private fun ExportConfigContent(
    state: DataExportUiState,
    onToggleEntity: (ExportEntity) -> Unit,
    onSetFormat: (ExportFormat) -> Unit,
    onSetDateFrom: (String) -> Unit,
    onSetDateTo: (String) -> Unit,
    onSetActiveOnly: (Boolean) -> Unit,
    onSetEmailOnReady: (Boolean) -> Unit,
    onRequestExport: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val scrollState = rememberScrollState()
    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(scrollState)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        // Entity type selector
        SectionHeader("Entity Types")
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ExportEntity.entries.forEach { entity ->
                FilterChip(
                    selected = entity in state.selectedEntities,
                    onClick = { onToggleEntity(entity) },
                    label = { Text(entity.label) },
                )
            }
        }

        HorizontalDivider()

        // Format selector
        SectionHeader("Format")
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ExportFormat.entries.forEach { fmt ->
                FilterChip(
                    selected = fmt == state.selectedFormat,
                    onClick = { onSetFormat(fmt) },
                    label = { Text(fmt.label) },
                )
            }
        }

        HorizontalDivider()

        // Date range
        SectionHeader("Date Range (optional)")
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(
                value = state.dateFrom,
                onValueChange = onSetDateFrom,
                label = { Text("From (YYYY-MM-DD)") },
                modifier = Modifier.weight(1f),
                singleLine = true,
                placeholder = { Text("e.g. 2025-01-01") },
            )
            OutlinedTextField(
                value = state.dateTo,
                onValueChange = onSetDateTo,
                label = { Text("To (YYYY-MM-DD)") },
                modifier = Modifier.weight(1f),
                singleLine = true,
                placeholder = { Text("e.g. 2025-12-31") },
            )
        }

        HorizontalDivider()

        // Toggles
        ToggleRow(
            label = "Active records only",
            checked = state.activeOnly,
            onCheckedChange = onSetActiveOnly,
        )
        ToggleRow(
            label = "Email archive to admin when ready",
            checked = state.emailOnReady,
            onCheckedChange = onSetEmailOnReady,
        )

        state.error?.let { msg ->
            Text(
                text = msg,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
            )
        }

        Spacer(Modifier.height(4.dp))

        Button(
            onClick = onRequestExport,
            modifier = Modifier.fillMaxWidth(),
            enabled = !state.isLoading && state.selectedEntities.isNotEmpty(),
        ) {
            if (state.isLoading) {
                CircularProgressIndicator(modifier = Modifier.padding(end = 8.dp))
            }
            Text("Request Export")
        }
    }
}

// ── Progress / download ────────────────────────────────────────────────────────

@Composable
private fun ExportProgressContent(
    state: DataExportUiState,
    onDownload: () -> Unit,
    onReset: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val isReady = state.jobStatus == ExportJobStatus.READY
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        if (isReady) {
            Icon(
                Icons.Default.CheckCircle,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
            )
            Text("Export ready!", style = MaterialTheme.typography.titleMedium)
            Button(onClick = onDownload, modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Default.Download, contentDescription = null)
                Text("Download", modifier = Modifier.padding(start = 8.dp))
            }
        } else {
            LinearProgressIndicator(
                progress = { state.progress / 100f },
                modifier = Modifier.fillMaxWidth(),
            )
            Text(
                text = "Preparing export… ${state.progress}%",
                style = MaterialTheme.typography.bodyMedium,
            )
            Text(
                text = "You can leave this screen — you'll be notified when ready.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
        state.error?.let { msg ->
            Row(
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Default.Error, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                Text(msg, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
            }
        }
        if (isReady || state.error != null) {
            OutlinedButton(onClick = onReset, modifier = Modifier.fillMaxWidth()) {
                Text("New Export")
            }
        }
    }
}

// ── Empty states ───────────────────────────────────────────────────────────────

@Composable
private fun ExportAccessDeniedState() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(Icons.Default.Error, contentDescription = null, tint = MaterialTheme.colorScheme.error)
            Spacer(Modifier.height(8.dp))
            Text(
                "Manager access required to export data.",
                style = MaterialTheme.typography.bodyMedium,
                textAlign = TextAlign.Center,
            )
        }
    }
}

@Composable
private fun ExportUnsupportedState() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text(
            "Export is not configured on this server.",
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

// ── Shared small composables ────────────────────────────────────────────────────

@Composable
private fun SectionHeader(text: String) {
    Text(text, style = MaterialTheme.typography.titleSmall)
}

@Composable
private fun ToggleRow(
    label: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}
