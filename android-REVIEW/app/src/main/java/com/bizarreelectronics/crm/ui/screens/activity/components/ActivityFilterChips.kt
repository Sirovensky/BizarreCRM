package com.bizarreelectronics.crm.ui.screens.activity.components

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

/**
 * §3.16 L594 — Horizontally-scrolling filter chip row for the Activity feed.
 *
 * Chips: {All | Tickets | Invoices | Customers | Inventory | My Activity}
 * Multi-select: any combination of type chips can be active simultaneously.
 * "All" clears all type selections (exclusive shortcut).
 *
 * @param filter        Current active filter state from [ActivityFeedViewModel].
 * @param onFilterChange Called when user toggles a chip.
 */
@Composable
fun ActivityFilterChips(
    filter: ActivityFilter,
    onFilterChange: (ActivityFilter) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        // "All" chip — clears all type selections
        FilterChip(
            selected = filter.types.isEmpty(),
            onClick = { onFilterChange(filter.copy(types = emptySet())) },
            label = { Text("All") },
            modifier = Modifier.semantics {
                contentDescription = "Show all activity types"
            },
            colors = FilterChipDefaults.filterChipColors(
                selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
                selectedLabelColor = MaterialTheme.colorScheme.onPrimaryContainer,
            ),
        )

        ActivityEventType.entries.forEach { type ->
            val selected = type.key in filter.types
            FilterChip(
                selected = selected,
                onClick = {
                    val newTypes = if (selected) {
                        filter.types - type.key
                    } else {
                        filter.types + type.key
                    }
                    onFilterChange(filter.copy(types = newTypes))
                },
                label = { Text(type.label) },
                modifier = Modifier.semantics {
                    contentDescription = "${if (selected) "Remove" else "Add"} ${type.label} filter"
                },
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
                    selectedLabelColor = MaterialTheme.colorScheme.onPrimaryContainer,
                ),
            )
        }

        // "My Activity" chip — filters by current employee
        FilterChip(
            selected = filter.myActivityOnly,
            onClick = {
                onFilterChange(filter.copy(myActivityOnly = !filter.myActivityOnly))
            },
            label = { Text("My Activity") },
            modifier = Modifier.semantics {
                contentDescription = if (filter.myActivityOnly) "Remove My Activity filter" else "Show only my activity"
            },
            colors = FilterChipDefaults.filterChipColors(
                selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
                selectedLabelColor = MaterialTheme.colorScheme.onPrimaryContainer,
            ),
        )
    }
}

/**
 * §3.16 L594 — Immutable filter state for the Activity feed.
 *
 * @param types          Set of [ActivityEventType.key] strings to include.
 *                       Empty = all types.
 * @param myActivityOnly When true, only events performed by the current user.
 */
data class ActivityFilter(
    val types: Set<String> = emptySet(),
    val myActivityOnly: Boolean = false,
) {
    /** Returns the comma-separated types query param, or null when all types requested. */
    fun typesParam(): String? = types.joinToString(",").takeIf { it.isNotBlank() }
}

/** Canonical event-type labels for the filter chip row. */
enum class ActivityEventType(val key: String, val label: String) {
    TICKET("ticket", "Tickets"),
    INVOICE("invoice", "Invoices"),
    CUSTOMER("customer", "Customers"),
    INVENTORY("inventory", "Inventory"),
}
