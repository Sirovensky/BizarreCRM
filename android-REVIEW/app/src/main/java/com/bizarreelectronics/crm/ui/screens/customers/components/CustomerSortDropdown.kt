package com.bizarreelectronics.crm.ui.screens.customers.components

import androidx.compose.foundation.layout.Box
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Sort
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.text.font.FontWeight

/**
 * Sort options for the customer list (plan:L875).
 * Default is [Recent] (most recently updated first).
 */
enum class CustomerSort(val label: String, val sortKey: String) {
    Recent("Most recent", "recent"),
    AZ("A–Z", "az"),
    ZA("Z–A", "za"),
    MostTickets("Most tickets", "tickets"),
    MostRevenue("Most revenue", "revenue"),
    LastVisit("Last visit", "last_visit"),
}

/**
 * Overflow icon button that expands a [DropdownMenu] with all [CustomerSort] options.
 * Mirrors [TicketSortDropdown] pattern exactly.
 *
 * @param currentSort    Currently active sort, shown highlighted.
 * @param onSortSelected Callback when the user picks a new sort order.
 */
@Composable
fun CustomerSortDropdown(
    currentSort: CustomerSort,
    onSortSelected: (CustomerSort) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }

    Box(contentAlignment = Alignment.TopEnd) {
        IconButton(onClick = { expanded = true }) {
            Icon(
                imageVector = Icons.Default.Sort,
                contentDescription = "Sort customers",
                tint = MaterialTheme.colorScheme.onSurface,
            )
        }
        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
        ) {
            CustomerSort.entries.forEach { sort ->
                val isSelected = sort == currentSort
                DropdownMenuItem(
                    text = {
                        Text(
                            text = sort.label,
                            color = if (isSelected) {
                                MaterialTheme.colorScheme.primary
                            } else {
                                MaterialTheme.colorScheme.onSurface
                            },
                            style = if (isSelected) {
                                MaterialTheme.typography.bodyMedium.copy(
                                    fontWeight = FontWeight.SemiBold,
                                )
                            } else {
                                MaterialTheme.typography.bodyMedium
                            },
                        )
                    },
                    onClick = {
                        onSortSelected(sort)
                        expanded = false
                    },
                )
            }
        }
    }
}
