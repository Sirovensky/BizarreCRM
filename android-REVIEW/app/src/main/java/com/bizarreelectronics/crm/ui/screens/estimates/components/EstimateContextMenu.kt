package com.bizarreelectronics.crm.ui.screens.estimates.components

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.OpenInNew
import androidx.compose.material.icons.filled.Receipt
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.filled.ThumbDown
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

/**
 * Context menu shown on long-press of an estimate list row.
 *
 * Actions: Open · Copy # · Send · Approve · Reject · Convert to ticket ·
 *          Convert to invoice · Delete.
 *
 * All icons are decorative (contentDescription = null) — the DropdownMenuItem
 * text provides the accessible label.
 */
@Composable
fun EstimateContextMenu(
    estimateNumber: String,
    expanded: Boolean,
    onDismiss: () -> Unit,
    onOpen: () -> Unit,
    onCopyNumber: () -> Unit,
    onSend: () -> Unit,
    onApprove: () -> Unit,
    onReject: () -> Unit,
    onConvertToTicket: () -> Unit,
    onConvertToInvoice: () -> Unit,
    onDelete: () -> Unit,
    modifier: Modifier = Modifier,
) {
    DropdownMenu(
        expanded = expanded,
        onDismissRequest = onDismiss,
        modifier = modifier,
    ) {
        DropdownMenuItem(
            text = { Text("Open") },
            leadingIcon = { Icon(Icons.Default.OpenInNew, contentDescription = null) },
            onClick = { onDismiss(); onOpen() },
        )
        DropdownMenuItem(
            text = { Text("Copy #$estimateNumber") },
            leadingIcon = { Icon(Icons.Default.ContentCopy, contentDescription = null) },
            onClick = { onDismiss(); onCopyNumber() },
        )
        DropdownMenuItem(
            text = { Text("Send") },
            leadingIcon = { Icon(Icons.Default.Send, contentDescription = null) },
            onClick = { onDismiss(); onSend() },
        )
        DropdownMenuItem(
            text = { Text("Approve") },
            leadingIcon = { Icon(Icons.Default.CheckCircle, contentDescription = null) },
            onClick = { onDismiss(); onApprove() },
        )
        DropdownMenuItem(
            text = { Text("Reject") },
            leadingIcon = { Icon(Icons.Default.ThumbDown, contentDescription = null) },
            onClick = { onDismiss(); onReject() },
        )
        DropdownMenuItem(
            text = { Text("Convert to ticket") },
            leadingIcon = { Icon(Icons.Default.SwapHoriz, contentDescription = null) },
            onClick = { onDismiss(); onConvertToTicket() },
        )
        DropdownMenuItem(
            text = { Text("Convert to invoice") },
            leadingIcon = { Icon(Icons.Default.Receipt, contentDescription = null) },
            onClick = { onDismiss(); onConvertToInvoice() },
        )
        DropdownMenuItem(
            text = { Text("Delete", color = MaterialTheme.colorScheme.error) },
            leadingIcon = {
                Icon(
                    Icons.Default.Delete,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.error,
                )
            },
            onClick = { onDismiss(); onDelete() },
        )
    }
}
