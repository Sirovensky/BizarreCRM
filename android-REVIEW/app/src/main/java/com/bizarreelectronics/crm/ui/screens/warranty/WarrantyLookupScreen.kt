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
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.data.remote.api.WarrantyLookupRowDto
import com.bizarreelectronics.crm.ui.components.shared.ConfirmDialog

/**
 * §46.1 — Warranty lookup screen.
 *
 * ### Flow
 * 1. Search by IMEI / Serial / Phone.
 * 2. Results list: each matched record shows device, install date, expiry, active badge.
 * 3. Tap "Create warranty-return ticket" → [ConfirmDialog] → [onCreateWarrantyTicket].
 *
 * @param onCreateWarrantyTicket  Navigate to check-in pre-filled for warranty return,
 *                                carrying the [ticketId] of the source repair.
 * @param onBack                  Pop this screen from the back stack.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WarrantyLookupScreen(
    onCreateWarrantyTicket: (sourceTicketId: Long) -> Unit,
    onBack: () -> Unit,
    viewModel: WarrantyLookupViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHost = remember { SnackbarHostState() }

    LaunchedEffect(state.error) {
        val err = state.error ?: return@LaunchedEffect
        snackbarHost.showSnackbar(err)
    }

    // "Create warranty-return ticket" confirmation dialog.
    state.pendingCreateTicket?.let { row ->
        ConfirmDialog(
            title = stringResource(R.string.warranty_lookup_confirm_create_ticket_title),
            message = stringResource(
                R.string.warranty_lookup_confirm_create_ticket_msg,
                row.deviceName ?: stringResource(R.string.warranty_lookup_unknown_device),
            ),
            confirmLabel = stringResource(R.string.warranty_lookup_create_ticket_cta),
            onConfirm = {
                viewModel.dismissCreateTicket()
                onCreateWarrantyTicket(row.ticketId)
            },
            onDismiss = viewModel::dismissCreateTicket,
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.screen_warranty_lookup)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.cd_back),
                        )
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
            // Query type chips
            item {
                Spacer(Modifier.height(8.dp))
                Text(
                    stringResource(R.string.warranty_lookup_search_by),
                    style = MaterialTheme.typography.titleSmall,
                )
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.padding(top = 6.dp),
                ) {
                    WarrantyLookupQueryType.values().forEach { type ->
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
                    label = { Text(state.queryType.label) },
                    singleLine = true,
                    trailingIcon = {
                        IconButton(
                            onClick = viewModel::search,
                            enabled = state.query.isNotBlank(),
                        ) {
                            Icon(
                                Icons.Default.Search,
                                contentDescription = stringResource(R.string.warranty_lookup_search_cd),
                            )
                        }
                    },
                )
            }

            // Loading indicator
            if (state.isLoading) {
                item {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.Center,
                    ) {
                        CircularProgressIndicator()
                    }
                }
            }

            // Results header
            if (state.results.isNotEmpty()) {
                item {
                    Text(
                        stringResource(R.string.warranty_lookup_results_count, state.results.size),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }

                items(state.results, key = { it.ticketId }) { row ->
                    WarrantyLookupResultCard(
                        row = row,
                        onCreateTicket = { viewModel.requestCreateTicket(row) },
                    )
                }
            }

            item { Spacer(Modifier.height(24.dp)) }
        }
    }
}

// ─── Result card ─────────────────────────────────────────────────────────────

@Composable
private fun WarrantyLookupResultCard(
    row: WarrantyLookupRowDto,
    onCreateTicket: () -> Unit,
) {
    OutlinedCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = listOfNotNull(row.customerFirst, row.customerLast).joinToString(" ")
                        .ifBlank { stringResource(R.string.warranty_lookup_unknown_customer) },
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                WarrantyStatusChip(active = row.warrantyActive)
            }

            row.deviceName?.let {
                Text(it, style = MaterialTheme.typography.bodyMedium)
            }
            row.imei?.let {
                Text(
                    stringResource(R.string.warranty_lookup_imei_label, it),
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            row.serial?.let {
                Text(
                    stringResource(R.string.warranty_lookup_serial_label, it),
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            Text(
                stringResource(R.string.warranty_lookup_expires_label, row.warrantyExpires ?: "—"),
                style = MaterialTheme.typography.bodySmall,
                color = if (row.warrantyActive) MaterialTheme.colorScheme.onSurface
                        else MaterialTheme.colorScheme.error,
            )
            Text(
                stringResource(R.string.warranty_lookup_duration_label, row.warrantyDays),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            if (row.warrantyActive) {
                Spacer(Modifier.height(4.dp))
                FilledTonalButton(
                    onClick = onCreateTicket,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(stringResource(R.string.warranty_lookup_create_ticket_cta))
                }
            }
        }
    }
}

@Composable
private fun WarrantyStatusChip(active: Boolean) {
    val (bg, fg) = if (active) {
        MaterialTheme.colorScheme.secondaryContainer to MaterialTheme.colorScheme.onSecondaryContainer
    } else {
        MaterialTheme.colorScheme.errorContainer to MaterialTheme.colorScheme.onErrorContainer
    }
    androidx.compose.material3.Surface(
        shape = MaterialTheme.shapes.small,
        color = bg,
    ) {
        Text(
            text = if (active) stringResource(R.string.warranty_lookup_active)
                   else stringResource(R.string.warranty_lookup_expired),
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
            style = MaterialTheme.typography.labelSmall,
            color = fg,
            fontWeight = FontWeight.Medium,
        )
    }
}
