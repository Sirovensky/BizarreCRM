package com.bizarreelectronics.crm.ui.screens.estimates.components

import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ScrollableTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

/** Ordered tab labels for the estimate list status filter. */
val ESTIMATE_STATUS_TABS = listOf("All", "Draft", "Sent", "Approved", "Rejected", "Expired")

/**
 * Scrollable tab row for filtering estimates by status.
 *
 * Mirrors [InvoiceStatusChip] approach but uses [ScrollableTabRow] to allow
 * future tab additions without overflow. The selected tab is highlighted via
 * Material 3 indicator. Tab a11y announcements include "selected / not selected"
 * so TalkBack gives full context without reading the indicator color.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EstimateStatusTabs(
    selectedStatus: String,
    onStatusSelected: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val selectedIndex = ESTIMATE_STATUS_TABS.indexOf(selectedStatus).coerceAtLeast(0)

    ScrollableTabRow(
        selectedTabIndex = selectedIndex,
        modifier = modifier,
        edgePadding = 16.dp,
        containerColor = MaterialTheme.colorScheme.surface,
    ) {
        ESTIMATE_STATUS_TABS.forEachIndexed { index, label ->
            val isSelected = index == selectedIndex
            Tab(
                selected = isSelected,
                onClick = { onStatusSelected(label) },
                text = { Text(label, style = MaterialTheme.typography.labelLarge) },
                modifier = Modifier.semantics {
                    contentDescription = if (isSelected) "$label, selected" else "$label, not selected"
                },
            )
        }
    }
}
