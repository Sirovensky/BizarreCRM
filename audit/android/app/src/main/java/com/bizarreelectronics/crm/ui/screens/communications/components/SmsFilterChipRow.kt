package com.bizarreelectronics.crm.ui.screens.communications.components

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.dto.SmsConversationItem

/** Filter categories for the SMS conversation list. */
enum class SmsFilter(val label: String) {
    All("All"),
    Unread("Unread"),
    Flagged("Flagged"),
    Pinned("Pinned"),
    Archived("Archived"),
    Assigned("Assigned"),
    Unassigned("Unassigned"),
}

/**
 * Pure function: filters [all] conversations based on [filter].
 * Pinned threads are sorted to the top regardless of filter.
 */
fun applySmsFilter(
    all: List<SmsConversationItem>,
    filter: SmsFilter,
): List<SmsConversationItem> {
    val filtered = when (filter) {
        SmsFilter.All -> all
        SmsFilter.Unread -> all.filter { it.unreadCount > 0 }
        SmsFilter.Flagged -> all.filter { it.isFlagged }
        SmsFilter.Pinned -> all.filter { it.isPinned }
        SmsFilter.Archived -> all.filter { it.isArchived }
        SmsFilter.Assigned -> all.filter { it.assignedTo != null }
        SmsFilter.Unassigned -> all.filter { it.assignedTo == null }
    }
    // Pinned threads always sort to top
    return filtered.sortedByDescending { it.isPinned }
}

/**
 * Horizontal scrolling row of filter chips.
 * Updates [currentFilter] via [onFilterSelected] on tap.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SmsFilterChipRow(
    currentFilter: SmsFilter,
    onFilterSelected: (SmsFilter) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        SmsFilter.entries.forEach { filter ->
            FilterChip(
                selected = currentFilter == filter,
                onClick = { onFilterSelected(filter) },
                label = { Text(filter.label) },
            )
        }
    }
}
