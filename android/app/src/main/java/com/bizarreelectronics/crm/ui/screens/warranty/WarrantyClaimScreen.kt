package com.bizarreelectronics.crm.ui.screens.warranty

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.remote.api.WarrantyRecordDto

/**
 * §4.18 L812-L822 — Warranty Claim screen.
 *
 * ### Flow
 * 1. Search form: user selects query type (IMEI / Receipt / Name) and enters value.
 * 2. Results list: each matched warranty shows install date, duration, eligibility chip.
 * 3. Select a record → "File claim" button appears.
 * 4. On submit: server returns branch decision:
 *    - "within"  → [onNavigateToTicket] called with the new zero-price warranty return ticket id.
 *    - "out"     → [onNavigateToTicket] called with the new paid repair ticket id.
 *    - "manual"  → snackbar with the server's next-steps message.
 *
 * ### Auto-SMS
 * The server fires an SMS confirmation automatically; no client action needed.
 *
 * @param onNavigateToTicket  Navigate to the new ticket created by the server.
 * @param onBack              Pop this screen from the back stack.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WarrantyClaimScreen(
    onNavigateToTicket: (ticketId: Long) -> Unit,
    onBack: () -> Unit,
    viewModel: WarrantyClaimViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHost = remember { SnackbarHostState() }

    // Handle branch outcomes
    LaunchedEffect(state.claimResult) {
        val result = state.claimResult ?: return@LaunchedEffect
        when (result.branch) {
            "within", "out" -> {
                result.newTicketId?.let { onNavigateToTicket(it) }
                viewModel.clearClaimResult()
            }
            "manual" -> {
                snackbarHost.showSnackbar(
                    result.message ?: "Manual review required — contact the manager."
                )
                viewModel.clearClaimResult()
            }
        }
    }

    LaunchedEffect(state.claimError) {
        val err = state.claimError ?: return@LaunchedEffect
        snackbarHost.showSnackbar(err)
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Warranty Claim") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHost) },
    ) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // Query type selector
            item {
                Spacer(Modifier.height(8.dp))
                Text("Search by", style = MaterialTheme.typography.titleSmall)
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.padding(top = 6.dp),
                ) {
                    QueryType.values().forEach { type ->
                        FilterChip(
                            selected = state.queryType == type,
                            onClick = { viewModel.onQueryTypeChange(type) },
                            label = { Text(type.label) },
                        )
                    }
                }
            }

            // Search field
            item {
                OutlinedTextField(
                    value = state.query,
                    onValueChange = viewModel::onQueryChange,
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Enter ${state.queryType.label}") },
                    singleLine = true,
                    trailingIcon = {
                        TextButton(onClick = viewModel::search) {
                            Text("Search")
                        }
                    },
                )
            }

            // Loading
            if (state.isSearching) {
                item {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.Center,
                    ) {
                        CircularProgressIndicator()
                    }
                }
            }

            // Error
            state.searchError?.let { err ->
                item {
                    Text(err, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                }
            }

            // Results
            if (state.searchResults.isNotEmpty()) {
                item {
                    Text(
                        "${state.searchResults.size} record(s) found",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                items(state.searchResults, key = { it.id }) { warranty ->
                    WarrantyResultCard(
                        warranty = warranty,
                        isSelected = state.selectedWarranty?.id == warranty.id,
                        onSelect = { viewModel.selectWarranty(warranty) },
                    )
                }
            }

            // Claim section — shown when a record is selected
            state.selectedWarranty?.let { warranty ->
                item {
                    HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
                    Text("File Claim", style = MaterialTheme.typography.titleMedium)
                }
                item {
                    OutlinedTextField(
                        value = state.claimNotes,
                        onValueChange = viewModel::onClaimNotesChange,
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("Notes (optional)") },
                        minLines = 2,
                        maxLines = 4,
                    )
                }
                item {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        TextButton(onClick = viewModel::clearSelection, modifier = Modifier.weight(1f)) {
                            Text("Cancel")
                        }
                        Button(
                            onClick = viewModel::fileClaim,
                            enabled = !state.isSubmitting,
                            modifier = Modifier.weight(2f),
                        ) {
                            if (state.isSubmitting) {
                                CircularProgressIndicator(
                                    modifier = Modifier.padding(end = 8.dp),
                                    strokeWidth = 2.dp,
                                )
                            }
                            Text(if (warranty.eligible) "File Warranty Claim" else "File Paid Claim")
                        }
                    }
                    Spacer(Modifier.height(24.dp))
                }
            }
        }
    }
}

// ─── Result card ─────────────────────────────────────────────────────────────

@Composable
private fun WarrantyResultCard(
    warranty: WarrantyRecordDto,
    isSelected: Boolean,
    onSelect: () -> Unit,
) {
    Card(
        onClick = onSelect,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = warranty.customerName ?: "Unknown customer",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                EligibilityChip(eligible = warranty.eligible)
            }

            warranty.serial?.let {
                Text("Serial: $it", style = MaterialTheme.typography.bodySmall)
            }
            warranty.imei?.let {
                Text("IMEI: $it", style = MaterialTheme.typography.bodySmall)
            }
            Text(
                "Installed: ${warranty.installDate ?: "—"}",
                style = MaterialTheme.typography.bodySmall,
            )
            Text(
                "Duration: ${warranty.duration}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (isSelected) {
                Text(
                    "Selected",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary,
                    fontWeight = FontWeight.Bold,
                )
            }
        }
    }
}

@Composable
private fun EligibilityChip(eligible: Boolean) {
    val (bg, fg) = if (eligible) {
        MaterialTheme.colorScheme.secondary.copy(alpha = 0.14f) to MaterialTheme.colorScheme.secondary
    } else {
        MaterialTheme.colorScheme.errorContainer to MaterialTheme.colorScheme.onErrorContainer
    }
    Surface(shape = MaterialTheme.shapes.small, color = bg) {
        Text(
            text = if (eligible) "Eligible" else "Out of warranty",
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
            style = MaterialTheme.typography.labelSmall,
            color = fg,
            fontWeight = FontWeight.Medium,
        )
    }
}
