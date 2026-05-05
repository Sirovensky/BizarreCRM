package com.bizarreelectronics.crm.ui.screens.publictracking

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.SearchOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.data.remote.dto.PublicTicketData
import com.bizarreelectronics.crm.data.remote.dto.PublicTicketDevice
import com.bizarreelectronics.crm.data.remote.dto.PublicTicketHistoryEntry
import com.bizarreelectronics.crm.util.DateFormatter

// ---------------------------------------------------------------------------
// §55.2 — Customer-facing read-only repair status screen
//
// Reached via:
//   - App Link: https://app.bizarrecrm.com/t/:orderId?token=<trackingToken>
//   - Custom scheme: bizarrecrm://track/:orderId?token=<trackingToken>
//
// Displays ticket status, device list, and customer-visible status timeline.
// No internal data (cost, tech name, internal notes) is shown — the server
// strips those fields before returning the public response.
// ---------------------------------------------------------------------------

/**
 * Entry-point composable for the public ticket tracking screen.
 * Route: `public-tracking/{orderId}?trackingToken={trackingToken}`
 * Label: [R.string.screen_public_tracking]
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PublicTrackingScreen(
    onBack: () -> Unit,
    viewModel: PublicTrackingViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = stringResource(R.string.screen_public_tracking),
                        style = MaterialTheme.typography.titleMedium,
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.cd_navigate_back),
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                    titleContentColor = MaterialTheme.colorScheme.onSurface,
                    navigationIconContentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                ),
            )
        },
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            when (val s = state) {
                is PublicTrackingUiState.Loading -> {
                    CircularProgressIndicator(
                        modifier = Modifier.align(Alignment.Center),
                        color = MaterialTheme.colorScheme.primary,
                    )
                }

                is PublicTrackingUiState.NotFound -> {
                    PublicTrackingNotFound(modifier = Modifier.align(Alignment.Center))
                }

                is PublicTrackingUiState.Error -> {
                    PublicTrackingError(
                        message = s.message,
                        onRetry = viewModel::retry,
                        modifier = Modifier.align(Alignment.Center),
                    )
                }

                is PublicTrackingUiState.Success -> {
                    PublicTrackingContent(ticket = s.ticket)
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Content
// ---------------------------------------------------------------------------

@Composable
private fun PublicTrackingContent(ticket: PublicTicketData) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(
            horizontal = 16.dp,
            vertical = 16.dp,
        ),
    ) {
        // ── Header card: ticket # + status ──────────────────────────────
        item {
            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(
                        text = ticket.orderId ?: "",
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSurface,
                        modifier = Modifier.semantics { heading() },
                    )
                    Spacer(Modifier.height(4.dp))
                    val statusName = ticket.status?.name ?: ""
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        val isClosed = ticket.status?.isClosed == true
                        Icon(
                            imageVector = if (isClosed) Icons.Default.CheckCircle else Icons.Default.Build,
                            contentDescription = stringResource(R.string.cd_ticket_status),
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(18.dp),
                        )
                        Text(
                            text = statusName,
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    if (!ticket.customerFirstName.isNullOrBlank()) {
                        Spacer(Modifier.height(4.dp))
                        Text(
                            text = stringResource(
                                R.string.public_tracking_greeting,
                                ticket.customerFirstName,
                            ),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    if (!ticket.dueOn.isNullOrBlank()) {
                        Spacer(Modifier.height(4.dp))
                        Text(
                            text = stringResource(
                                R.string.public_tracking_eta,
                                DateFormatter.formatDate(ticket.dueOn),
                            ),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }

        // ── Devices ──────────────────────────────────────────────────────
        val devices = ticket.devices.orEmpty()
        if (devices.isNotEmpty()) {
            item {
                Text(
                    text = stringResource(R.string.public_tracking_devices_heading),
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.semantics { heading() },
                )
            }
            item {
                OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                    devices.forEachIndexed { index, device ->
                        DeviceListItem(device = device)
                        if (index < devices.lastIndex) {
                            HorizontalDivider(
                                modifier = Modifier.padding(horizontal = 16.dp),
                                color = MaterialTheme.colorScheme.outlineVariant,
                            )
                        }
                    }
                }
            }
        }

        // ── Status timeline ───────────────────────────────────────────────
        val history = ticket.history.orEmpty()
        if (history.isNotEmpty()) {
            item {
                Text(
                    text = stringResource(R.string.public_tracking_history_heading),
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.semantics { heading() },
                )
            }
            items(history) { entry ->
                HistoryEntryItem(entry = entry)
            }
        }

        // ── Store contact footer ──────────────────────────────────────────
        val store = ticket.toStoreInfo()
        if (store != null && !store.storePhone.isNullOrBlank()) {
            item {
                OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                    ListItem(
                        headlineContent = {
                            Text(
                                text = store.storeName ?: stringResource(R.string.app_name),
                                style = MaterialTheme.typography.bodyMedium,
                                fontWeight = FontWeight.SemiBold,
                            )
                        },
                        supportingContent = store.storePhone?.let { phone ->
                            { Text(text = phone, style = MaterialTheme.typography.bodySmall) }
                        },
                        leadingContent = {
                            Icon(
                                imageVector = Icons.Default.Info,
                                contentDescription = stringResource(R.string.cd_store_info),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        },
                    )
                }
            }
        }
    }
}

@Composable
private fun DeviceListItem(device: PublicTicketDevice) {
    ListItem(
        headlineContent = {
            Text(
                text = device.name ?: device.type ?: stringResource(R.string.public_tracking_device_unknown),
                style = MaterialTheme.typography.bodyMedium,
            )
        },
        supportingContent = device.status?.let { s ->
            { Text(text = s, style = MaterialTheme.typography.bodySmall) }
        },
        leadingContent = {
            Icon(
                imageVector = Icons.Default.Build,
                contentDescription = stringResource(R.string.cd_device_icon),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(20.dp),
            )
        },
    )
}

@Composable
private fun HistoryEntryItem(entry: PublicTicketHistoryEntry) {
    ListItem(
        headlineContent = {
            Text(
                text = entry.description ?: entry.action ?: "",
                style = MaterialTheme.typography.bodyMedium,
            )
        },
        supportingContent = entry.createdAt?.let { ts ->
            {
                Text(
                    text = DateFormatter.formatDateTime(ts),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
        leadingContent = {
            Icon(
                imageVector = Icons.Default.History,
                contentDescription = null, // decorative; sibling text carries the announcement
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(20.dp),
            )
        },
    )
}

// ---------------------------------------------------------------------------
// Empty / error states
// ---------------------------------------------------------------------------

@Composable
private fun PublicTrackingNotFound(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(
            imageVector = Icons.Default.SearchOff,
            contentDescription = stringResource(R.string.cd_not_found_icon),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(48.dp),
        )
        Text(
            text = stringResource(R.string.public_tracking_not_found_title),
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurface,
        )
        Text(
            text = stringResource(R.string.public_tracking_not_found_subtitle),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun PublicTrackingError(
    message: String,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(
            imageVector = Icons.Default.Error,
            contentDescription = stringResource(R.string.cd_error_icon),
            tint = MaterialTheme.colorScheme.error,
            modifier = Modifier.size(48.dp),
        )
        Text(
            text = message,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        FilledTonalButton(onClick = onRetry) {
            Text(stringResource(R.string.action_retry))
        }
    }
}
