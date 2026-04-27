@file:OptIn(ExperimentalMaterial3Api::class)

package com.bizarreelectronics.crm.ui.screens.warranty

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.remote.dto.WarrantyResult
import com.bizarreelectronics.crm.ui.components.shared.ConfirmDialog
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.util.DateFormatter

/**
 * §46.1 — Standalone Warranty Lookup screen.
 *
 * Search by IMEI / serial / phone / customer last name.
 * Results show device name, warranty duration, expiry, eligibility chip.
 * Tapping a record reveals a "Create warranty-return ticket" CTA that calls
 * POST /warranties/:id/claim via [WarrantyLookupViewModel].
 * Back-press with a record selected shows [ConfirmDialog] before discarding.
 *
 * @param onNavigateToTicket  Navigate to the newly created ticket after claim.
 * @param onBack              Pop this screen from the back stack.
 */
@Composable
fun WarrantyLookupScreen(
    onNavigateToTicket: (ticketId: Long) -> Unit,
    onBack: () -> Unit,
    viewModel: WarrantyLookupViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHost = remember { SnackbarHostState() }
    var showCloseConfirm by remember { mutableStateOf(false) }

    // Handle branch outcomes
    LaunchedEffect(state.claimResult) {
        val result = state.claimResult ?: return@LaunchedEffect
        when (result.branch) {
            "within", "out" -> {
                result.newTicketId?.let { onNavigateToTicket(it) }
                viewModel.clearClaimResult()
            }
            "manual" -> {
                snackbarHost.showSnackbar(result.message ?: "Manual review required — contact the manager.")
                viewModel.clearClaimResult()
            }
        }
    }
    LaunchedEffect(state.claimError) {
        val err = state.claimError ?: return@LaunchedEffect
        snackbarHost.showSnackbar(err)
    }

    if (showCloseConfirm) {
        ConfirmDialog(
            title = "Discard warranty claim?",
            message = "You have a warranty record selected. Leaving now will discard your unsaved claim.",
            confirmLabel = "Leave",
            onConfirm = {
                showCloseConfirm = false
                viewModel.clearSelection()
                onBack()
            },
            onDismiss = { showCloseConfirm = false },
            isDestructive = false,
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Warranty Lookup") },
                navigationIcon = {
                    IconButton(
                        onClick = {
                            if (state.selectedWarranty != null) showCloseConfirm = true else onBack()
                        },
                    ) {
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
            // ── Query type chips ─────────────────────────────────────────────
            item {
                Spacer(Modifier.height(8.dp))
                Text("Search by", style = MaterialTheme.typography.titleSmall)
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier
                        .padding(top = 6.dp)
                        .horizontalScroll(rememberScrollState()),
                ) {
                    WarrantyQueryType.entries.forEach { type ->
                        FilterChip(
                            selected = state.queryType == type,
                            onClick = { viewModel.onQueryTypeChange(type) },
                            label = { Text(type.label) },
                        )
                    }
                }
            }

            // ── Search field ──────────────────────────────────────────────────
            item {
                OutlinedTextField(
                    value = state.query,
                    onValueChange = viewModel::onQueryChange,
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Enter ${state.queryType.label}") },
                    singleLine = true,
                    trailingIcon = {
                        TextButton(onClick = viewModel::search) { Text("Search") }
                    },
                )
            }

            // ── Loading ──────────────────────────────────────────────────────
            if (state.isSearching) {
                item {
                    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(modifier = Modifier.padding(16.dp))
                    }
                }
            }

            // ── Error / empty ────────────────────────────────────────────────
            state.searchError?.let { err ->
                item {
                    EmptyState(
                        icon = Icons.Default.SearchOff,
                        title = "No records found",
                        subtitle = err,
                        action = null,
                        includeWave = false,
                    )
                }
            }

            // ── Results ──────────────────────────────────────────────────────
            if (state.searchResults.isNotEmpty()) {
                item {
                    Text(
                        "${state.searchResults.size} record(s) found",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                items(state.searchResults, key = { it.ticketId?.toString() ?: it.hashCode().toString() }) { warranty ->
                    WarrantyLookupCard(
                        warranty = warranty,
                        isSelected = state.selectedWarranty === warranty,
                        onSelect = { viewModel.selectWarranty(warranty) },
                    )
                }
            }

            // ── Claim section ─────────────────────────────────────────────────
            state.selectedWarranty?.let { warranty ->
                item {
                    HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
                    Text("File Warranty Claim", style = MaterialTheme.typography.titleMedium)
                    Spacer(Modifier.height(4.dp))
                    Text(
                        buildString {
                            warranty.ticketId?.let { append("Ticket #$it · ") }
                            append(warranty.customerName)
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
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
                        TextButton(
                            onClick = { showCloseConfirm = true },
                            modifier = Modifier.weight(1f),
                        ) { Text("Cancel") }
                        Button(
                            onClick = viewModel::fileClaim,
                            enabled = !state.isSubmitting && warranty.ticketId != null,
                            modifier = Modifier.weight(2f),
                        ) {
                            if (state.isSubmitting) {
                                CircularProgressIndicator(
                                    modifier = Modifier
                                        .size(16.dp)
                                        .padding(end = 8.dp),
                                    strokeWidth = 2.dp,
                                )
                            }
                            Text(
                                if (warranty.warrantyActive == true) "Create warranty-return ticket"
                                else "File paid claim",
                            )
                        }
                    }
                    Spacer(Modifier.height(24.dp))
                }
            }
        }
    }
}

// ─── Warranty lookup card ─────────────────────────────────────────────────────

@Composable
private fun WarrantyLookupCard(
    warranty: WarrantyResult,
    isSelected: Boolean,
    onSelect: () -> Unit,
) {
    val isActive = warranty.warrantyActive == true
    Card(
        onClick = onSelect,
        modifier = Modifier.fillMaxWidth(),
        border = if (isSelected) CardDefaults.outlinedCardBorder() else null,
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
                    warranty.customerName,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                WarrantyEligibilityChip(active = isActive)
            }
            if (!warranty.deviceName.isNullOrBlank()) {
                Text("Device: ${warranty.deviceName}", style = MaterialTheme.typography.bodySmall)
            }
            if (!warranty.imei.isNullOrBlank()) {
                Text("IMEI: ${warranty.imei}", style = MaterialTheme.typography.bodySmall)
            }
            if (!warranty.serial.isNullOrBlank()) {
                Text("Serial: ${warranty.serial}", style = MaterialTheme.typography.bodySmall)
            }
            warranty.warrantyDays?.let {
                Text(
                    "Duration: $it days",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (!warranty.warrantyExpires.isNullOrBlank()) {
                Text(
                    "Expires: ${DateFormatter.formatAbsolute(warranty.warrantyExpires)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = if (isActive) MaterialTheme.colorScheme.secondary
                    else MaterialTheme.colorScheme.error,
                )
            }
            if (isSelected) {
                Text(
                    "Selected — fill in notes below to file claim",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary,
                    fontWeight = FontWeight.Bold,
                )
            }
        }
    }
}

@Composable
private fun WarrantyEligibilityChip(active: Boolean) {
    val (bg, fg) = if (active) {
        MaterialTheme.colorScheme.secondary.copy(alpha = 0.14f) to MaterialTheme.colorScheme.secondary
    } else {
        MaterialTheme.colorScheme.errorContainer to MaterialTheme.colorScheme.onErrorContainer
    }
    Surface(shape = MaterialTheme.shapes.small, color = bg) {
        Text(
            text = if (active) "Under warranty" else "Out of warranty",
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
            style = MaterialTheme.typography.labelSmall,
            color = fg,
            fontWeight = FontWeight.Medium,
        )
    }
}
