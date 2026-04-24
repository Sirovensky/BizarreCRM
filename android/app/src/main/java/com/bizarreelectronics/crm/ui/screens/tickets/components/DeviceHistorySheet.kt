@file:OptIn(ExperimentalMaterial3Api::class)

package com.bizarreelectronics.crm.ui.screens.tickets.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Build
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.dto.DeviceHistoryEntry
import com.bizarreelectronics.crm.util.DateFormatter

/**
 * "Device history" modal bottom sheet (L726).
 *
 * Displays past repairs for a device (matched by IMEI/serial from current ticket).
 * Each row is tappable → navigates to that ticket's detail screen.
 *
 * @param entries           list of past repairs from GET /tickets/device-history?imei=.
 * @param isLoading         true while the API call is in-flight.
 * @param errorMessage      non-null on network / 404 error.
 * @param onTicketTap       called with ticketId when user taps a row.
 * @param onDismiss         called when the sheet should close.
 */
@Composable
fun DeviceHistorySheet(
    entries: List<DeviceHistoryEntry>,
    isLoading: Boolean,
    errorMessage: String?,
    onTicketTap: (ticketId: Long) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(modifier = Modifier.padding(horizontal = 16.dp).padding(bottom = 24.dp)) {
            Text(
                "Device History",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(bottom = 12.dp),
            )

            when {
                isLoading -> {
                    Box(
                        modifier = Modifier.fillMaxWidth().height(120.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator()
                    }
                }
                errorMessage != null -> {
                    Text(
                        errorMessage,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                        modifier = Modifier.padding(vertical = 12.dp),
                    )
                }
                entries.isEmpty() -> {
                    Text(
                        "No prior repairs found for this device.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(vertical = 12.dp),
                    )
                }
                else -> {
                    LazyColumn(
                        modifier = Modifier.fillMaxWidth(),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        items(entries, key = { it.ticketId }) { entry ->
                            DeviceHistoryRow(entry = entry, onTap = { onTicketTap(entry.ticketId) })
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun DeviceHistoryRow(entry: DeviceHistoryEntry, onTap: () -> Unit) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onTap),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                Icons.Default.Build,
                contentDescription = null,
                modifier = Modifier.size(20.dp),
                tint = MaterialTheme.colorScheme.primary,
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    entry.orderId ?: "Ticket #${entry.ticketId}",
                    style = MaterialTheme.typography.bodySmall,
                    fontWeight = FontWeight.SemiBold,
                )
                if (!entry.customerName.isNullOrBlank()) {
                    Text(
                        entry.customerName,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                if (!entry.serviceName.isNullOrBlank()) {
                    Text(
                        entry.serviceName,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    DateFormatter.formatAbsolute(entry.createdAt),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (!entry.statusName.isNullOrBlank()) {
                    Text(
                        entry.statusName,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
            }
        }
    }
}
