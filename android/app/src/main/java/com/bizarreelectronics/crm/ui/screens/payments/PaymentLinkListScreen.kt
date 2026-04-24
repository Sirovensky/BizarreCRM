package com.bizarreelectronics.crm.ui.screens.payments

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
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.remote.api.PaymentLinkData
import com.bizarreelectronics.crm.ui.components.WaveDivider
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandStatusBadge
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.util.DateFormatter

/**
 * §41.2 — List existing payment links with status {Pending / Paid / Expired}.
 * Tap row → detail actions: Void, Remind, Resend.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PaymentLinkListScreen(
    onCreateClick: () -> Unit,
    viewModel: PaymentLinkViewModel = hiltViewModel(),
) {
    val state by viewModel.listState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val statusFilters = listOf("All", "Pending", "Paid", "Expired", "Cancelled")

    LaunchedEffect(state.actionMessage) {
        state.actionMessage?.let { snackbarHostState.showSnackbar(it); viewModel.clearActionMessage() }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        floatingActionButton = {
            FloatingActionButton(
                onClick = onCreateClick,
                modifier = Modifier.semantics { contentDescription = "Create new payment link" },
            ) {
                Icon(Icons.Default.Add, contentDescription = null)
            }
        },
        topBar = {
            Column {
                BrandTopAppBar(
                    title = "Payment Links",
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
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            if (state.notConfigured) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                        modifier = Modifier.padding(32.dp),
                    ) {
                        Icon(Icons.Default.LinkOff, contentDescription = null, modifier = Modifier.size(48.dp))
                        Text("Payment links not configured on this server")
                    }
                }
                return@Scaffold
            }

            // Status filter chips
            LazyRow(
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(statusFilters, key = { it }) { status ->
                    FilterChip(
                        selected = state.selectedStatus == status,
                        onClick = { viewModel.onStatusFilterChanged(status) },
                        label = { Text(status) },
                    )
                }
            }

            when {
                state.isLoading -> BrandSkeleton(rows = 5, modifier = Modifier.fillMaxSize())
                state.error != null -> Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center,
                ) {
                    ErrorState(
                        message = state.error ?: "Failed to load payment links",
                        onRetry = viewModel::loadLinks,
                    )
                }
                state.links.isEmpty() -> Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center,
                ) {
                    EmptyState(
                        icon = Icons.Default.Link,
                        title = "No payment links",
                        subtitle = "Tap + to create one",
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
                        items(state.links, key = { it.id }) { link ->
                            PaymentLinkRow(
                                link = link,
                                onVoid = { viewModel.voidLink(link.id) },
                                onResend = { viewModel.resendLink(link.id) },
                                onRemind = { viewModel.remindCustomer(link.id) },
                            )
                        }
                    }
                }
            }
        }
    }
}

// ── Row ───────────────────────────────────────────────────────────────────────

@Composable
private fun PaymentLinkRow(
    link: PaymentLinkData,
    onVoid: () -> Unit,
    onResend: () -> Unit,
    onRemind: () -> Unit,
) {
    var showMenu by remember { mutableStateOf(false) }
    val amountDollars = "$${"%.2f".format(link.amount_cents / 100.0)}"

    BrandCard(
        modifier = Modifier
            .fillMaxWidth()
            .semantics { contentDescription = "Payment link $amountDollars, ${link.status}" },
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(amountDollars, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                link.memo?.takeIf { it.isNotBlank() }?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                link.customer_name?.takeIf { it.isNotBlank() }?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall)
                }
                Text(
                    DateFormatter.formatRelative(link.created_at),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                BrandStatusBadge(label = link.status.replaceFirstChar { it.uppercase() }, status = link.status)

                Box {
                    IconButton(onClick = { showMenu = true }, modifier = Modifier.size(24.dp)) {
                        Icon(Icons.Default.MoreVert, contentDescription = "More options", modifier = Modifier.size(16.dp))
                    }
                    DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
                        if (link.status == "pending") {
                            DropdownMenuItem(
                                text = { Text("Resend") },
                                onClick = { showMenu = false; onResend() },
                                leadingIcon = { Icon(Icons.Default.Send, null) },
                            )
                            DropdownMenuItem(
                                text = { Text("Remind") },
                                onClick = { showMenu = false; onRemind() },
                                leadingIcon = { Icon(Icons.Default.Notifications, null) },
                            )
                            DropdownMenuItem(
                                text = { Text("Void", color = MaterialTheme.colorScheme.error) },
                                onClick = { showMenu = false; onVoid() },
                                leadingIcon = { Icon(Icons.Default.Cancel, null, tint = MaterialTheme.colorScheme.error) },
                            )
                        }
                    }
                }
            }
        }
    }
}
