package com.bizarreelectronics.crm.ui.screens.inventory.components

import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color

/**
 * Context menu for an inventory row.
 *
 * Triggered by:
 *   - Long-press on the row (parent handles the gesture and sets [expanded] = true)
 *   - The overflow "…" IconButton on each row
 *
 * Options:
 *   Open / Copy SKU / Adjust stock / Print label (TODO stub) / Duplicate / Deactivate
 */
@Composable
fun InventoryContextMenu(
    expanded: Boolean,
    onDismiss: () -> Unit,
    onOpen: () -> Unit,
    onCopySku: () -> Unit,
    onAdjustStock: () -> Unit,
    onPrintLabel: () -> Unit,
    onDuplicate: () -> Unit,
    onDeactivate: () -> Unit,
    modifier: Modifier = Modifier,
) {
    DropdownMenu(
        expanded = expanded,
        onDismissRequest = onDismiss,
        modifier = modifier,
    ) {
        DropdownMenuItem(
            text = { Text("Open") },
            onClick = { onOpen(); onDismiss() },
        )
        DropdownMenuItem(
            text = { Text("Copy SKU") },
            onClick = { onCopySku(); onDismiss() },
        )
        DropdownMenuItem(
            text = { Text("Adjust stock") },
            onClick = { onAdjustStock(); onDismiss() },
        )
        DropdownMenuItem(
            text = { Text("Print label") },
            onClick = { onPrintLabel(); onDismiss() },
        )
        DropdownMenuItem(
            text = { Text("Duplicate") },
            onClick = { onDuplicate(); onDismiss() },
        )
        DropdownMenuItem(
            text = {
                Text(
                    "Deactivate",
                    color = MaterialTheme.colorScheme.error,
                )
            },
            onClick = { onDeactivate(); onDismiss() },
        )
    }
}
