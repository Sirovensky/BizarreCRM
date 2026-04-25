package com.bizarreelectronics.crm.ui.screens.pos.components

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.screens.pos.toDollarString

/**
 * Dialog that lets the cashier choose how to split a payment across
 * multiple tender methods.
 *
 * Two split strategies are offered:
 * - **Split evenly N ways** — the cashier picks a part count (2–6) via a
 *   simple row of chips; each part receives an equal share of [remainingCents].
 * - **Split by item** — defers to a future item-level split screen
 *   (Wave 2 concern); fires [onSplitByItem] immediately.
 *
 * Placement: shown from [PosTenderScreen] when the "Split payment" action is
 * tapped.
 *
 * @param totalCents       Full cart total displayed for reference.
 * @param remainingCents   Amount still owed; drives the "N ways" label.
 * @param onSplitEvenly    Called with the chosen part count (2–6).
 * @param onSplitByItem    Called when the cashier chooses item-level split.
 * @param onDismiss        Called on Cancel or outside-tap.
 */
@Composable
fun PosSplitTenderDialog(
    totalCents: Long,
    remainingCents: Long,
    onSplitEvenly: (parts: Int) -> Unit,
    onSplitByItem: () -> Unit,
    onDismiss: () -> Unit,
) {
    var selectedParts by remember { mutableIntStateOf(2) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Split payment") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Text(
                    text = "Total: ${totalCents.toDollarString()}  ·  Remaining: ${remainingCents.toDollarString()}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )

                // ── Split evenly section ──────────────────────────────────
                Text(
                    text = "Split evenly",
                    style = MaterialTheme.typography.labelLarge,
                )

                // Part-count picker: chips for 2..6
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    for (n in 2..6) {
                        FilterChip(
                            selected = selectedParts == n,
                            onClick = { selectedParts = n },
                            label = { Text("$n") },
                        )
                    }
                }

                val perPart = if (selectedParts > 0) remainingCents / selectedParts else 0L
                Text(
                    text = "${perPart.toDollarString()} per part",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )

                Button(
                    onClick = { onSplitEvenly(selectedParts) },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Split evenly $selectedParts ways")
                }

                HorizontalDivider()

                // ── Split by item section ─────────────────────────────────
                Text(
                    text = "Or split by item",
                    style = MaterialTheme.typography.labelLarge,
                )

                OutlinedButton(
                    onClick = onSplitByItem,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Split by item")
                }
            }
        },
        confirmButton = {},
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        },
    )
}
