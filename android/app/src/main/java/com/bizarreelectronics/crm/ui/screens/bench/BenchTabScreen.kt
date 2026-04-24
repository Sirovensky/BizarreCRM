package com.bizarreelectronics.crm.ui.screens.bench

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.remote.dto.TicketListItem
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.screens.tickets.components.BenchTimerCard

/**
 * BenchTabScreen — §4.9 L756
 *
 * Full-screen list of the authenticated technician's active bench tickets.
 * Accessible from the Dashboard tile or as a direct nav destination.
 *
 * Each row shows:
 *  - Ticket order ID and device description.
 *  - A [BenchTimerCard] showing the elapsed bench-timer with Start/Stop.
 *  - A "Device templates" shortcut button that navigates to [Screen.DeviceTemplates].
 *
 * Tap the row body to navigate to [Screen.TicketDetail].
 *
 * Live update integration: [BenchTimerCard] already wires [LiveUpdateNotifier] on
 * timer start to post a CATEGORY_PROGRESS notification (foreground service via
 * [RepairInProgressService.start]). See BenchTimerCard KDoc for details.
 *
 * iOS parallel: same server endpoints; documented here for cross-platform reference.
 *
 * @param onBack                Navigate back (pop the back stack).
 * @param onNavigateToTicket    Open [Screen.TicketDetail] for the given ticket ID.
 * @param onNavigateToTemplates Navigate to [Screen.DeviceTemplates] settings sub-screen.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BenchTabScreen(
    onBack: () -> Unit,
    onNavigateToTicket: (Long) -> Unit,
    onNavigateToTemplates: () -> Unit,
    viewModel: BenchTabViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "My Bench",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { viewModel.loadBench() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh bench")
                    }
                },
            )
        },
    ) { padding ->
        when {
            state.isLoading -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            }

            state.offline -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    EmptyState(
                        icon = Icons.Default.Build,
                        title = "Offline",
                        subtitle = "Bench requires a server connection.",
                    )
                }
            }

            state.error != null -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    ErrorState(
                        message = state.error ?: "Failed to load bench tickets",
                        onRetry = { viewModel.loadBench() },
                    )
                }
            }

            state.tickets.isEmpty() -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    EmptyState(
                        icon = Icons.Default.Build,
                        title = "No active bench tickets",
                        subtitle = "Tickets assigned to you with status \"In Repair\" will appear here.",
                    )
                }
            }

            else -> {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentPadding = PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    items(
                        items = state.tickets,
                        key = { it.id },
                    ) { ticket ->
                        BenchTicketRow(
                            ticket = ticket,
                            onRowClick = { onNavigateToTicket(ticket.id) },
                            onTemplatesClick = onNavigateToTemplates,
                        )
                    }
                }
            }
        }
    }
}

// ─── Private composables ──────────────────────────────────────────────────────

/**
 * A single bench ticket row showing ticket metadata + elapsed timer + template shortcut.
 */
@Composable
private fun BenchTicketRow(
    ticket: TicketListItem,
    onRowClick: () -> Unit,
    onTemplatesClick: () -> Unit,
) {
    Card(
        onClick = onRowClick,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            // Ticket header: order ID + device
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "#${ticket.orderId}",
                        style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold),
                    )
                    val deviceLabel = ticket.firstDevice?.deviceName
                        ?: ticket.firstDevice?.deviceType
                        ?: "Unknown device"
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Icon(
                            Icons.Default.PhoneAndroid,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            text = deviceLabel,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    ticket.customerName.takeIf { it.isNotBlank() && it != "Unknown" }?.let { name ->
                        Text(
                            text = name,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }

                // Device templates shortcut
                TextButton(onClick = onTemplatesClick) {
                    Icon(
                        Icons.Default.Build,
                        contentDescription = null,
                        modifier = Modifier.padding(end = 4.dp),
                    )
                    Text(
                        text = "Templates",
                        style = MaterialTheme.typography.labelMedium.copy(
                            fontFamily = FontFamily.Default,
                        ),
                    )
                }
            }

            // Bench timer — wires LiveUpdateNotifier on start (see BenchTimerCard KDoc).
            // RepairInProgressService.start is called by BenchTimerCard via LiveUpdateNotifier
            // to post a CATEGORY_PROGRESS foreground notification.
            BenchTimerCard(
                ticketId = ticket.id,
                orderId = ticket.orderId,
                isRunning = false, // Server-sourced running state TBD via TicketApi.startBenchTimer
                onStart = { /* TicketApi.startBenchTimer wired in BenchTimerCard host */ },
                onStop = { /* TicketApi.stopBenchTimer wired in BenchTimerCard host */ },
            )
        }
    }
}
