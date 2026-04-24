package com.bizarreelectronics.crm.ui.screens.tickets.components

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.dto.WarrantyResult
import com.bizarreelectronics.crm.util.DateFormatter

/**
 * Overflow "Check warranty" dialog (L725).
 *
 * User enters IMEI / serial / phone → taps Lookup → server responds with
 * warranty details or 404 "No warranty record".
 *
 * @param isLoading         true while the warranty API call is in-flight.
 * @param result            last server response; null = not yet looked up.
 * @param errorMessage      non-null if the last call returned 404 or error.
 * @param onLookup          called with the query string when the user taps Lookup.
 * @param onDismiss         called when the dialog should close.
 */
@Composable
fun TicketWarrantyDialog(
    isLoading: Boolean,
    result: WarrantyResult?,
    errorMessage: String?,
    onLookup: (query: String) -> Unit,
    onDismiss: () -> Unit,
) {
    var query by rememberSaveable { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Check Warranty") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value = query,
                    onValueChange = { query = it },
                    label = { Text("IMEI / Serial / Phone") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isLoading,
                )

                when {
                    isLoading -> {
                        Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(modifier = Modifier.size(28.dp))
                        }
                    }
                    errorMessage != null -> {
                        Text(
                            errorMessage,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error,
                        )
                    }
                    result != null -> {
                        WarrantyResultCard(result)
                    }
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = { if (query.isNotBlank()) onLookup(query.trim()) },
                enabled = query.isNotBlank() && !isLoading,
            ) {
                Icon(Icons.Default.Search, contentDescription = null, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(4.dp))
                Text("Lookup")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Close") }
        },
    )
}

@Composable
private fun WarrantyResultCard(result: WarrantyResult) {
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            if (!result.deviceName.isNullOrBlank()) {
                LabeledRow("Device", result.deviceName)
            }
            if (!result.customerName.isNullOrBlank()) {
                LabeledRow("Customer", result.customerName)
            }
            if (!result.status.isNullOrBlank()) {
                LabeledRow("Status", result.status)
            }
            if (!result.purchaseDate.isNullOrBlank()) {
                LabeledRow("Purchased", DateFormatter.formatAbsolute(result.purchaseDate))
            }
            if (!result.warrantyEnd.isNullOrBlank()) {
                LabeledRow("Warranty ends", DateFormatter.formatAbsolute(result.warrantyEnd))
            }
            if (!result.lastRepairDate.isNullOrBlank()) {
                LabeledRow("Last repair", DateFormatter.formatAbsolute(result.lastRepairDate))
            }
        }
    }
}

@Composable
private fun LabeledRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            value,
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.Medium,
        )
    }
}
