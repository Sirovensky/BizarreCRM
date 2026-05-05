package com.bizarreelectronics.crm.ui.screens.exportdata

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
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.util.ZipEncryptor

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

    // §51.3 / §51.4 — SAF document-create launcher.
    // When ZIP password is enabled the MIME type switches to "application/zip"
    // so the file manager opens with a .zip extension.
    val safMimeType = if (state.zipPasswordEnabled && state.zipPassword.isNotBlank()) {
        "application/zip"
    } else {
        state.selectedFormat.mimeType
    }
    val saveLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument(safMimeType),
    ) { destUri: Uri? ->
        if (destUri != null) {
            viewModel.downloadTo(context, destUri)
        }
    }

    LaunchedEffect(state.toastMessage) {
        state.toastMessage?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearToast()
        }
    }

    // §51.3 — "Cancel export" ConfirmDialog (shown while poll is active)
    if (state.showCancelConfirm) {
        AlertDialog(
            onDismissRequest = viewModel::dismissCancelExport,
            title = { Text(stringResource(R.string.export_cancel_title)) },
            text = { Text(stringResource(R.string.export_cancel_message)) },
            confirmButton = {
                Button(
                    onClick = viewModel::confirmCancelExport,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.error,
                    ),
                ) {
                    Text(stringResource(R.string.export_cancel_confirm))
                }
            },
            dismissButton = {
                TextButton(onClick = viewModel::dismissCancelExport) {
                    Text(stringResource(R.string.action_keep_waiting))
                }
            },
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.screen_data_export)) },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.cd_navigate_back),
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
                !state.canExport -> ExportAccessDeniedState()
                state.serverUnsupported -> ExportUnsupportedState()
                state.isPollActive || state.jobStatus == ExportJobStatus.READY -> {
                    ExportProgressContent(
                        state = state,
                        onDownload = {
                            // §51.4 — use .zip name when encryption is on.
                            val ext = state.selectedFormat.apiValue
                            val rawName = "export_$ext.$ext"
                            val suggestedName = if (state.zipPasswordEnabled && state.zipPassword.isNotBlank()) {
                                ZipEncryptor.suggestZipName(rawName)
                            } else {
                                rawName
                            }
                            saveLauncher.launch(suggestedName)
                        },
                        onCancelExport = viewModel::promptCancelExport,
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
                    onSetZipPasswordEnabled = viewModel::setZipPasswordEnabled,
                    onSetZipPassword = viewModel::setZipPassword,
                    onToggleZipPasswordVisibility = viewModel::toggleZipPasswordVisibility,
                    onRequestExport = viewModel::requestExport,
                )
            }
        }
    }
}

// ── Configuration form ─────────────────────────────────────────────────────────

@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
private fun ExportConfigContent(
    state: DataExportUiState,
    onToggleEntity: (ExportEntity) -> Unit,
    onSetFormat: (ExportFormat) -> Unit,
    onSetDateFrom: (String) -> Unit,
    onSetDateTo: (String) -> Unit,
    onSetActiveOnly: (Boolean) -> Unit,
    onSetEmailOnReady: (Boolean) -> Unit,
    onSetZipPasswordEnabled: (Boolean) -> Unit,
    onSetZipPassword: (String) -> Unit,
    onToggleZipPasswordVisibility: () -> Unit,
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

        HorizontalDivider()

        // §51.4 — Optional AES-256 ZIP password protection
        SectionHeader(stringResource(R.string.export_zip_password_section))
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.weight(1f),
            ) {
                Icon(
                    imageVector = if (state.zipPasswordEnabled) Icons.Default.Lock else Icons.Default.LockOpen,
                    contentDescription = null,
                    tint = if (state.zipPasswordEnabled) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                )
                Text(
                    text = stringResource(R.string.export_zip_password_toggle),
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
            Switch(
                checked = state.zipPasswordEnabled,
                onCheckedChange = onSetZipPasswordEnabled,
            )
        }
        if (state.zipPasswordEnabled) {
            OutlinedTextField(
                value = state.zipPassword,
                onValueChange = onSetZipPassword,
                label = { Text(stringResource(R.string.export_zip_password_label)) },
                placeholder = { Text(stringResource(R.string.export_zip_password_placeholder)) },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                visualTransformation = if (state.zipPasswordVisible) {
                    VisualTransformation.None
                } else {
                    PasswordVisualTransformation()
                },
                trailingIcon = {
                    IconButton(onClick = onToggleZipPasswordVisibility) {
                        Icon(
                            imageVector = if (state.zipPasswordVisible) {
                                Icons.Default.VisibilityOff
                            } else {
                                Icons.Default.Visibility
                            },
                            contentDescription = stringResource(
                                if (state.zipPasswordVisible) {
                                    R.string.cd_hide_password
                                } else {
                                    R.string.cd_show_password
                                },
                            ),
                        )
                    }
                },
                isError = state.zipPasswordEnabled && state.zipPassword.isBlank(),
                supportingText = if (state.zipPasswordEnabled && state.zipPassword.isBlank()) {
                    { Text(stringResource(R.string.export_zip_password_required)) }
                } else {
                    null
                },
            )
        }

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
            enabled = !state.isLoading &&
                state.selectedEntities.isNotEmpty() &&
                // §51.4 — block submit if ZIP is toggled on but password is blank
                !(state.zipPasswordEnabled && state.zipPassword.isBlank()),
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
    onCancelExport: () -> Unit,
    onReset: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val isReady = state.jobStatus == ExportJobStatus.READY
    OutlinedCard(
        modifier = modifier
            .fillMaxSize()
            .padding(24.dp),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            if (isReady) {
                Icon(
                    Icons.Default.CheckCircle,
                    contentDescription = stringResource(R.string.cd_export_ready),
                    tint = MaterialTheme.colorScheme.primary,
                )
                Text(
                    stringResource(R.string.export_ready_label),
                    style = MaterialTheme.typography.titleMedium,
                )
                Button(
                    onClick = onDownload,
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !state.isDownloading,
                ) {
                    if (state.isDownloading) {
                        CircularProgressIndicator(
                            modifier = Modifier.padding(end = 8.dp),
                            strokeWidth = 2.dp,
                        )
                    } else {
                        Icon(
                            Icons.Default.Download,
                            contentDescription = null,
                            modifier = Modifier.padding(end = 8.dp),
                        )
                    }
                    Text(stringResource(R.string.export_action_download))
                }
            } else {
                LinearProgressIndicator(
                    progress = { state.progress / 100f },
                    modifier = Modifier.fillMaxWidth(),
                )
                Text(
                    text = stringResource(R.string.export_preparing, state.progress),
                    style = MaterialTheme.typography.bodyMedium,
                )
                Text(
                    text = stringResource(R.string.export_notify_hint),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )
                // §51 — cancel while polling
                FilledTonalButton(
                    onClick = onCancelExport,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Icon(
                        Icons.Default.Cancel,
                        contentDescription = null,
                        modifier = Modifier.padding(end = 8.dp),
                    )
                    Text(stringResource(R.string.export_action_cancel))
                }
            }
            state.error?.let { msg ->
                Row(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        Icons.Default.Error,
                        contentDescription = stringResource(R.string.cd_error_icon),
                        tint = MaterialTheme.colorScheme.error,
                    )
                    Text(msg, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                }
            }
            if (isReady || state.error != null) {
                OutlinedButton(onClick = onReset, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.export_action_new))
                }
            }
        }
    }
}

// ── Empty states ───────────────────────────────────────────────────────────────

@Composable
private fun ExportAccessDeniedState() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(
                Icons.Default.Error,
                contentDescription = stringResource(R.string.cd_error_icon),
                tint = MaterialTheme.colorScheme.error,
            )
            Spacer(Modifier.height(8.dp))
            Text(
                stringResource(R.string.export_access_denied),
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
            stringResource(R.string.export_unsupported),
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
