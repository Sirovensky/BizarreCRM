package com.bizarreelectronics.crm.ui.screens.warranty

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
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
import com.bizarreelectronics.crm.data.remote.api.DeviceHistoryRowDto

/**
 * §46.2 — Device history screen.
 *
 * Search by IMEI or Serial to see all past repair tickets for a device across
 * any customer. Useful for "this exact iPhone has been in 3 times" repeat-repair
 * detection.
 *
 * Accessible from:
 *  - Ticket detail → device card (via pre-filled IMEI/serial).
 *  - Customer asset tab (via pre-filled IMEI/serial).
 *  - Quick-action menu (blank search form).
 *
 * @param prefillImei    Optional IMEI to pre-fill and auto-search on launch.
 * @param prefillSerial  Optional serial to pre-fill and auto-search on launch.
 * @param onTicketClick  Navigate to the tapped ticket detail screen.
 * @param onBack         Pop this screen from the back stack.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DeviceHistoryScreen(
    prefillImei: String? = null,
    prefillSerial: String? = null,
    onTicketClick: (ticketId: Long) -> Unit,
    onBack: () -> Unit,
    viewModel: DeviceHistoryViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHost = remember { SnackbarHostState() }

    // Auto-fill + auto-search when launched from a known device context.
    LaunchedEffect(prefillImei, prefillSerial) {
        if (state.prefilledQuery == null) {
            viewModel.initWithPrefill(prefillImei, prefillSerial)
        }
    }

    LaunchedEffect(state.error) {
        val err = state.error ?: return@LaunchedEffect
        snackbarHost.showSnackbar(err)
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.screen_device_history)) },
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
                    stringResource(R.string.device_history_search_by),
                    style = MaterialTheme.typography.titleSmall,
                )
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.padding(top = 6.dp),
                ) {
                    DeviceHistoryQueryType.values().forEach { type ->
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
                                contentDescription = stringResource(R.string.device_history_search_cd),
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

            // Results header + repeat-repair banner
            if (state.rows.isNotEmpty()) {
                item {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            stringResource(R.string.device_history_results_count, state.rows.size),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        if (state.rows.size >= 3) {
                            // Repeat-repair warning
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(4.dp),
                            ) {
                                Icon(
                                    Icons.Default.History,
                                    contentDescription = stringResource(R.string.device_history_repeat_repair_cd),
                                    tint = MaterialTheme.colorScheme.error,
                                    modifier = Modifier.size(16.dp),
                                )
                                Text(
                                    stringResource(R.string.device_history_repeat_repair),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.error,
                                )
                            }
                        }
                    }
                }

                items(state.rows, key = { it.id }) { row ->
                    DeviceHistoryCard(row = row, onTicketClick = { onTicketClick(row.id) })
                }
            }

            item { Spacer(Modifier.height(24.dp)) }
        }
    }
}

// ─── History card ─────────────────────────────────────────────────────────────

@Composable
private fun DeviceHistoryCard(
    row: DeviceHistoryRowDto,
    onTicketClick: () -> Unit,
) {
    OutlinedCard(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(4.dp)) {
            ListItem(
                headlineContent = {
                    Text(
                        text = row.orderId?.let { "#$it" } ?: "#${row.id}",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                    )
                },
                supportingContent = {
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(
                            listOfNotNull(row.customerFirst, row.customerLast)
                                .joinToString(" ")
                                .ifBlank { stringResource(R.string.warranty_lookup_unknown_customer) },
                            style = MaterialTheme.typography.bodySmall,
                        )
                        row.statusName?.let {
                            Text(it, style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        row.createdAt?.let {
                            Text(
                                stringResource(R.string.device_history_created_label, it.take(10)),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                },
                trailingContent = {
                    FilledTonalButton(onClick = onTicketClick) {
                        Text(stringResource(R.string.device_history_view_ticket))
                    }
                },
            )
        }
    }
}
