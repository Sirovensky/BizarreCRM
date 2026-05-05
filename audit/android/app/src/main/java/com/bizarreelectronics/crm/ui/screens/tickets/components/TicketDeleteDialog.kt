package com.bizarreelectronics.crm.ui.screens.tickets.components

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DeleteForever
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable

/**
 * L715 — Destructive delete confirmation dialog.
 *
 * Only rendered when the caller has already verified privileged role (admin /
 * manager). The dialog uses a red confirm button and icon to signal the
 * destructive intent per Material 3 guidelines.
 *
 * [onConfirm] fires a soft-delete via [TicketApi.deleteTicket]; on success
 * the screen navigates back.
 */
@Composable
fun TicketDeleteDialog(
    orderId: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        icon = {
            Icon(
                Icons.Default.DeleteForever,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.error,
            )
        },
        title = { Text("Delete Ticket $orderId?") },
        text = {
            Text(
                "This ticket will be soft-deleted and removed from the list. " +
                    "Invoices and customer history are not affected. " +
                    "This action cannot be undone from the app.",
                style = MaterialTheme.typography.bodyMedium,
            )
        },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text(
                    "Delete",
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.labelLarge,
                )
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        },
    )
}
