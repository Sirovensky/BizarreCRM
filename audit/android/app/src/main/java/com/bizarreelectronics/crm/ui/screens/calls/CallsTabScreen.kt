package com.bizarreelectronics.crm.ui.screens.calls

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.remote.api.CallLogEntry
import com.bizarreelectronics.crm.ui.components.WaveDivider
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.util.DateFormatter

/**
 * §42 — Calls tab: lists inbound / outbound / missed call log entries.
 * Tap row → CallDetailScreen for recording playback + transcription.
 * Staff+ can initiate a new call via the FAB.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CallsTabScreen(
    onCallClick: (Long) -> Unit,
    onInitiateCall: () -> Unit,
    viewModel: CallsViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val directionFilters = listOf("All", "Inbound", "Outbound", "Missed")

    LaunchedEffect(state.actionMessage) {
        state.actionMessage?.let { snackbarHostState.showSnackbar(it); viewModel.clearActionMessage() }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        floatingActionButton = {
            if (state.canInitiateCalls) {
                FloatingActionButton(
                    onClick = onInitiateCall,
                    modifier = Modifier.semantics { contentDescription = "Initiate VoIP call" },
                ) {
                    Icon(Icons.Default.Phone, contentDescription = null)
                }
            }
        },
        topBar = {
            Column {
                BrandTopAppBar(
                    title = "Calls",
                    actions = {
                        IconButton(onClick = viewModel::refresh) {
                            Icon(Icons.Default.Refresh, contentDescription = "Refresh")
                        }
                    },
                )
                WaveDivider()
            }
        },
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {

            // Not-configured banner
            if (state.notConfigured) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                        modifier = Modifier.padding(32.dp),
                    ) {
                        Icon(Icons.Default.PhoneDisabled, contentDescription = null, modifier = Modifier.size(48.dp))
                        Text("VoIP not configured on this server", style = MaterialTheme.typography.bodyLarge)
                        Text(
                            "Contact your admin to set up voice calling.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                return@Scaffold
            }

            // Direction filter chips
            LazyRow(
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(directionFilters, key = { it }) { dir ->
                    FilterChip(
                        selected = state.directionFilter == dir,
                        onClick = { viewModel.onDirectionFilterChanged(dir) },
                        label = { Text(dir) },
                    )
                }
            }

            when {
                state.isLoading -> BrandSkeleton(rows = 6, modifier = Modifier.fillMaxSize())
                state.error != null -> Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center,
                ) {
                    ErrorState(
                        message = state.error ?: "Failed to load calls",
                        onRetry = viewModel::loadCalls,
                    )
                }
                state.calls.isEmpty() -> Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center,
                ) {
                    EmptyState(
                        icon = Icons.Default.PhoneMissed,
                        title = "No calls found",
                        subtitle = "Call history will appear here",
                    )
                }
                else -> PullToRefreshBox(
                    isRefreshing = state.isRefreshing,
                    onRefresh = viewModel::refresh,
                    modifier = Modifier.fillMaxSize(),
                ) {
                    LazyColumn(
                        contentPadding = PaddingValues(
                            start = 16.dp, end = 16.dp, top = 4.dp, bottom = 80.dp,
                        ),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        items(state.calls, key = { it.id }) { entry ->
                            CallLogRow(entry = entry, onClick = { onCallClick(entry.id) })
                        }
                    }
                }
            }
        }
    }
}

// ── Call log row ─────────────────────────────────────────────────────────────

@Composable
fun CallLogRow(entry: CallLogEntry, onClick: () -> Unit) {
    val (icon, iconTint) = when {
        entry.direction == "missed" || entry.status == "missed" ->
            Icons.Default.PhoneMissed to MaterialTheme.colorScheme.error
        entry.direction == "inbound" ->
            Icons.Default.PhoneCallback to MaterialTheme.colorScheme.primary
        else ->
            Icons.Default.PhoneForwarded to MaterialTheme.colorScheme.tertiary
    }

    BrandCard(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .semantics {
                contentDescription = buildString {
                    append("${entry.direction} call")
                    entry.customer_name?.let { append(" from $it") }
                    append(", ${formatDuration(entry.duration_seconds)}")
                }
            },
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(icon, contentDescription = null, tint = iconTint, modifier = Modifier.size(24.dp))

            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    entry.customer_name ?: entry.from_number,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    entry.from_number,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    DateFormatter.formatRelative(entry.started_at),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    formatDuration(entry.duration_seconds),
                    style = MaterialTheme.typography.bodySmall,
                    fontWeight = FontWeight.Medium,
                )
                if (entry.recording_url != null) {
                    Icon(
                        Icons.Default.Mic,
                        contentDescription = "Recording available",
                        modifier = Modifier.size(14.dp),
                        tint = MaterialTheme.colorScheme.secondary,
                    )
                }
            }
        }
    }
}

private fun formatDuration(seconds: Int): String = when {
    seconds < 60 -> "${seconds}s"
    seconds < 3600 -> "${seconds / 60}m ${seconds % 60}s"
    else -> "${seconds / 3600}h ${(seconds % 3600) / 60}m"
}
