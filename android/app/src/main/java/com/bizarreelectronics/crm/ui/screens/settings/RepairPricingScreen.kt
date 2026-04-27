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
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Search
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
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.data.remote.dto.RepairServiceItem
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ConfirmDialog
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import java.text.NumberFormat
import java.util.Locale

/**
 * RepairPricingScreen — §44.2
 *
 * Settings sub-screen: searchable, category-filtered repair services catalog.
 *
 * Shows a LazyColumn of all services (name + category + default labor rate).
 * A search bar filters results via the server (`GET /repair-pricing/services?q=`).
 * [FilterChip]s below the search bar narrow by service category.
 *
 * "Add service" FAB opens [RepairServiceEditDialog] for POST.
 * Tapping a row opens the same dialog pre-filled for PUT.
 * Tapping the Delete icon triggers [ConfirmDialog] → DELETE.
 *
 * Labor rate is displayed formatted via [NumberFormat.getCurrencyInstance].
 *
 * Per-device-model overrides are stored on the server; this screen shows only
 * the service catalog with base labor rates. Model-specific price lookup is
 * available via [RepairPricingApi.pricingLookup] when creating a ticket.
 *
 * iOS parallel: same server endpoints; documented here for cross-platform reference.
 *
 * @param onBack Navigate back (pop the back stack).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RepairPricingScreen(
    onBack: () -> Unit,
    viewModel: RepairPricingViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    var editTarget by remember { mutableStateOf<RepairServiceItem?>(null) }
    var showAddDialog by remember { mutableStateOf(false) }
    val snackbar = remember { SnackbarHostState() }

    LaunchedEffect(state.deleteError) {
        state.deleteError?.let {
            snackbar.showSnackbar(it)
            viewModel.clearDeleteError()
        }
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = stringResource(R.string.screen_repair_pricing),
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
                        contentDescription = stringResource(R.string.cd_add_service),
                    )
                },
                text = { Text(stringResource(R.string.repair_pricing_add)) },
            )
        },
        snackbarHost = { SnackbarHost(snackbar) },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            // ── Search bar ─────────────────────────────────────────────────
            OutlinedTextField(
                value = state.searchQuery,
                onValueChange = { viewModel.search(it) },
                placeholder = { Text(stringResource(R.string.repair_pricing_search_hint)) },
                leadingIcon = {
                    Icon(
                        Icons.Default.Search,
                        contentDescription = stringResource(R.string.cd_search),
                    )
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            )

            // ── Category filter chips ──────────────────────────────────────
            if (state.availableCategories.isNotEmpty()) {
                LazyRow(
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 4.dp),
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
                            icon = Icons.Default.Build,
                            title = stringResource(R.string.error_offline),
                            subtitle = stringResource(R.string.repair_pricing_offline_subtitle),
                        )
                    }
                }

                state.error != null -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        ErrorState(
                            message = state.error ?: "Failed to load services",
                            onRetry = { viewModel.loadServices() },
                        )
                    }
                }

                state.services.isEmpty() -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        EmptyState(
                            icon = Icons.Default.Build,
                            title = stringResource(R.string.repair_pricing_empty_title),
                            subtitle = when {
                                state.searchQuery.isNotBlank() ->
                                    stringResource(R.string.repair_pricing_empty_search, state.searchQuery)
                                state.selectedCategory != null ->
                                    stringResource(R.string.repair_pricing_empty_filtered)
                                else ->
                                    stringResource(R.string.repair_pricing_empty_subtitle)
                            },
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
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        items(
                            items = state.services,
                            key = { it.id },
                        ) { service ->
                            RepairServiceCard(
                                service = service,
                                isDeleting = state.isDeleting && state.pendingDeleteId == service.id,
                                onClick = { editTarget = service },
                                onDeleteClick = { viewModel.requestDelete(service.id) },
                            )
                        }
                    }
                }
            }
        }

        // ── Delete confirm dialog ──────────────────────────────────────────
        state.pendingDeleteId?.let { deleteId ->
            val name = state.services.firstOrNull { it.id == deleteId }?.name ?: "this service"
            ConfirmDialog(
                title = stringResource(R.string.repair_pricing_delete_title),
                message = stringResource(R.string.repair_pricing_delete_message, name),
                confirmLabel = stringResource(R.string.action_delete),
                onConfirm = { viewModel.deleteService(deleteId) },
                onDismiss = { viewModel.cancelDelete() },
                isDestructive = true,
            )
        }

        // ── Add dialog ─────────────────────────────────────────────────────
        if (showAddDialog) {
            RepairServiceEditDialog(
                service = null,
                isSaving = state.isSaving,
                saveError = state.saveError,
                onSave = { name, category, laborPrice, description ->
                    viewModel.saveService(null, name, category, laborPrice, description)
                    showAddDialog = false
                },
                onDismiss = { showAddDialog = false },
            )
        }

        // ── Edit dialog ────────────────────────────────────────────────────
        editTarget?.let { service ->
            RepairServiceEditDialog(
                service = service,
                isSaving = state.isSaving,
                saveError = state.saveError,
                onSave = { name, category, laborPrice, description ->
                    viewModel.saveService(service.id, name, category, laborPrice, description)
                    editTarget = null
                },
                onDismiss = { editTarget = null },
            )
        }
    }
}

// ─── Private composables ──────────────────────────────────────────────────────

@Composable
private fun RepairServiceCard(
    service: RepairServiceItem,
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
                    text = service.name,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
            },
            supportingContent = {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    service.category?.let { cat ->
                        Text(
                            text = cat,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    if (service.laborPrice > 0.0) {
                        Text(
                            text = stringResource(
                                R.string.repair_pricing_labor_rate,
                                fmt.format(service.laborPrice),
                            ),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
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
                                R.string.repair_pricing_delete_cd,
                                service.name,
                            ),
                            tint = MaterialTheme.colorScheme.error,
                        )
                    }
                }
            },
        )
    }
}

/**
 * Dialog for adding or editing a repair service in the pricing catalog.
 *
 * @param service      Pre-fill for edit; null for create.
 * @param isSaving     Show loading indicator on save button while true.
 * @param saveError    Inline error text; null when none.
 * @param onSave       Callback with (name, category, laborPrice, description).
 * @param onDismiss    Close without saving.
 */
@Composable
fun RepairServiceEditDialog(
    service: RepairServiceItem?,
    isSaving: Boolean,
    saveError: String?,
    onSave: (name: String, category: String?, laborPrice: Double, description: String?) -> Unit,
    onDismiss: () -> Unit,
) {
    val fmt = remember { NumberFormat.getCurrencyInstance(Locale.US) }

    var name by remember(service) { mutableStateOf(service?.name ?: "") }
    var category by remember(service) { mutableStateOf(service?.category ?: "") }
    var description by remember(service) { mutableStateOf(service?.description ?: "") }
    var laborPriceText by remember(service) {
        mutableStateOf(
            if ((service?.laborPrice ?: 0.0) > 0.0) fmt.format(service!!.laborPrice) else "",
        )
    }

    val canSave = name.isNotBlank() && !isSaving

    AlertDialog(
        onDismissRequest = onDismiss,
        icon = {
            Icon(
                Icons.Default.Build,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
            )
        },
        title = {
            Text(
                if (service == null)
                    stringResource(R.string.repair_pricing_add_dialog_title)
                else
                    stringResource(R.string.repair_pricing_edit_dialog_title),
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
                    label = { Text(stringResource(R.string.repair_pricing_field_name)) },
                    placeholder = { Text(stringResource(R.string.repair_pricing_field_name_hint)) },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    isError = name.isBlank(),
                    supportingText = if (name.isBlank()) {
                        { Text(stringResource(R.string.error_field_required)) }
                    } else null,
                )
                OutlinedTextField(
                    value = category,
                    onValueChange = { category = it },
                    label = { Text(stringResource(R.string.repair_pricing_field_category)) },
                    placeholder = { Text(stringResource(R.string.repair_pricing_field_category_hint)) },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                )
                OutlinedTextField(
                    value = laborPriceText,
                    onValueChange = { laborPriceText = it },
                    label = { Text(stringResource(R.string.repair_pricing_field_labor_rate)) },
                    placeholder = { Text("0.00") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                )
                OutlinedTextField(
                    value = description,
                    onValueChange = { description = it },
                    label = { Text(stringResource(R.string.repair_pricing_field_description)) },
                    modifier = Modifier.fillMaxWidth(),
                    minLines = 2,
                    maxLines = 3,
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
                        val cleanedPrice = laborPriceText.replace(Regex("[^0-9.]"), "")
                        val price = cleanedPrice.toDoubleOrNull() ?: 0.0
                        onSave(
                            name.trim(),
                            category.trim().takeIf { it.isNotBlank() },
                            price,
                            description.trim().takeIf { it.isNotBlank() },
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
