@file:OptIn(ExperimentalMaterial3Api::class)

package com.bizarreelectronics.crm.ui.screens.devicehistory

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
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
import com.bizarreelectronics.crm.data.remote.dto.DeviceHistoryEntry
import com.bizarreelectronics.crm.ui.components.shared.BrandStatusBadge
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.util.DateFormatter

/**
 * §46.2 — Standalone Device History screen.
 *
 * Search by IMEI or serial number → displays a chronological timeline of all
 * past tickets for this device across any customer ("this iPhone has been in
 * 3 times" repeat-repair detection).
 *
 * Each row taps through to the ticket detail. Also surfaces from:
 *   - Ticket detail → device card (DeviceHistorySheet bottom sheet, unchanged)
 *   - Customer detail → asset tab (CustomerDetailScreen, unchanged)
 *
 * @param onNavigateToTicket  Navigate to a specific ticket from the timeline.
 * @param onBack              Pop this screen.
 */
@Composable
fun DeviceHistoryScreen(
    onNavigateToTicket: (ticketId: Long) -> Unit,
    onBack: () -> Unit,
    viewModel: DeviceHistoryViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Device History") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
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
                    modifier = Modifier.padding(top = 6.dp),
                ) {
                    DeviceHistoryQueryType.entries.forEach { type ->
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
            if (state.isLoading) {
                item {
                    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(modifier = Modifier.padding(16.dp))
                    }
                }
            }

            // ── Error / empty ────────────────────────────────────────────────
            state.error?.let { err ->
                item {
                    EmptyState(
                        icon = Icons.Default.History,
                        title = "No history found",
                        subtitle = err,
                        action = null,
                        includeWave = false,
                    )
                }
            }

            // ── Timeline ─────────────────────────────────────────────────────
            if (state.entries.isNotEmpty()) {
                item {
                    Text(
                        "${state.entries.size} repair(s) found for this device",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                itemsIndexed(state.entries) { index, entry ->
                    DeviceHistoryTimelineRow(
                        entry = entry,
                        isLast = index == state.entries.lastIndex,
                        onTap = { onNavigateToTicket(entry.ticketId) },
                    )
                }
                item { Spacer(Modifier.height(16.dp)) }
            }
        }
    }
}

// ─── Timeline row ─────────────────────────────────────────────────────────────

@Composable
private fun DeviceHistoryTimelineRow(
    entry: DeviceHistoryEntry,
    isLast: Boolean,
    onTap: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onTap),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Timeline stem (dot + vertical line)
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.width(20.dp),
        ) {
            Surface(
                shape = MaterialTheme.shapes.small,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(10.dp),
            ) {}
            if (!isLast) {
                Box(
                    modifier = Modifier
                        .width(2.dp)
                        .height(60.dp)
                        .padding(top = 4.dp),
                ) {
                    VerticalDivider(
                        modifier = Modifier.fillMaxHeight(),
                        color = MaterialTheme.colorScheme.outlineVariant,
                    )
                }
            }
        }

        // Content card
        Card(
            modifier = Modifier
                .weight(1f)
                .padding(bottom = if (isLast) 0.dp else 8.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
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
                        entry.orderId ?: "Ticket #${entry.ticketId}",
                        style = MaterialTheme.typography.bodySmall,
                        fontWeight = FontWeight.SemiBold,
                    )
                    if (!entry.statusName.isNullOrBlank()) {
                        BrandStatusBadge(label = entry.statusName, status = entry.statusName)
                    }
                }
                val customerDisplay = entry.displayCustomerName
                if (customerDisplay != "Unknown") {
                    Text(
                        customerDisplay,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                if (!entry.deviceName.isNullOrBlank()) {
                    Text(
                        entry.deviceName,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                if (!entry.createdAt.isNullOrBlank()) {
                    Text(
                        DateFormatter.formatAbsolute(entry.createdAt),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}
