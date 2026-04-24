package com.bizarreelectronics.crm.ui.screens.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.remote.api.DeviceTemplateDto
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState

/**
 * DeviceTemplatesScreen — §4.9 L762
 *
 * Settings sub-screen: searchable list of device templates (GET /device-templates).
 * Each template has a device model binding + a list of common repair names used to
 * pre-fill suggestions in the TicketCreate Device step and the Bench tab.
 *
 * "Add template" FAB opens [DeviceTemplateEditDialog] for POST. Tapping a row
 * opens the same dialog pre-filled for PUT.
 *
 * iOS parallel: same server endpoints; documented here for cross-platform reference.
 *
 * @param onBack Navigate back (pop the back stack).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DeviceTemplatesScreen(
    onBack: () -> Unit,
    viewModel: DeviceTemplatesViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    var editTarget by remember { mutableStateOf<DeviceTemplateDto?>(null) }
    var showAddDialog by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Device Templates",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = { showAddDialog = true },
                icon = { Icon(Icons.Default.Add, contentDescription = null) },
                text = { Text("Add template") },
            )
        },
    ) { padding ->
        when {
            state.isLoading -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            }

            state.offline -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    EmptyState(
                        icon = Icons.Default.PhoneAndroid,
                        title = "Offline",
                        subtitle = "Device templates require a server connection.",
                    )
                }
            }

            state.error != null -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    ErrorState(
                        message = state.error ?: "Failed to load templates",
                        onRetry = { viewModel.loadTemplates() },
                    )
                }
            }

            state.templates.isEmpty() -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    EmptyState(
                        icon = Icons.Default.PhoneAndroid,
                        title = "No device templates",
                        subtitle = "Tap \"+Add template\" to create your first device template.",
                    )
                }
            }

            else -> {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentPadding = PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    items(
                        items = state.templates,
                        key = { it.id },
                    ) { template ->
                        DeviceTemplateCard(
                            template = template,
                            onClick = { editTarget = template },
                        )
                    }
                }
            }
        }

        // Add dialog
        if (showAddDialog) {
            DeviceTemplateEditDialog(
                template = null,
                isSaving = state.isSaving,
                saveError = state.saveError,
                onSave = { name, deviceModelId, commonRepairs ->
                    viewModel.saveTemplate(null, name, deviceModelId, commonRepairs)
                    showAddDialog = false
                },
                onDismiss = { showAddDialog = false },
            )
        }

        // Edit dialog
        editTarget?.let { template ->
            DeviceTemplateEditDialog(
                template = template,
                isSaving = state.isSaving,
                saveError = state.saveError,
                onSave = { name, deviceModelId, commonRepairs ->
                    viewModel.saveTemplate(template.id, name, deviceModelId, commonRepairs)
                    editTarget = null
                },
                onDismiss = { editTarget = null },
            )
        }
    }
}

// ─── Private composables ──────────────────────────────────────────────────────

@Composable
private fun DeviceTemplateCard(
    template: DeviceTemplateDto,
    onClick: () -> Unit,
) {
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = template.name,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )
            template.deviceModelName?.let { model ->
                Text(
                    text = model,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (template.commonRepairs.isNotEmpty()) {
                Spacer(modifier = Modifier.height(6.dp))
                Text(
                    text = "Common repairs: ${template.commonRepairs.joinToString(", ")}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                )
            }
        }
    }
}

/**
 * Dialog for creating or editing a device template.
 *
 * @param template     Pre-fill from existing template for edit; null for create.
 * @param isSaving     Show loading indicator on save button while true.
 * @param saveError    Inline error text shown below the form; null when none.
 * @param onSave       Callback with (name, deviceModelId, commonRepairs).
 * @param onDismiss    Close without saving.
 */
@Composable
fun DeviceTemplateEditDialog(
    template: DeviceTemplateDto?,
    isSaving: Boolean,
    saveError: String?,
    onSave: (name: String, deviceModelId: Long?, commonRepairs: List<String>) -> Unit,
    onDismiss: () -> Unit,
) {
    var name by remember(template) { mutableStateOf(template?.name ?: "") }
    var repairsText by remember(template) {
        mutableStateOf(template?.commonRepairs?.joinToString(", ") ?: "")
    }

    val canSave = name.isNotBlank() && !isSaving

    AlertDialog(
        onDismissRequest = onDismiss,
        icon = {
            Icon(Icons.Default.PhoneAndroid, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
        },
        title = { Text(if (template == null) "Add device template" else "Edit template") },
        text = {
            Column(modifier = Modifier.fillMaxWidth()) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("Template name *") },
                    placeholder = { Text("e.g. iPhone 14 screen repair") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    isError = name.isBlank(),
                    supportingText = if (name.isBlank()) {
                        { Text("Name is required") }
                    } else null,
                )
                Spacer(modifier = Modifier.height(12.dp))
                OutlinedTextField(
                    value = repairsText,
                    onValueChange = { repairsText = it },
                    label = { Text("Common repairs (comma-separated)") },
                    placeholder = { Text("e.g. Screen replacement, Battery swap") },
                    modifier = Modifier.fillMaxWidth(),
                    minLines = 2,
                    maxLines = 4,
                )
                if (saveError != null) {
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = saveError,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            }
        },
        confirmButton = {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (isSaving) CircularProgressIndicator()
                TextButton(
                    onClick = {
                        val repairs = repairsText.split(",")
                            .map { it.trim() }
                            .filter { it.isNotBlank() }
                        onSave(name.trim(), template?.deviceModelId, repairs)
                    },
                    enabled = canSave,
                ) {
                    Text("Save")
                }
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        },
    )
}
