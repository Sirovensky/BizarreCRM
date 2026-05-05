package com.bizarreelectronics.crm.ui.screens.appointments.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.screens.appointments.AppointmentFilter

/**
 * Horizontal filter chip row (L1425): Employee / Location / Type.
 * Each chip opens a ModalBottomSheet picker.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FilterChipRow(
    filter: AppointmentFilter,
    onFilterChange: (AppointmentFilter) -> Unit,
    modifier: Modifier = Modifier,
) {
    var showEmployeeSheet by remember { mutableStateOf(false) }
    var showLocationSheet by remember { mutableStateOf(false) }
    var showTypeSheet by remember { mutableStateOf(false) }

    Row(
        modifier = modifier.horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = Icons.Default.FilterList,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(18.dp),
        )

        FilterChip(
            selected = filter.employeeId != null,
            onClick = { showEmployeeSheet = true },
            label = { Text(filter.employeeName ?: "Employee") },
            trailingIcon = if (filter.employeeId != null) {
                {
                    Icon(
                        imageVector = Icons.Default.Close,
                        contentDescription = "Clear employee filter",
                        modifier = Modifier
                            .size(14.dp)
                            .clickable {
                                onFilterChange(filter.copy(employeeId = null, employeeName = null))
                            },
                    )
                }
            } else null,
        )

        FilterChip(
            selected = filter.location != null,
            onClick = { showLocationSheet = true },
            label = { Text(filter.location ?: "Location") },
            trailingIcon = if (filter.location != null) {
                {
                    Icon(
                        imageVector = Icons.Default.Close,
                        contentDescription = "Clear location filter",
                        modifier = Modifier
                            .size(14.dp)
                            .clickable { onFilterChange(filter.copy(location = null)) },
                    )
                }
            } else null,
        )

        FilterChip(
            selected = filter.type != null,
            onClick = { showTypeSheet = true },
            label = { Text(filter.type ?: "Type") },
            trailingIcon = if (filter.type != null) {
                {
                    Icon(
                        imageVector = Icons.Default.Close,
                        contentDescription = "Clear type filter",
                        modifier = Modifier
                            .size(14.dp)
                            .clickable { onFilterChange(filter.copy(type = null)) },
                    )
                }
            } else null,
        )
    }

    if (showEmployeeSheet) {
        ModalBottomSheet(onDismissRequest = { showEmployeeSheet = false }) {
            FilterPickerContent(
                title = "Filter by employee",
                options = listOf("All employees"),
                onSelect = { label ->
                    onFilterChange(
                        filter.copy(
                            employeeId = if (label == "All employees") null else 1L,
                            employeeName = if (label == "All employees") null else label,
                        ),
                    )
                    showEmployeeSheet = false
                },
                onClear = {
                    onFilterChange(filter.copy(employeeId = null, employeeName = null))
                    showEmployeeSheet = false
                },
            )
        }
    }

    if (showLocationSheet) {
        ModalBottomSheet(onDismissRequest = { showLocationSheet = false }) {
            FilterPickerContent(
                title = "Filter by location",
                options = listOf("All locations", "Main store", "Secondary"),
                onSelect = { label ->
                    onFilterChange(
                        filter.copy(location = if (label.startsWith("All")) null else label),
                    )
                    showLocationSheet = false
                },
                onClear = {
                    onFilterChange(filter.copy(location = null))
                    showLocationSheet = false
                },
            )
        }
    }

    if (showTypeSheet) {
        ModalBottomSheet(onDismissRequest = { showTypeSheet = false }) {
            FilterPickerContent(
                title = "Filter by type",
                options = listOf("All types", "Repair", "Diagnostic", "Pickup", "Drop-off"),
                onSelect = { label ->
                    onFilterChange(
                        filter.copy(type = if (label.startsWith("All")) null else label),
                    )
                    showTypeSheet = false
                },
                onClear = {
                    onFilterChange(filter.copy(type = null))
                    showTypeSheet = false
                },
            )
        }
    }
}

@Composable
private fun FilterPickerContent(
    title: String,
    options: List<String>,
    onSelect: (String) -> Unit,
    onClear: () -> Unit,
) {
    Column(modifier = Modifier.padding(bottom = 32.dp)) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.padding(horizontal = 24.dp, vertical = 16.dp),
        )
        HorizontalDivider()
        options.forEach { option ->
            Text(
                text = option,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onSelect(option) }
                    .padding(horizontal = 24.dp, vertical = 14.dp),
            )
            HorizontalDivider()
        }
        TextButton(
            onClick = onClear,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp, vertical = 8.dp),
        ) {
            Text("Clear filter")
        }
    }
}
