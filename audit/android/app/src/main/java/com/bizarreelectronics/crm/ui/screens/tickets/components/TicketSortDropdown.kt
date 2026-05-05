package com.bizarreelectronics.crm.ui.screens.tickets.components

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

/**
 * Sort options for the ticket list.
 * Default is [Newest] (most recently created first).
 */
enum class TicketSort(val label: String) {
    Newest("Newest first"),
    Oldest("Oldest first"),
    Status("Status"),
    Urgency("Urgency"),
    DueDate("Due date"),
    CustomerAZ("Customer A–Z"),
}

/**
 * Overflow icon button that expands a [DropdownMenu] with all [TicketSort] options.
 *
 * The currently selected sort has its label highlighted in [MaterialTheme.colorScheme.primary].
 * Selecting an option calls [onSortSelected] and dismisses the menu.
 *
 * @param currentSort   Currently active sort, shown highlighted.
 * @param onSortSelected Callback when the user picks a new sort order.
 */
@Composable
fun TicketSortDropdown(
    currentSort: TicketSort,
    onSortSelected: (TicketSort) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }

    Box(contentAlignment = Alignment.TopEnd) {
        IconButton(onClick = { expanded = true }) {
            Icon(
                imageVector = Icons.Default.Sort,
                contentDescription = "Sort tickets",
                tint = MaterialTheme.colorScheme.onSurface,
            )
        }
        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
        ) {
            TicketSort.entries.forEach { sort ->
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
                                    fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold,
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
