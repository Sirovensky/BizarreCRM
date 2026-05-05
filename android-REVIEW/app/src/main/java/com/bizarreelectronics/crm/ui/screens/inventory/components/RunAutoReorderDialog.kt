package com.bizarreelectronics.crm.ui.screens.inventory.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Autorenew
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.dto.AutoReorderCreatedOrder
import com.bizarreelectronics.crm.data.remote.dto.AutoReorderRunResult
import com.bizarreelectronics.crm.util.CurrencyFormatter

/**
 * §6.8 Auto-reorder dialog — two phases in one composable:
 *
 *  1. **Confirmation** — shown when [result] is null and [isRunning] is false.
 *     Explains what will happen and offers "Run" / "Cancel".
 *
 *  2. **Running** — [isRunning] is true; shows a progress indicator.
 *
 *  3. **Result** — [result] is non-null; summarises created POs and lets
 *     the admin dismiss.
 *
 * The dialog is intentionally self-contained: all three states share the
 * same dismiss action ([onDismiss]) so the caller only needs one
 * `showDialog` flag.
 */
@Composable
fun RunAutoReorderDialog(
    isRunning: Boolean,
    result: AutoReorderRunResult?,
    errorMessage: String?,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = { if (!isRunning) onDismiss() },
        icon = {
            if (result != null) {
                Icon(
                    Icons.Default.CheckCircle,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(32.dp),
                )
            } else {
                Icon(
                    Icons.Default.Autorenew,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(32.dp),
                )
            }
        },
        title = {
            Text(
                text = when {
                    result != null -> "Auto-reorder complete"
                    isRunning     -> "Creating purchase orders…"
                    else          -> "Run auto-reorder"
                },
                style = MaterialTheme.typography.titleLarge,
            )
        },
        text = {
            when {
                isRunning -> RunningContent()
                result != null -> ResultContent(result)
                errorMessage != null -> ErrorContent(errorMessage)
                else -> ConfirmContent()
            }
        },
        confirmButton = {
            when {
                isRunning -> { /* no confirm while running */ }
                result != null -> {
                    Button(onClick = onDismiss) { Text("Done") }
                }
                errorMessage != null -> {
                    Button(onClick = onDismiss) { Text("Close") }
                }
                else -> {
                    Button(onClick = onConfirm) { Text("Run now") }
                }
            }
        },
        dismissButton = {
            if (!isRunning && result == null && errorMessage == null) {
                TextButton(onClick = onDismiss) { Text("Cancel") }
            }
        },
    )
}

// ─── Phase 1: confirmation ────────────────────────────────────────────────────

@Composable
private fun ConfirmContent() {
    Text(
        "Scans all inventory items whose stock is at or below their reorder threshold " +
            "and have a supplier assigned. Groups qualifying items by supplier and " +
            "creates one draft purchase order per supplier.\n\n" +
            "Only items marked as reorderable are included. " +
            "Review each purchase order before sending.",
        style = MaterialTheme.typography.bodyMedium,
    )
}

// ─── Phase 2: running ─────────────────────────────────────────────────────────

@Composable
private fun RunningContent() {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp)
            .semantics { contentDescription = "Creating purchase orders, please wait" },
    ) {
        CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
        Spacer(Modifier.width(12.dp))
        Text(
            "Checking stock levels…",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

// ─── Phase 3a: result ─────────────────────────────────────────────────────────

@Composable
private fun ResultContent(result: AutoReorderRunResult) {
    Column(
        modifier = Modifier.verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (result.ordersCreated == 0) {
            Text(
                "No items qualified for reorder. All stock levels are above their " +
                    "reorder thresholds, or items are missing a supplier assignment.",
                style = MaterialTheme.typography.bodyMedium,
            )
            return@Column
        }

        // Summary row
        Text(
            "${result.ordersCreated} purchase order${if (result.ordersCreated == 1) "" else "s"} " +
                "created · ${result.itemsOrdered} item${if (result.itemsOrdered == 1) "" else "s"} ordered",
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold,
        )

        Spacer(Modifier.height(4.dp))

        result.orders.forEach { order ->
            HorizontalDivider()
            OrderSummaryRow(order)
        }
    }
}

@Composable
private fun OrderSummaryRow(order: AutoReorderCreatedOrder) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(
                order.supplierName ?: "Unknown supplier",
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Medium,
            )
            Text(
                order.orderId ?: "",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        order.items.forEach { item ->
            Text(
                "• ${item.name ?: "Item"} × ${item.quantityOrdered}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        order.subtotal?.let { sub ->
            Text(
                "Subtotal: ${CurrencyFormatter.format(sub)}",
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }
}

// ─── Phase 3b: error ──────────────────────────────────────────────────────────

@Composable
private fun ErrorContent(message: String) {
    Text(
        message,
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.error,
    )
}
