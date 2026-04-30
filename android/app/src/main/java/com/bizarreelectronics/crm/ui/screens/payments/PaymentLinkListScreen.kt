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
import com.bizarreelectronics.crm.ui.components.shared.ConfirmDialog
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

            // Status filter chips (SuggestionChip per M3-Expressive: non-selectable quick-filter)
            LazyRow(
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(statusFilters, key = { it }) { status ->
                    if (state.selectedStatus == status) {
                        // Active filter: filled tonal chip to show selection
                        InputChip(
                            selected = true,
                            onClick = { viewModel.onStatusFilterChanged(status) },
                            label = { Text(status) },
                        )
                    } else {
                        SuggestionChip(
                            onClick = { viewModel.onStatusFilterChanged(status) },
                            label = { Text(status) },
                        )
                    }
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

/**
 * Pending confirmation for a destructive or sensitive action on this link.
 */
private enum class LinkPendingAction { VOID, RESEND, NONE }

@Composable
private fun PaymentLinkRow(
    link: PaymentLinkData,
    onVoid: () -> Unit,
    onResend: () -> Unit,
    onRemind: () -> Unit,
) {
    var showMenu by remember { mutableStateOf(false) }
    var pendingAction by remember { mutableStateOf(LinkPendingAction.NONE) }
    val amountDollars = "$${"%.2f".format(link.amount_cents / 100.0)}"

    // ConfirmDialog — "Cancel link" (void)
    if (pendingAction == LinkPendingAction.VOID) {
        ConfirmDialog(
            title = "Cancel payment link?",
            message = "This will void the link and the customer will no longer be able to pay. This cannot be undone.",
            confirmLabel = "Cancel link",
            onConfirm = { pendingAction = LinkPendingAction.NONE; onVoid() },
            onDismiss = { pendingAction = LinkPendingAction.NONE },
            isDestructive = true,
        )
    }

    // ConfirmDialog — "Resend" (re-send SMS/email)
    if (pendingAction == LinkPendingAction.RESEND) {
        ConfirmDialog(
            title = "Resend payment request?",
            message = "The customer will receive another SMS or email with the payment link.",
            confirmLabel = "Resend",
            onConfirm = { pendingAction = LinkPendingAction.NONE; onResend() },
            onDismiss = { pendingAction = LinkPendingAction.NONE },
            isDestructive = false,
        )
    }

    BrandCard(
        modifier = Modifier
            .fillMaxWidth()
            .semantics { contentDescription = "Payment link $amountDollars, ${link.status}" },
    ) {
        // Use M3 ListItem for headline / supporting-text layout discipline
        ListItem(
            headlineContent = {
                Text(amountDollars, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            },
            supportingContent = {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
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
            },
            leadingContent = {
                Icon(
                    Icons.Default.Link,
                    contentDescription = "Payment link",
                    tint = MaterialTheme.colorScheme.primary,
                )
            },
            trailingContent = {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    BrandStatusBadge(label = link.status.replaceFirstChar { it.uppercase() }, status = link.status)
                    Box {
                        IconButton(
                            onClick = { showMenu = true },
                            modifier = Modifier.size(32.dp),
                        ) {
                            Icon(Icons.Default.MoreVert, contentDescription = "More options for $amountDollars link")
                        }
                        DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
                            if (link.status == "pending") {
                                DropdownMenuItem(
                                    text = { Text("Resend") },
                                    onClick = { showMenu = false; pendingAction = LinkPendingAction.RESEND },
                                    leadingIcon = { Icon(Icons.Default.Send, contentDescription = "Resend link") },
                                )
                                DropdownMenuItem(
                                    text = { Text("Remind") },
                                    onClick = { showMenu = false; onRemind() },
                                    leadingIcon = { Icon(Icons.Default.Notifications, contentDescription = "Send reminder") },
                                )
                                DropdownMenuItem(
                                    text = { Text("Cancel link", color = MaterialTheme.colorScheme.error) },
                                    onClick = { showMenu = false; pendingAction = LinkPendingAction.VOID },
                                    leadingIcon = {
                                        Icon(Icons.Default.Cancel, contentDescription = "Cancel link", tint = MaterialTheme.colorScheme.error)
                                    },
                                )
                            }
                        }
                    }
                }
            },
        )
    }
}
