package com.bizarreelectronics.crm.ui.screens.inventory.components

import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp

/**
 * Reason options for a stock adjustment.
 */
enum class AdjustReason(val label: String, val apiType: String) {
    Sold("Sold", "sold"),
    Received("Received", "received"),
    Damaged("Damaged", "damaged"),
    Adjusted("Adjusted", "adjusted"),
}

/**
 * Inline +/- stepper that sits at the end of an inventory row.
 * On tablet-wide layouts it is visible; on phone it is hidden (caller controls).
 *
 * Long-press opens a [ModalBottomSheet] for exact amount + reason entry.
 *
 * @param stockQty Current quantity shown between the buttons.
 * @param onAdjust Called with a signed delta (+N or -N) and the adjustment type string.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QuickStockAdjust(
    stockQty: Int,
    onAdjust: (delta: Int, type: String, reason: String?) -> Unit,
    modifier: Modifier = Modifier,
) {
    var showDetailSheet by remember { mutableStateOf(false) }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    Row(
        modifier = modifier.pointerInput(Unit) {
            detectTapGestures(onLongPress = { showDetailSheet = true })
        },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        FilledIconButton(
            onClick = { onAdjust(-1, AdjustReason.Adjusted.apiType, null) },
            modifier = Modifier.size(28.dp),
            colors = IconButtonDefaults.filledIconButtonColors(
                containerColor = MaterialTheme.colorScheme.errorContainer,
                contentColor = MaterialTheme.colorScheme.onErrorContainer,
            ),
        ) {
            Icon(Icons.Default.Remove, contentDescription = "Decrease stock")
        }

        Text(
            text = "$stockQty",
            style = MaterialTheme.typography.labelLarge,
            modifier = Modifier.width(28.dp),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        )

        FilledIconButton(
            onClick = { onAdjust(+1, AdjustReason.Received.apiType, null) },
            modifier = Modifier.size(28.dp),
            colors = IconButtonDefaults.filledIconButtonColors(
                containerColor = MaterialTheme.colorScheme.primaryContainer,
                contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
            ),
        ) {
            Icon(Icons.Default.Add, contentDescription = "Increase stock")
        }
    }

    if (showDetailSheet) {
        ModalBottomSheet(
            onDismissRequest = { showDetailSheet = false },
            sheetState = sheetState,
        ) {
            StockAdjustSheet(
                currentQty = stockQty,
                onConfirm = { delta, type, reason ->
                    onAdjust(delta, type, reason)
                    showDetailSheet = false
                },
                onDismiss = { showDetailSheet = false },
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun StockAdjustSheet(
    currentQty: Int,
    onConfirm: (delta: Int, type: String, reason: String?) -> Unit,
    onDismiss: () -> Unit,
) {
    var amount by remember { mutableIntStateOf(1) }
    var amountText by remember { mutableStateOf("1") }
    var selectedReason by remember { mutableStateOf(AdjustReason.Adjusted) }
    var reasonMenuExpanded by remember { mutableStateOf(false) }
    var isDelta by remember { mutableStateOf(true) } // true = +/- delta, false = set absolute

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("Adjust stock", style = MaterialTheme.typography.titleMedium)
        Text(
            "Current qty: $currentQty",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        OutlinedTextField(
            value = amountText,
            onValueChange = { v ->
                amountText = v
                amount = v.toIntOrNull() ?: 0
            },
            label = { Text("Amount") },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )

        // Reason dropdown
        ExposedDropdownMenuBox(
            expanded = reasonMenuExpanded,
            onExpandedChange = { reasonMenuExpanded = it },
        ) {
            OutlinedTextField(
                value = selectedReason.label,
                onValueChange = {},
                readOnly = true,
                label = { Text("Reason") },
                trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = reasonMenuExpanded) },
                modifier = Modifier.fillMaxWidth().menuAnchor(),
            )
            ExposedDropdownMenu(
                expanded = reasonMenuExpanded,
                onDismissRequest = { reasonMenuExpanded = false },
            ) {
                AdjustReason.entries.forEach { reason ->
                    DropdownMenuItem(
                        text = { Text(reason.label) },
                        onClick = {
                            selectedReason = reason
                            reasonMenuExpanded = false
                        },
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(4.dp))

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.End,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TextButton(onClick = onDismiss) { Text("Cancel") }
            Spacer(modifier = Modifier.width(8.dp))
            Button(
                onClick = {
                    val delta = when (selectedReason) {
                        AdjustReason.Sold, AdjustReason.Damaged -> -amount
                        else -> amount
                    }
                    onConfirm(delta, selectedReason.apiType, selectedReason.label)
                },
                enabled = amount > 0,
            ) {
                Text("Apply")
            }
        }
    }
}
