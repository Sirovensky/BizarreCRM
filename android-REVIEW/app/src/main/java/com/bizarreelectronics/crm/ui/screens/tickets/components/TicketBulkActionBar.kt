package com.bizarreelectronics.crm.ui.screens.tickets.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Archive
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Label
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * L724 — Bulk action bar for multi-selected tickets.
 *
 * Replaces the private [BulkActionBar] composable that lived inline in
 * [TicketListScreen]. This extracted component wires all four bulk actions:
 *
 * - Bulk assign → [onBulkAssign] opens an employee picker.
 * - Bulk status → [onBulkStatus] opens a status picker.
 * - Bulk archive → [onBulkArchive] sends POST /tickets/bulk-action {action:"archive"}.
 * - Bulk tag     → [onBulkTag] opens a tag/label picker.
 *
 * The bar is displayed at the bottom of the screen whenever [isSelecting] is true.
 * [selectedCount] drives the left-hand count badge.
 */
@Composable
fun TicketBulkActionBar(
    selectedCount: Int,
    onBulkAssign: () -> Unit,
    onBulkStatus: () -> Unit,
    onBulkArchive: () -> Unit,
    onBulkTag: () -> Unit,
    onExitSelect: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        tonalElevation = 3.dp,
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        modifier = modifier,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                text = "$selectedCount selected",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.weight(1f),
            )

            // Bulk assign
            FilledTonalButton(
                onClick = onBulkAssign,
                contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 10.dp, vertical = 6.dp),
            ) {
                Icon(
                    Icons.Default.PersonAdd,
                    contentDescription = null,
                    modifier = Modifier.padding(end = 4.dp),
                )
                Text("Assign", style = MaterialTheme.typography.labelMedium)
            }

            // Bulk status
            FilledTonalButton(
                onClick = onBulkStatus,
                contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 10.dp, vertical = 6.dp),
            ) {
                Text("Status", style = MaterialTheme.typography.labelMedium)
            }

            // Bulk archive
            IconButton(onClick = onBulkArchive) {
                Icon(
                    Icons.Default.Archive,
                    contentDescription = "Archive selected tickets",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            // Bulk tag
            IconButton(onClick = onBulkTag) {
                Icon(
                    Icons.Default.Label,
                    contentDescription = "Tag selected tickets",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            // Exit select mode
            IconButton(onClick = onExitSelect) {
                Icon(Icons.Default.Close, contentDescription = "Exit selection mode")
            }
        }
    }
}
