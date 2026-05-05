package com.bizarreelectronics.crm.ui.screens.inventory.components

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Autorenew
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.components.shared.BrandCard

/**
 * Auto-reorder configuration card (L1075).
 *
 * Displays the current reorder threshold and reorder quantity and lets the user
 * edit them inline. Changes are written back via [onSave] which should call
 * [InventoryApi.setAutoReorder]. The preferred supplier field is a free-text
 * stub until supplier search is wired.
 *
 * @param reorderThreshold   Current minimum stock level before auto-reorder triggers.
 * @param reorderQty         Current quantity to reorder when threshold is breached.
 * @param preferredSupplier  Current preferred supplier name (free text).
 * @param isSaving           True while a PATCH is in-flight — disables the Save button.
 * @param onSave             Invoked with (threshold, qty, supplier) when user taps Save.
 * @param modifier           Applied to the root [BrandCard].
 */
@Composable
fun InventoryAutoReorderCard(
    reorderThreshold: Int,
    reorderQty: Int,
    preferredSupplier: String,
    isSaving: Boolean,
    onSave: (threshold: Int, qty: Int, supplier: String) -> Unit,
    modifier: Modifier = Modifier,
) {
    var thresholdText by rememberSaveable(reorderThreshold) {
        mutableStateOf(reorderThreshold.toString())
    }
    var qtyText by rememberSaveable(reorderQty) {
        mutableStateOf(reorderQty.toString())
    }
    var supplierText by rememberSaveable(preferredSupplier) {
        mutableStateOf(preferredSupplier)
    }

    val thresholdVal = thresholdText.toIntOrNull()
    val qtyVal = qtyText.toIntOrNull()
    val isValid = thresholdVal != null && thresholdVal >= 0 && qtyVal != null && qtyVal >= 0
    val isDirty = thresholdText != reorderThreshold.toString() ||
        qtyText != reorderQty.toString() ||
        supplierText != preferredSupplier

    BrandCard(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    Icons.Default.Autorenew,
                    contentDescription = null,
                    modifier = Modifier.size(18.dp),
                    tint = MaterialTheme.colorScheme.primary,
                )
                Text("Auto-reorder", style = MaterialTheme.typography.titleSmall)
            }

            Row(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                OutlinedTextField(
                    value = thresholdText,
                    onValueChange = { v -> if (v.isEmpty() || v.matches(Regex("^\\d+$"))) thresholdText = v },
                    label = { Text("Threshold") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                    supportingText = { Text("Min stock") },
                    isError = thresholdVal == null,
                )
                OutlinedTextField(
                    value = qtyText,
                    onValueChange = { v -> if (v.isEmpty() || v.matches(Regex("^\\d+$"))) qtyText = v },
                    label = { Text("Reorder qty") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                    isError = qtyVal == null,
                )
            }

            OutlinedTextField(
                value = supplierText,
                onValueChange = { supplierText = it },
                label = { Text("Preferred supplier") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )

            if (isDirty) {
                Button(
                    onClick = {
                        val t = thresholdVal ?: return@Button
                        val q = qtyVal ?: return@Button
                        onSave(t, q, supplierText)
                    },
                    enabled = isValid && !isSaving,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    if (isSaving) {
                        CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Saving…")
                    } else {
                        Icon(Icons.Default.Check, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(modifier = Modifier.width(6.dp))
                        Text("Save auto-reorder")
                    }
                }
            }
        }
    }
}
