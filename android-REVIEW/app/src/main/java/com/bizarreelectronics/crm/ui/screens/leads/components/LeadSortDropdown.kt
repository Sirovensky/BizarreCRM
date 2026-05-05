package com.bizarreelectronics.crm.ui.screens.leads.components

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
 * Sort options for the lead list (ActionPlan §9 L1375).
 * Default is [NameAZ].
 */
enum class LeadSort(val label: String) {
    NameAZ("Name A–Z"),
    CreatedNewest("Newest first"),
    CreatedOldest("Oldest first"),
    LeadScore("Lead score (high–low)"),
    LastActivity("Last activity"),
    NextAction("Next action date"),
}

/**
 * Applies [sort] to [leads]. Returns a new list — does not mutate the original.
 *
 * Nulls-last policy: fields that may be absent (score, dates) sort after
 * present values so incomplete records don't surface to the top.
 */
fun applySortOrder(
    leads: List<com.bizarreelectronics.crm.data.local.db.entities.LeadEntity>,
    sort: LeadSort,
): List<com.bizarreelectronics.crm.data.local.db.entities.LeadEntity> = when (sort) {
    LeadSort.NameAZ -> leads.sortedWith(
        compareBy(String.CASE_INSENSITIVE_ORDER) { lead ->
            listOfNotNull(lead.firstName, lead.lastName).joinToString(" ").ifBlank { "\uFFFF" }
        }
    )
    LeadSort.CreatedNewest -> leads.sortedByDescending { it.createdAt }
    LeadSort.CreatedOldest -> leads.sortedBy { it.createdAt }
    LeadSort.LeadScore -> leads.sortedByDescending { it.leadScore }
    LeadSort.LastActivity -> leads.sortedByDescending { it.updatedAt }
    LeadSort.NextAction -> leads.sortedBy { it.updatedAt } // updatedAt proxies next-action until dedicated field added
}

/**
 * Overflow icon button that expands a [DropdownMenu] with all [LeadSort] options.
 *
 * The currently selected sort has its label highlighted in primary color.
 * Selecting an option calls [onSortSelected] and dismisses the menu.
 */
@Composable
fun LeadSortDropdown(
    currentSort: LeadSort,
    onSortSelected: (LeadSort) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }

    Box(contentAlignment = Alignment.TopEnd) {
        IconButton(onClick = { expanded = true }) {
            Icon(
                imageVector = Icons.Default.Sort,
                contentDescription = "Sort leads",
                tint = MaterialTheme.colorScheme.onSurface,
            )
        }
        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
        ) {
            LeadSort.entries.forEach { sort ->
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
