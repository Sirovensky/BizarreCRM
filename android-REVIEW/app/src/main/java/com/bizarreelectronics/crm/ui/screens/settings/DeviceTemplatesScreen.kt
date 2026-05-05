package com.bizarreelectronics.crm.ui.screens.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.data.remote.api.DeviceTemplateDto
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ConfirmDialog
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import java.text.NumberFormat
import java.util.Locale

/**
 * DeviceTemplatesScreen — §44.1
 *
 * Settings sub-screen: searchable, category-filtered list of device templates
 * (GET /device-templates). Each template captures:
 *  - device category + model + fault
 *  - estimated labor time + labor cost (stored as cents) + suggested price
 *  - diagnostic pre-conditions checklist
 *  - parts list with inventory stock badges
 *
 * "Add template" FAB opens [DeviceTemplateEditDialog] for POST.
 * Tapping a row opens the same dialog pre-filled for PUT.
 * Long-pressing a row (or tapping the Delete icon) triggers [ConfirmDialog]
 * which calls DELETE via the ViewModel.
 *
 * Category [FilterChip]s across the top narrow the server-side query.
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
    val snackbar = remember { SnackbarHostState() }

    // Show delete errors in snackbar
    LaunchedEffect(state.deleteError) {
        state.deleteError?.let {
            snackbar.showSnackbar(it)
            viewModel.clearDeleteError()
        }
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = stringResource(R.string.screen_device_templates),
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.cd_navigate_back),
                        )
                    }
                },
            )
        },
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = { showAddDialog = true },
                icon = {
                    Icon(
                        Icons.Default.Add,
                        contentDescription = stringResource(R.string.cd_add_template),
                    )
                },
                text = { Text(stringResource(R.string.device_templates_add)) },
            )
        },
        snackbarHost = { SnackbarHost(snackbar) },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            // ── Category filter chips ──────────────────────────────────────
            if (state.availableCategories.isNotEmpty()) {
                LazyRow(
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    item {
                        FilterChip(
                            selected = state.selectedCategory == null,
                            onClick = { viewModel.selectCategory(null) },
                            label = { Text(stringResource(R.string.filter_all)) },
                        )
                    }
                    items(state.availableCategories) { cat ->
                        FilterChip(
                            selected = state.selectedCategory == cat,
                            onClick = {
                                viewModel.selectCategory(
                                    if (state.selectedCategory == cat) null else cat,
                                )
                            },
                            label = { Text(cat) },
                        )
                    }
                }
            }

            when {
                state.isLoading -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator()
                    }
                }

                state.offline -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        EmptyState(
                            icon = Icons.Default.PhoneAndroid,
                            title = stringResource(R.string.error_offline),
                            subtitle = stringResource(R.string.device_templates_offline_subtitle),
                        )
                    }
                }

                state.error != null -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
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
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        EmptyState(
                            icon = Icons.Default.PhoneAndroid,
                            title = stringResource(R.string.device_templates_empty_title),
                            subtitle = if (state.selectedCategory != null)
                                stringResource(R.string.device_templates_empty_filtered)
                            else
                                stringResource(R.string.device_templates_empty_subtitle),
                        )
                    }
                }

                else -> {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(
                            start = 16.dp,
                            end = 16.dp,
                            top = 4.dp,
                            bottom = 88.dp,
                        ),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        items(
                            items = state.templates,
                            key = { it.id },
                        ) { template ->
                            DeviceTemplateCard(
                                template = template,
                                isDeleting = state.isDeleting && state.pendingDeleteId == template.id,
                                onClick = { editTarget = template },
                                onDeleteClick = { viewModel.requestDelete(template.id) },
                            )
                        }
                    }
                }
            }
        }

        // ── Delete confirm dialog ──────────────────────────────────────────
        state.pendingDeleteId?.let { deleteId ->
            val name = state.templates.firstOrNull { it.id == deleteId }?.name ?: "this template"
            ConfirmDialog(
                title = stringResource(R.string.device_templates_delete_title),
                message = stringResource(R.string.device_templates_delete_message, name),
                confirmLabel = stringResource(R.string.action_delete),
                onConfirm = { viewModel.deleteTemplate(deleteId) },
                onDismiss = { viewModel.cancelDelete() },
                isDestructive = true,
            )
        }

        // ── Add dialog ─────────────────────────────────────────────────────
        if (showAddDialog) {
            DeviceTemplateEditDialog(
                template = null,
                isSaving = state.isSaving,
                saveError = state.saveError,
                onSave = { req ->
                    viewModel.saveTemplate(
                        id = null,
                        name = req.name,
                        deviceCategory = req.deviceCategory,
                        deviceModel = req.deviceModel,
                        fault = req.fault,
                        estLaborMinutes = req.estLaborMinutes,
                        estLaborCostCents = req.estLaborCost,
                        suggestedPriceCents = req.suggestedPrice,
                        diagnosticChecklist = req.diagnosticChecklist,
                        warrantyDays = req.warrantyDays,
                    )
                    showAddDialog = false
                },
                onDismiss = { showAddDialog = false },
            )
        }

        // ── Edit dialog ────────────────────────────────────────────────────
        editTarget?.let { template ->
            DeviceTemplateEditDialog(
                template = template,
                isSaving = state.isSaving,
                saveError = state.saveError,
                onSave = { req ->
                    viewModel.saveTemplate(
                        id = template.id,
                        name = req.name,
                        deviceCategory = req.deviceCategory,
                        deviceModel = req.deviceModel,
                        fault = req.fault,
                        estLaborMinutes = req.estLaborMinutes,
                        estLaborCostCents = req.estLaborCost,
                        suggestedPriceCents = req.suggestedPrice,
                        diagnosticChecklist = req.diagnosticChecklist,
                        warrantyDays = req.warrantyDays,
                    )
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
    isDeleting: Boolean,
    onClick: () -> Unit,
    onDeleteClick: () -> Unit,
) {
    val fmt = remember { NumberFormat.getCurrencyInstance(Locale.US) }

    OutlinedCard(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
    ) {
        ListItem(
            headlineContent = {
                Text(
                    text = template.name,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
            },
            supportingContent = {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    val subParts = buildList {
                        template.deviceCategory?.let { add(it) }
                        template.deviceModel?.let { add(it) }
                        template.fault?.let { add(it) }
                    }
                    if (subParts.isNotEmpty()) {
                        Text(
                            text = subParts.joinToString(" · "),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    if (template.estLaborCostCents > 0 || template.suggestedPriceCents > 0) {
                        val laborStr = if (template.estLaborCostCents > 0)
                            "Labor: ${fmt.format(template.estLaborCostCents / 100.0)}"
                        else null
                        val priceStr = if (template.suggestedPriceCents > 0)
                            "Price: ${fmt.format(template.suggestedPriceCents / 100.0)}"
                        else null
                        listOfNotNull(laborStr, priceStr).joinToString("  ·  ").takeIf { it.isNotBlank() }?.let {
                            Text(
                                text = it,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                    if (template.diagnosticChecklist.isNotEmpty()) {
                        Text(
                            text = "${template.diagnosticChecklist.size} checklist item" +
                                if (template.diagnosticChecklist.size == 1) "" else "s",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    if (template.parts.isNotEmpty()) {
                        Text(
                            text = "${template.parts.size} part" +
                                if (template.parts.size == 1) "" else "s",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    // Legacy common_repairs (pre-§44.1 server)
                    if (template.commonRepairs.isNotEmpty() && template.parts.isEmpty()) {
                        Text(
                            text = "Repairs: ${template.commonRepairs.joinToString(", ")}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 2,
                        )
                    }
                }
            },
            trailingContent = {
                if (isDeleting) {
                    CircularProgressIndicator()
                } else {
                    IconButton(onClick = onDeleteClick) {
                        Icon(
                            Icons.Default.Delete,
                            contentDescription = stringResource(
                                R.string.device_templates_delete_cd,
                                template.name,
                            ),
                            tint = MaterialTheme.colorScheme.error,
                        )
                    }
                }
            },
        )
    }
}

// ─── Edit / create dialog ─────────────────────────────────────────────────────

/**
 * Internal data class carrying form fields out of [DeviceTemplateEditDialog].
 * Money fields are in cents (Long) per project convention.
 */
data class DeviceTemplateFormResult(
    val name: String,
    val deviceCategory: String?,
    val deviceModel: String?,
    val fault: String?,
    val estLaborMinutes: Int,
    /** Cents */
    val estLaborCost: Long,
    /** Cents */
    val suggestedPrice: Long,
    val diagnosticChecklist: List<String>,
    val warrantyDays: Int,
)

/**
 * Dialog for creating or editing a device template.
 *
 * @param template     Pre-fill from existing template for edit; null for create.
 * @param isSaving     Show loading indicator on save button while true.
 * @param saveError    Inline error text shown below the form; null when none.
 * @param onSave       Callback with [DeviceTemplateFormResult].
 * @param onDismiss    Close without saving.
 */
@Composable
fun DeviceTemplateEditDialog(
    template: DeviceTemplateDto?,
    isSaving: Boolean,
    saveError: String?,
    onSave: (DeviceTemplateFormResult) -> Unit,
    onDismiss: () -> Unit,
) {
    val fmt = remember { NumberFormat.getCurrencyInstance(Locale.US) }

    var name by remember(template) { mutableStateOf(template?.name ?: "") }
    var deviceCategory by remember(template) { mutableStateOf(template?.deviceCategory ?: "") }
    var deviceModel by remember(template) { mutableStateOf(template?.deviceModel ?: "") }
    var fault by remember(template) { mutableStateOf(template?.fault ?: "") }
    var estLaborMinutesText by remember(template) {
        mutableStateOf(
            if ((template?.estLaborMinutes ?: 0) > 0) template!!.estLaborMinutes.toString() else ""
        )
    }
    var estLaborCostText by remember(template) {
        mutableStateOf(
            if ((template?.estLaborCostCents ?: 0L) > 0L)
                fmt.format(template!!.estLaborCostCents / 100.0)
            else ""
        )
    }
    var suggestedPriceText by remember(template) {
        mutableStateOf(
            if ((template?.suggestedPriceCents ?: 0L) > 0L)
                fmt.format(template!!.suggestedPriceCents / 100.0)
            else ""
        )
    }
    var checklistText by remember(template) {
        mutableStateOf(template?.diagnosticChecklist?.joinToString("\n") ?: "")
    }
    var warrantyDaysText by remember(template) {
        mutableStateOf((template?.warrantyDays ?: 30).toString())
    }

    val canSave = name.isNotBlank() && !isSaving

    AlertDialog(
        onDismissRequest = onDismiss,
        icon = {
            Icon(
                Icons.Default.PhoneAndroid,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
            )
        },
        title = {
            Text(
                if (template == null)
                    stringResource(R.string.device_templates_add_dialog_title)
                else
                    stringResource(R.string.device_templates_edit_dialog_title),
            )
        },
        text = {
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text(stringResource(R.string.device_templates_field_name)) },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    isError = name.isBlank(),
                    supportingText = if (name.isBlank()) {
                        { Text(stringResource(R.string.error_field_required)) }
                    } else null,
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    OutlinedTextField(
                        value = deviceCategory,
                        onValueChange = { deviceCategory = it },
                        label = { Text(stringResource(R.string.device_templates_field_category)) },
                        modifier = Modifier.weight(1f),
                        singleLine = true,
                    )
                    OutlinedTextField(
                        value = deviceModel,
                        onValueChange = { deviceModel = it },
                        label = { Text(stringResource(R.string.device_templates_field_model)) },
                        modifier = Modifier.weight(1f),
                        singleLine = true,
                    )
                }
                OutlinedTextField(
                    value = fault,
                    onValueChange = { fault = it },
                    label = { Text(stringResource(R.string.device_templates_field_fault)) },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    OutlinedTextField(
                        value = estLaborCostText,
                        onValueChange = { estLaborCostText = it },
                        label = { Text(stringResource(R.string.device_templates_field_labor_cost)) },
                        placeholder = { Text("0.00") },
                        modifier = Modifier.weight(1f),
                        singleLine = true,
                    )
                    OutlinedTextField(
                        value = suggestedPriceText,
                        onValueChange = { suggestedPriceText = it },
                        label = { Text(stringResource(R.string.device_templates_field_suggested_price)) },
                        placeholder = { Text("0.00") },
                        modifier = Modifier.weight(1f),
                        singleLine = true,
                    )
                }
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    OutlinedTextField(
                        value = estLaborMinutesText,
                        onValueChange = { estLaborMinutesText = it },
                        label = { Text(stringResource(R.string.device_templates_field_labor_minutes)) },
                        placeholder = { Text("60") },
                        modifier = Modifier.weight(1f),
                        singleLine = true,
                    )
                    OutlinedTextField(
                        value = warrantyDaysText,
                        onValueChange = { warrantyDaysText = it },
                        label = { Text(stringResource(R.string.device_templates_field_warranty_days)) },
                        placeholder = { Text("30") },
                        modifier = Modifier.weight(1f),
                        singleLine = true,
                    )
                }
                OutlinedTextField(
                    value = checklistText,
                    onValueChange = { checklistText = it },
                    label = { Text(stringResource(R.string.device_templates_field_checklist)) },
                    placeholder = { Text(stringResource(R.string.device_templates_field_checklist_hint)) },
                    modifier = Modifier.fillMaxWidth(),
                    minLines = 2,
                    maxLines = 5,
                )
                if (saveError != null) {
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
                FilledTonalButton(
                    onClick = {
                        // Parse money fields: strip currency symbols, parse as Double, convert to cents
                        fun parseCents(raw: String): Long {
                            val cleaned = raw.replace(Regex("[^0-9.]"), "")
                            return ((cleaned.toDoubleOrNull() ?: 0.0) * 100).toLong()
                        }
                        val checklist = checklistText.lines()
                            .map { it.trim() }
                            .filter { it.isNotBlank() }
                        onSave(
                            DeviceTemplateFormResult(
                                name = name.trim(),
                                deviceCategory = deviceCategory.trim().takeIf { it.isNotBlank() },
                                deviceModel = deviceModel.trim().takeIf { it.isNotBlank() },
                                fault = fault.trim().takeIf { it.isNotBlank() },
                                estLaborMinutes = estLaborMinutesText.trim().toIntOrNull() ?: 0,
                                estLaborCost = parseCents(estLaborCostText),
                                suggestedPrice = parseCents(suggestedPriceText),
                                diagnosticChecklist = checklist,
                                warrantyDays = warrantyDaysText.trim().toIntOrNull() ?: 30,
                            ),
                        )
                    },
                    enabled = canSave,
                ) {
                    Text(stringResource(R.string.action_save))
                }
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.action_cancel))
            }
        },
    )
}
