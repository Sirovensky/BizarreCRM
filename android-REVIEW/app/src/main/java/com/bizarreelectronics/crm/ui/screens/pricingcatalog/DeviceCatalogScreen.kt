package com.bizarreelectronics.crm.ui.screens.pricingcatalog

import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Devices
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FilterChip
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
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.remote.dto.DeviceModelItem
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState

private val CATEGORIES = listOf("phone", "tablet", "laptop", "tv", "other")

/**
 * DeviceCatalogScreen — §44.3
 *
 * Settings sub-screen: browse the device catalog with manufacturer + category
 * filter chips and free-text search. Admin users see an "Add device" FAB that
 * opens [AddDeviceDialog] for POST /catalog/devices.
 *
 * @param onBack       Navigate back.
 * @param isAdmin      Show "Add device" FAB when true.
 * @param onDeviceClick Optional click handler for device row (e.g. open template picker).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DeviceCatalogScreen(
    onBack: () -> Unit,
    isAdmin: Boolean = false,
    onDeviceClick: ((DeviceModelItem) -> Unit)? = null,
    viewModel: DeviceCatalogViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    var showAddDialog by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Device Catalog",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
        floatingActionButton = {
            if (isAdmin) {
                ExtendedFloatingActionButton(
                    onClick = { showAddDialog = true },
                    icon = { Icon(Icons.Default.Add, contentDescription = null) },
                    text = { Text("Add device") },
                )
            }
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
                onValueChange = { viewModel.onSearchQueryChanged(it) },
                placeholder = { Text("Search devices…") },
                leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                singleLine = true,
            )

            // Manufacturer filter chips
            if (state.manufacturers.isNotEmpty()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState())
                        .padding(horizontal = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    FilterChip(
                        selected = state.selectedManufacturerId == null,
                        onClick = { viewModel.onManufacturerSelected(null) },
                        label = { Text("All") },
                    )
                    state.manufacturers.forEach { mfr ->
                        FilterChip(
                            selected = state.selectedManufacturerId == mfr.id,
                            onClick = { viewModel.onManufacturerSelected(mfr.id) },
                            label = { Text(mfr.name) },
                        )
                    }
                }
            }

            // Category filter chips
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState())
                    .padding(horizontal = 12.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                FilterChip(
                    selected = state.selectedCategory == null,
                    onClick = { viewModel.onCategorySelected(null) },
                    label = { Text("All types") },
                )
                CATEGORIES.forEach { cat ->
                    FilterChip(
                        selected = state.selectedCategory == cat,
                        onClick = { viewModel.onCategorySelected(cat) },
                        label = { Text(cat.replaceFirstChar { it.uppercase() }) },
                    )
                }
            }

            when {
                state.isLoading || state.isLoadingDevices -> {
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
                            icon = Icons.Default.Devices,
                            title = "Offline",
                            subtitle = "Device catalog requires a server connection.",
                        )
                    }
                }

                state.error != null -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        ErrorState(
                            message = state.error ?: "Failed to load catalog",
                            onRetry = { viewModel.loadManufacturers() },
                        )
                    }
                }

                state.devices.isEmpty() -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        EmptyState(
                            icon = Icons.Default.Devices,
                            title = "No devices",
                            subtitle = if (state.searchQuery.isNotBlank())
                                "No results for \"${state.searchQuery}\""
                            else "No devices match the selected filters.",
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
                            bottom = 80.dp,
                        ),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        items(
                            items = state.devices,
                            key = { it.id },
                        ) { device ->
                            DeviceModelCard(
                                device = device,
                                onClick = { onDeviceClick?.invoke(device) },
                            )
                        }
                    }
                }
            }
        }

        if (showAddDialog) {
            AddDeviceDialog(
                manufacturers = state.manufacturers,
                isSaving = state.isSaving,
                saveError = state.saveError,
                onSave = { manufacturerId, name, category, releaseYear ->
                    viewModel.addDevice(manufacturerId, name, category, releaseYear)
                    showAddDialog = false
                },
                onDismiss = { showAddDialog = false },
            )
        }
    }
}

// ─── Private composables ──────────────────────────────────────────────────────

@Composable
private fun DeviceModelCard(
    device: DeviceModelItem,
    onClick: () -> Unit,
) {
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Text(
                text = device.name,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )
            val subtitle = listOfNotNull(
                device.manufacturerName,
                device.category?.replaceFirstChar { it.uppercase() },
                device.releaseYear?.toString(),
            ).joinToString(" · ")
            if (subtitle.isNotBlank()) {
                Text(
                    text = subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

/**
 * Dialog for adding a new device model to the catalog (admin only).
 *
 * @param manufacturers  Manufacturer list for dropdown.
 * @param isSaving       Show loading indicator while true.
 * @param saveError      Inline error message; null when none.
 * @param onSave         Callback with (manufacturerId, name, category, releaseYear).
 * @param onDismiss      Close without saving.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddDeviceDialog(
    manufacturers: List<com.bizarreelectronics.crm.data.remote.dto.ManufacturerItem>,
    isSaving: Boolean,
    saveError: String?,
    onSave: (manufacturerId: Long, name: String, category: String, releaseYear: Int?) -> Unit,
    onDismiss: () -> Unit,
) {
    var name by remember { mutableStateOf("") }
    var releaseYearText by remember { mutableStateOf("") }
    var selectedManufacturer by remember { mutableStateOf(manufacturers.firstOrNull()) }
    var selectedCategory by remember { mutableStateOf("phone") }
    var manufacturerExpanded by remember { mutableStateOf(false) }
    var categoryExpanded by remember { mutableStateOf(false) }

    val canSave = name.isNotBlank() && selectedManufacturer != null && !isSaving

    AlertDialog(
        onDismissRequest = onDismiss,
        icon = {
            Icon(
                Icons.Default.Devices,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
            )
        },
        title = { Text("Add device") },
        text = {
            Column(modifier = Modifier.fillMaxWidth()) {
                // Manufacturer dropdown
                ExposedDropdownMenuBox(
                    expanded = manufacturerExpanded,
                    onExpandedChange = { manufacturerExpanded = it },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    OutlinedTextField(
                        value = selectedManufacturer?.name ?: "",
                        onValueChange = {},
                        readOnly = true,
                        label = { Text("Manufacturer *") },
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = manufacturerExpanded) },
                        modifier = Modifier
                            .fillMaxWidth()
                            .menuAnchor(),
                    )
                    ExposedDropdownMenu(
                        expanded = manufacturerExpanded,
                        onDismissRequest = { manufacturerExpanded = false },
                    ) {
                        manufacturers.forEach { mfr ->
                            DropdownMenuItem(
                                text = { Text(mfr.name) },
                                onClick = {
                                    selectedManufacturer = mfr
                                    manufacturerExpanded = false
                                },
                            )
                        }
                    }
                }

                Spacer(modifier = Modifier.height(10.dp))

                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("Device name *") },
                    placeholder = { Text("e.g. iPhone 15 Pro") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    isError = name.isBlank(),
                    supportingText = if (name.isBlank()) {
                        { Text("Name is required") }
                    } else null,
                )

                Spacer(modifier = Modifier.height(10.dp))

                // Category dropdown
                ExposedDropdownMenuBox(
                    expanded = categoryExpanded,
                    onExpandedChange = { categoryExpanded = it },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    OutlinedTextField(
                        value = selectedCategory.replaceFirstChar { it.uppercase() },
                        onValueChange = {},
                        readOnly = true,
                        label = { Text("Category") },
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = categoryExpanded) },
                        modifier = Modifier
                            .fillMaxWidth()
                            .menuAnchor(),
                    )
                    ExposedDropdownMenu(
                        expanded = categoryExpanded,
                        onDismissRequest = { categoryExpanded = false },
                    ) {
                        CATEGORIES.forEach { cat ->
                            DropdownMenuItem(
                                text = { Text(cat.replaceFirstChar { it.uppercase() }) },
                                onClick = {
                                    selectedCategory = cat
                                    categoryExpanded = false
                                },
                            )
                        }
                    }
                }

                Spacer(modifier = Modifier.height(10.dp))

                OutlinedTextField(
                    value = releaseYearText,
                    onValueChange = { releaseYearText = it },
                    label = { Text("Release year (optional)") },
                    placeholder = { Text("e.g. 2024") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
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
                        val mfr = selectedManufacturer ?: return@TextButton
                        val year = releaseYearText.toIntOrNull()
                        onSave(mfr.id, name.trim(), selectedCategory, year)
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
