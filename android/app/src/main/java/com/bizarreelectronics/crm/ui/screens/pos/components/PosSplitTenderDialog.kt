package com.bizarreelectronics.crm.ui.screens.pos.components

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.theme.SuccessGreen
import java.util.Locale
import java.util.UUID

data class SplitTenderEntry(
    val id: String = UUID.randomUUID().toString(),
    val method: String,
    val amountCents: Long,
)

/**
 * Split tender dialog — chains payment methods until balance = 0.
 *
 * Plan §16.1 L1810.
 */
@Composable
fun PosSplitTenderDialog(
    totalCents: Long,
    onComplete: (List<SplitTenderEntry>) -> Unit,
    onDismiss: () -> Unit,
) {
    val paymentMethods = listOf("Cash", "Card", "Gift Card", "Store Credit", "Check")

    var entries by remember { mutableStateOf<List<SplitTenderEntry>>(emptyList()) }
    var selectedMethod by remember { mutableStateOf(paymentMethods.first()) }
    var amountText by remember { mutableStateOf("") }

    val appliedCents = entries.sumOf { it.amountCents }
    val remainingCents = (totalCents - appliedCents).coerceAtLeast(0L)
    val isBalanced = remainingCents == 0L

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Split Tender") },
        text = {
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                // Running balance
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text("Total", style = MaterialTheme.typography.bodyMedium)
                    Text(
                        "$${String.format(Locale.US, "%.2f", totalCents / 100.0)}",
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Bold,
                    )
                }
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text("Remaining", style = MaterialTheme.typography.bodyMedium)
                    Text(
                        "$${String.format(Locale.US, "%.2f", remainingCents / 100.0)}",
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Bold,
                        color = if (isBalanced) SuccessGreen else MaterialTheme.colorScheme.error,
                        modifier = Modifier.semantics {
                            contentDescription = "Remaining balance: $${String.format(Locale.US, "%.2f", remainingCents / 100.0)}"
                        },
                    )
                }

                Divider()

                // Applied entries
                if (entries.isNotEmpty()) {
                    LazyColumn(
                        modifier = Modifier.heightIn(max = 120.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        items(entries, key = { it.id }) { entry ->
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                            ) {
                                Text(entry.method, style = MaterialTheme.typography.bodySmall)
                                Text(
                                    "$${String.format(Locale.US, "%.2f", entry.amountCents / 100.0)}",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = SuccessGreen,
                                )
                            }
                        }
                    }
                    Divider()
                }

                // Method picker
                if (!isBalanced) {
                    SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                        paymentMethods.forEachIndexed { idx, method ->
                            SegmentedButton(
                                selected = method == selectedMethod,
                                onClick = { selectedMethod = method },
                                shape = SegmentedButtonDefaults.itemShape(idx, paymentMethods.size),
                                label = { Text(method, style = MaterialTheme.typography.labelSmall) },
                            )
                        }
                    }

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        OutlinedTextField(
                            value = amountText,
                            onValueChange = { amountText = it },
                            label = { Text("Amount") },
                            leadingIcon = { Text("$") },
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                            singleLine = true,
                            modifier = Modifier.weight(1f),
                        )
                        // Quick-fill remaining
                        TextButton(onClick = {
                            amountText = String.format(Locale.US, "%.2f", remainingCents / 100.0)
                        }) {
                            Text("Max")
                        }
                    }

                    Button(
                        onClick = {
                            val cents = (amountText.toDoubleOrNull() ?: 0.0).let { (it * 100).toLong() }
                            if (cents > 0) {
                                entries = entries + SplitTenderEntry(method = selectedMethod, amountCents = cents)
                                amountText = ""
                            }
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .semantics { role = Role.Button },
                    ) {
                        Icon(Icons.Default.Add, contentDescription = null)
                        Spacer(modifier = Modifier.width(4.dp))
                        Text("Add $selectedMethod")
                    }
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onComplete(entries) },
                enabled = isBalanced,
            ) {
                Text("Charge")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}
