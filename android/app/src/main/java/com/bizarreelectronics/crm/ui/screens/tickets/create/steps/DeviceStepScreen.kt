package com.bizarreelectronics.crm.ui.screens.tickets.create.steps

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.dto.DeviceModelItem
import com.bizarreelectronics.crm.data.remote.dto.ManufacturerItem

/**
 * Step 2 — Device selection.
 *
 * Provides:
 * - Manufacturer filter chips (from `GET /catalog/manufacturers`).
 * - Model search `GET /catalog/devices?keyword=&manufacturer=` debounced 300ms.
 * - Popular device chips as quick-add tiles.
 * - "Other / custom" text field for unlisted devices.
 * - "Add more" button to support multiple devices per ticket.
 *
 * Validation: Next enabled when `selectedDevice != null || customDeviceName.isNotBlank()`.
 */
@Composable
fun DeviceStepScreen(
    category: String,
    manufacturers: List<ManufacturerItem>,
    selectedManufacturerId: Long?,
    searchQuery: String,
    searchResults: List<DeviceModelItem>,
    popularDevices: List<DeviceModelItem>,
    isLoading: Boolean,
    customDeviceName: String,
    selectedDevice: DeviceModelItem?,
    onManufacturerSelect: (Long?) -> Unit,
    onSearchChange: (String) -> Unit,
    onDeviceSelect: (DeviceModelItem) -> Unit,
    onCustomNameChange: (String) -> Unit,
    onCustomDeviceConfirm: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val focusManager = LocalFocusManager.current

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        // ── Manufacturer filter row ─────────────────────────────────────
        if (manufacturers.isNotEmpty()) {
            item(key = "mfg_chips") {
                ManufacturerFilterRow(
                    manufacturers = manufacturers,
                    selectedId = selectedManufacturerId,
                    onSelect = onManufacturerSelect,
                )
            }
        }

        // ── Search field ────────────────────────────────────────────────
        item(key = "search") {
            OutlinedTextField(
                value = searchQuery,
                onValueChange = onSearchChange,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Search ${category.replaceFirstChar { it.uppercase() }} models") },
                leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                trailingIcon = {
                    if (isLoading) CircularProgressIndicator(modifier = Modifier.size(20.dp))
                },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                keyboardActions = KeyboardActions(onSearch = { focusManager.clearFocus() }),
            )
        }

        // ── Search results ─────────────────────────────────────────────
        if (searchResults.isNotEmpty()) {
            items(searchResults, key = { "result_${it.id}" }) { device ->
                DeviceResultRow(
                    device = device,
                    isSelected = selectedDevice?.id == device.id,
                    onSelect = { onDeviceSelect(device) },
                )
            }
        } else if (searchQuery.length >= 2 && !isLoading) {
            item(key = "no_results") {
                Text(
                    "No models found — enter a custom name below.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(vertical = 4.dp),
                )
            }
        }

        // ── Popular devices ─────────────────────────────────────────────
        if (searchQuery.isBlank() && popularDevices.isNotEmpty()) {
            item(key = "popular_header") {
                Text("Popular", style = MaterialTheme.typography.labelMedium)
            }
            items(popularDevices.take(10), key = { "pop_${it.id}" }) { device ->
                DeviceResultRow(
                    device = device,
                    isSelected = selectedDevice?.id == device.id,
                    onSelect = { onDeviceSelect(device) },
                )
            }
        }

        // ── Custom device entry ─────────────────────────────────────────
        item(key = "custom") {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                OutlinedTextField(
                    value = customDeviceName,
                    onValueChange = onCustomNameChange,
                    modifier = Modifier.weight(1f),
                    label = { Text("Custom / unlisted device") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = {
                        focusManager.clearFocus()
                        onCustomDeviceConfirm()
                    }),
                )
                if (customDeviceName.isNotBlank()) {
                    Button(onClick = onCustomDeviceConfirm) { Text("Use") }
                }
            }
        }
    }
}

// ── Private sub-composables ─────────────────────────────────────────────────

@Composable
private fun ManufacturerFilterRow(
    manufacturers: List<ManufacturerItem>,
    selectedId: Long?,
    onSelect: (Long?) -> Unit,
) {
    Row(
        modifier = Modifier.horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        FilterChip(
            selected = selectedId == null,
            onClick = { onSelect(null) },
            label = { Text("All") },
        )
        manufacturers.forEach { mfg ->
            FilterChip(
                selected = selectedId == mfg.id,
                onClick = { onSelect(mfg.id) },
                label = { Text(mfg.name) },
            )
        }
    }
}

@Composable
private fun DeviceResultRow(
    device: DeviceModelItem,
    isSelected: Boolean,
    onSelect: () -> Unit,
) {
    ListItem(
        headlineContent = { Text(device.name) },
        supportingContent = device.manufacturerName?.let { { Text(it) } },
        trailingContent = {
            if (isSelected) Icon(Icons.Default.Check, contentDescription = "Selected", tint = MaterialTheme.colorScheme.primary)
        },
        modifier = Modifier.clickable(onClick = onSelect),
    )
    HorizontalDivider()
}
