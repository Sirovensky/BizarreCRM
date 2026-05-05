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
    val isActive = result.warrantyActive == true
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    result.customerName,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                Surface(
                    shape = MaterialTheme.shapes.small,
                    color = if (isActive)
                        MaterialTheme.colorScheme.secondary.copy(alpha = 0.14f)
                    else MaterialTheme.colorScheme.errorContainer,
                ) {
                    Text(
                        if (isActive) "Under warranty" else "Expired",
                        modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                        style = MaterialTheme.typography.labelSmall,
                        color = if (isActive) MaterialTheme.colorScheme.secondary
                        else MaterialTheme.colorScheme.onErrorContainer,
                        fontWeight = FontWeight.Medium,
                    )
                }
            }
            if (!result.deviceName.isNullOrBlank()) LabeledRow("Device", result.deviceName)
            if (!result.imei.isNullOrBlank()) LabeledRow("IMEI", result.imei)
            if (!result.serial.isNullOrBlank()) LabeledRow("Serial", result.serial)
            if (!result.statusName.isNullOrBlank()) LabeledRow("Status", result.statusName)
            result.warrantyDays?.let { LabeledRow("Duration", "$it days") }
            if (!result.warrantyExpires.isNullOrBlank()) LabeledRow("Expires", DateFormatter.formatAbsolute(result.warrantyExpires))
            result.ticketId?.let { LabeledRow("Ticket", "#$it") }
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
