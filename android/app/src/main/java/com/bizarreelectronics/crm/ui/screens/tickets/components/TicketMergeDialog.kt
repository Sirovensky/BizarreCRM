package com.bizarreelectronics.crm.ui.screens.tickets.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MergeType
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/**
 * Represents a candidate ticket for merge.
 */
data class MergeCandidate(
    val id: Long,
    val orderId: String,
    val customerName: String,
    val statusName: String?,
)

/**
 * L721 — Merge tickets dialog.
 *
 * Presents a search box so the user can find a duplicate candidate by order ID
 * or customer name. Once a candidate is selected, Merge is enabled. The server
 * call [onConfirm] receives (keepId=current ticket, mergeId=selected candidate).
 *
 * The server merges notes, photos, and devices from [mergeId] into [keepId]
 * and soft-deletes [mergeId].
 *
 * [candidates] — filtered list supplied by the ViewModel (debounced search).
 * [isSearching]  — true while the ViewModel is fetching candidates.
 */
@Composable
fun TicketMergeDialog(
    keepOrderId: String,
    candidates: List<MergeCandidate>,
    isSearching: Boolean,
    onQueryChange: (String) -> Unit,
    onConfirm: (mergeId: Long) -> Unit,
    onDismiss: () -> Unit,
) {
    var query by remember { mutableStateOf("") }
    var selectedCandidate by remember { mutableStateOf<MergeCandidate?>(null) }

    AlertDialog(
        onDismissRequest = onDismiss,
        icon = {
            Icon(Icons.Default.MergeType, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
        },
        title = { Text("Merge into $keepOrderId") },
        text = {
            Column(modifier = Modifier.fillMaxWidth()) {
                Text(
                    "Search for a duplicate ticket to merge. Its notes, photos, and devices " +
                        "will be moved into this ticket and the other ticket will be deleted.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(modifier = Modifier.height(12.dp))
                OutlinedTextField(
                    value = query,
                    onValueChange = {
                        query = it
                        onQueryChange(it)
                    },
                    label = { Text("Search by order ID or customer") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                )
                Spacer(modifier = Modifier.height(8.dp))
                when {
                    isSearching -> {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            CircularProgressIndicator(modifier = Modifier.padding(end = 8.dp))
                            Text("Searching…", style = MaterialTheme.typography.bodySmall)
                        }
                    }
                    candidates.isEmpty() && query.isNotBlank() -> {
                        Text(
                            "No matching tickets found.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(vertical = 8.dp),
                        )
                    }
                    else -> {
                        LazyColumn(modifier = Modifier.fillMaxWidth()) {
                            items(candidates, key = { it.id }) { candidate ->
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clickable { selectedCandidate = candidate }
                                        .padding(vertical = 4.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    RadioButton(
                                        selected = selectedCandidate?.id == candidate.id,
                                        onClick = { selectedCandidate = candidate },
                                    )
                                    Column(modifier = Modifier.padding(start = 4.dp)) {
                                        Text(
                                            candidate.orderId,
                                            style = MaterialTheme.typography.bodyMedium,
                                            fontWeight = FontWeight.Medium,
                                        )
                                        Text(
                                            "${candidate.customerName}${candidate.statusName?.let { " · $it" } ?: ""}",
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    }
                                }
                                HorizontalDivider()
                            }
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    selectedCandidate?.let { onConfirm(it.id) }
                },
                enabled = selectedCandidate != null,
            ) {
                Text("Merge")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        },
    )
}
