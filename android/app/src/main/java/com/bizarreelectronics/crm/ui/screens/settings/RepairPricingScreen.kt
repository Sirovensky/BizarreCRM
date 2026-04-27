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
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Search
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
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.remote.dto.RepairServiceItem
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState

/**
 * RepairPricingScreen — §4.9 L766
 *
 * Settings sub-screen: searchable repair services catalog.
 *
 * Shows a LazyColumn of all services (name + default labor rate). A search bar
 * at the top filters results via the server (`GET /repair-pricing/services?q=`).
 *
 * "Add service" FAB opens [RepairServiceEditDialog] for POST. Tapping a row
 * opens the same dialog pre-filled for PUT.
 *
 * Per-device-model overrides are stored on the server; this screen shows only the
 * service catalog with base labor rates. Model-specific price lookup is available
 * via [RepairPricingApi.pricingLookup] when creating a ticket.
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

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Repair Pricing",
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
                text = { Text("Add service") },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            // Search bar
            OutlinedTextField(
                value = state.searchQuery,
                onValueChange = { viewModel.search(it) },
                placeholder = { Text("Search services…") },
                leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            )

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
                            title = "Offline",
                            subtitle = "Repair pricing requires a server connection.",
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
                            title = "No services",
                            subtitle = if (state.searchQuery.isNotBlank())
                                "No results for \"${state.searchQuery}\""
                            else "Tap \"+Add service\" to create your first pricing entry.",
                        )
                    }
                }

                else -> {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 80.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        items(
                            items = state.services,
                            key = { it.id },
                        ) { service ->
                            RepairServiceCard(
                                service = service,
                                onClick = { editTarget = service },
                            )
                        }
                    }
                }
            }
        }

        // Add dialog
        if (showAddDialog) {
            RepairServiceEditDialog(
                service = null,
                isSaving = state.isSaving,
                saveError = state.saveError,
                onSave = { name, category, laborPrice ->
                    viewModel.saveService(null, name, category, laborPrice)
                    showAddDialog = false
                },
                onDismiss = { showAddDialog = false },
            )
        }

        // Edit dialog
        editTarget?.let { service ->
            RepairServiceEditDialog(
                service = service,
                isSaving = state.isSaving,
                saveError = state.saveError,
                onSave = { name, category, laborPrice ->
                    viewModel.saveService(service.id, name, category, laborPrice)
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
    onClick: () -> Unit,
) {
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = service.name,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                service.category?.let { cat ->
                    Text(
                        text = cat,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            // Labor rate shown on the right
            if (service.laborPrice > 0) {
                Text(
                    text = "$%.2f".format(service.laborPrice),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
        }
    }
}

/**
 * Dialog for adding or editing a repair service in the pricing catalog.
 *
 * @param service      Pre-fill for edit; null for create.
 * @param isSaving     Show loading indicator on save button while true.
 * @param saveError    Inline error text; null when none.
 * @param onSave       Callback with (name, category, laborPrice).
 * @param onDismiss    Close without saving.
 */
@Composable
fun RepairServiceEditDialog(
    service: RepairServiceItem?,
    isSaving: Boolean,
    saveError: String?,
    onSave: (name: String, category: String?, laborPrice: Double) -> Unit,
    onDismiss: () -> Unit,
) {
    var name by remember(service) { mutableStateOf(service?.name ?: "") }
    var category by remember(service) { mutableStateOf(service?.category ?: "") }
    var laborPriceText by remember(service) {
        mutableStateOf(if (service != null && service.laborPrice > 0) "%.2f".format(service.laborPrice) else "")
    }

    val canSave = name.isNotBlank() && !isSaving

    AlertDialog(
        onDismissRequest = onDismiss,
        icon = {
            Icon(Icons.Default.Build, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
        },
        title = { Text(if (service == null) "Add service" else "Edit service") },
        text = {
            Column(modifier = Modifier.fillMaxWidth()) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("Service name *") },
                    placeholder = { Text("e.g. Screen replacement") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    isError = name.isBlank(),
                    supportingText = if (name.isBlank()) {
                        { Text("Name is required") }
                    } else null,
                )
                Spacer(modifier = Modifier.height(10.dp))
                OutlinedTextField(
                    value = category,
                    onValueChange = { category = it },
                    label = { Text("Category (optional)") },
                    placeholder = { Text("e.g. Screen, Battery") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                )
                Spacer(modifier = Modifier.height(10.dp))
                OutlinedTextField(
                    value = laborPriceText,
                    onValueChange = { laborPriceText = it },
                    label = { Text("Default labor rate") },
                    placeholder = { Text("0.00") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
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
                        val price = laborPriceText.toDoubleOrNull() ?: 0.0
                        onSave(
                            name.trim(),
                            category.trim().takeIf { it.isNotBlank() },
                            price,
                        )
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
