package com.bizarreelectronics.crm.ui.screens.employees.components

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * §14.1 L1610 — Employee list filter chips.
 *
 * Chips: All / Role:Admin / Role:Technician / Active / Inactive / Clocked-in.
 * Horizontally scrollable so more chips can be added without wrapping.
 * Selected chip is highlighted via FilterChip's built-in selected styling.
 */
enum class EmployeeFilter(val label: String) {
    All("All"),
    Admin("Admin"),
    Technician("Technician"),
    Active("Active"),
    Inactive("Inactive"),
    ClockedIn("Clocked in"),
}

@Composable
fun EmployeeFilterChips(
    selected: EmployeeFilter,
    onSelect: (EmployeeFilter) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 12.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        EmployeeFilter.entries.forEach { filter ->
            FilterChip(
                selected = selected == filter,
                onClick = { onSelect(filter) },
                label = {
                    Text(
                        text = filter.label,
                        style = MaterialTheme.typography.labelMedium,
                    )
                },
            )
        }
    }
}
