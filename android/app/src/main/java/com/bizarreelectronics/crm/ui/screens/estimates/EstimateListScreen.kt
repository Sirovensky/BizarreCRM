package com.bizarreelectronics.crm.ui.screens.estimates

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.local.db.entities.EstimateEntity
import com.bizarreelectronics.crm.ui.components.WaveDivider
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandStatusBadge
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.components.shared.SearchBar
import com.bizarreelectronics.crm.ui.screens.estimates.components.EstimateContextMenu
import com.bizarreelectronics.crm.ui.screens.estimates.components.EstimateFilterSheet
import com.bizarreelectronics.crm.ui.screens.estimates.components.EstimateFilterState
import com.bizarreelectronics.crm.ui.screens.estimates.components.EstimateStatusTabs
import com.bizarreelectronics.crm.ui.screens.estimates.components.ExpiringSoonChip
import com.bizarreelectronics.crm.ui.screens.estimates.components.isExpiringSoon
import com.bizarreelectronics.crm.util.formatAsMoney

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun EstimateListScreen(
    onEstimateClick: (Long) -> Unit,
    onCreateClick: (() -> Unit)? = null,
    viewModel: EstimateListViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val clipboardManager = LocalClipboardManager.current

    var showFilterSheet by remember { mutableStateOf(false) }
    var showBulkDeleteConfirm by remember { mutableStateOf(false) }

    // Context-menu state — which estimate is the target
    var contextMenuEstimate by remember { mutableStateOf<EstimateEntity?>(null) }

    LaunchedEffect(state.actionMessage) {
        state.actionMessage?.let { msg ->
            snackbarHostState.showSnackbar(msg)
            viewModel.clearActionMessage()
        }
    }

    if (showBulkDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { showBulkDeleteConfirm = false },
            title = { Text("Delete ${state.selectedIds.size} estimates?") },
            text = { Text("This will delete all selected estimates. This action cannot be undone.") },
            confirmButton = {
                TextButton(onClick = {
                    showBulkDeleteConfirm = false
                    viewModel.bulkDelete()
                }) { Text("Delete All", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { showBulkDeleteConfirm = false }) { Text("Cancel") }
            },
        )
    }

    // L1321 — filter sheet
    if (showFilterSheet) {
        EstimateFilterSheet(
            initial = state.activeFilters,
            onApply = { filters ->
                showFilterSheet = false
                viewModel.onFiltersApplied(filters)
            },
            onDismiss = { showFilterSheet = false },
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        floatingActionButton = {
            if (onCreateClick != null && !state.isBulkMode) {
                FloatingActionButton(onClick = onCreateClick) {
                    Icon(Icons.Default.Add, contentDescription = "Create estimate")
                }
            }
        },
        topBar = {
            Column {
                if (state.isBulkMode) {
                    // L1322 — bulk top bar
                    BulkTopBar(
                        selectedCount = state.selectedIds.size,
                        totalCount = state.estimates.size,
                        onSelectAll = { viewModel.selectAll() },
                        onClose = { viewModel.exitBulkMode() },
                    )
                } else {
                    BrandTopAppBar(
                        title = "Estimates",
                        actions = {
                            // Filter icon — highlighted when filters are active
                            IconButton(onClick = { showFilterSheet = true }) {
                                Icon(
                                    Icons.Default.FilterList,
                                    contentDescription = "Filter estimates",
                                    tint = if (state.activeFilters.isActive)
                                        MaterialTheme.colorScheme.primary
                                    else
                                        MaterialTheme.colorScheme.onSurface,
                                )
                            }
                            IconButton(onClick = { viewModel.loadEstimates() }) {
                                Icon(Icons.Default.Refresh, contentDescription = "Refresh estimates")
                            }
                        },
                    )
                }
                WaveDivider()
            }
        },
        bottomBar = {
            // L1322 — BulkActionBar
            if (state.isBulkMode) {
                EstimateBulkActionBar(
                    selectedCount = state.selectedIds.size,
                    onSend = { viewModel.bulkSend() },
                    onDelete = { showBulkDeleteConfirm = true },
                )
            }
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .imePadding(),
        ) {
            SearchBar(
                query = state.searchQuery,
                onQueryChange = { viewModel.onSearchChanged(it) },
                placeholder = "Search estimates...",
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )

            // L1320 — Status tabs (ScrollableTabRow)
            EstimateStatusTabs(
                selectedStatus = state.selectedStatus,
                onStatusSelected = { viewModel.onStatusChanged(it) },
            )

            if (!state.isLoading && state.estimates.isNotEmpty()) {
                val estimateCount = state.estimates.size
                val countLabel = "$estimateCount ${if (estimateCount == 1) "estimate" else "estimates"}"
                Text(
                    countLabel,
                    modifier = Modifier
                        .padding(horizontal = 16.dp, vertical = 4.dp)
                        .semantics {
                            liveRegion = LiveRegionMode.Polite
                            contentDescription = countLabel
                        },
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            Spacer(modifier = Modifier.height(4.dp))

            when {
                state.isLoading -> {
                    Box(
                        modifier = Modifier.semantics(mergeDescendants = true) {
                            contentDescription = "Loading estimates"
                        },
                    ) {
                        BrandSkeleton(rows = 6, modifier = Modifier.fillMaxSize())
                    }
                }
                state.error != null -> {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .semantics { liveRegion = LiveRegionMode.Assertive },
                        contentAlignment = Alignment.Center,
                    ) {
                        ErrorState(
                            message = state.error ?: "Error",
                            onRetry = { viewModel.loadEstimates() },
                        )
                    }
                }
                state.estimates.isEmpty() -> {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .semantics(mergeDescendants = true) {},
                        contentAlignment = Alignment.Center,
                    ) {
                        EmptyState(
                            icon = Icons.Default.Description,
                            title = "No estimates found",
                            subtitle = if (state.searchQuery.isNotEmpty() || state.activeFilters.isActive) {
                                "Try different search terms or clear filters"
                            } else {
                                "Estimates appear here when created from a ticket."
                            },
                        )
                    }
                }
                else -> {
                    PullToRefreshBox(
                        isRefreshing = state.isRefreshing,
                        onRefresh = { viewModel.refresh() },
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        LazyColumn(
                            contentPadding = PaddingValues(
                                start = 16.dp,
                                end = 16.dp,
                                top = 8.dp,
                                bottom = 80.dp,
                            ),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            items(state.estimates, key = { it.id }) { estimate ->
                                val isSelected = state.selectedIds.contains(estimate.id)
                                var showContextMenu by remember { mutableStateOf(false) }

                                Box {
                                    EstimateCard(
                                        estimate = estimate,
                                        isSelected = isSelected,
                                        isBulkMode = state.isBulkMode,
                                        onClick = {
                                            if (state.isBulkMode) {
                                                viewModel.toggleSelection(estimate.id)
                                            } else {
                                                onEstimateClick(estimate.id)
                                            }
                                        },
                                        onLongClick = {
                                            if (state.isBulkMode) {
                                                viewModel.toggleSelection(estimate.id)
                                            } else {
                                                showContextMenu = true
                                            }
                                        },
                                    )

                                    // L1324 — context menu
                                    EstimateContextMenu(
                                        estimateNumber = estimate.orderId.ifBlank { "EST-${estimate.id}" },
                                        expanded = showContextMenu,
                                        onDismiss = { showContextMenu = false },
                                        onOpen = { onEstimateClick(estimate.id) },
                                        onCopyNumber = {
                                            clipboardManager.setText(
                                                AnnotatedString(estimate.orderId.ifBlank { "EST-${estimate.id}" })
                                            )
                                            viewModel.clearActionMessage() // clear stale
                                        },
                                        onSend = {
                                            // route through detail for send sheet; just trigger list-level no-op
                                            onEstimateClick(estimate.id)
                                        },
                                        onApprove = {
                                            // navigate to detail to perform approve with confirm
                                            onEstimateClick(estimate.id)
                                        },
                                        onReject = {
                                            onEstimateClick(estimate.id)
                                        },
                                        onConvertToTicket = {
                                            onEstimateClick(estimate.id)
                                        },
                                        onConvertToInvoice = {
                                            onEstimateClick(estimate.id)
                                        },
                                        onDelete = {
                                            viewModel.onLongPress(estimate.id)
                                            showBulkDeleteConfirm = true
                                        },
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// ── Card ──────────────────────────────────────────────────────────────────────

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun EstimateCard(
    estimate: EstimateEntity,
    isSelected: Boolean,
    isBulkMode: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
) {
    val estimateNumber = estimate.orderId.ifBlank { "EST-${estimate.id}" }
    val a11yDesc = buildString {
        append("Estimate #$estimateNumber")
        estimate.customerName?.takeIf { it.isNotBlank() }?.let { append(" for $it") }
        append(", ${estimate.total.formatAsMoney()}")
        val statusLabel = estimate.status.replaceFirstChar { it.uppercase() }
        append(", $statusLabel")
        val dateStr = estimate.validUntil?.take(10)?.takeIf { it.isNotBlank() }
        if (dateStr != null) append(", valid until $dateStr")
        append(". Tap to open.")
    }

    // Days remaining for expiring chip
    val expiringSoon = isExpiringSoon(estimate.validUntil)
    val daysRemaining: Int = if (expiringSoon && !estimate.validUntil.isNullOrBlank()) {
        runCatching {
            val parts = estimate.validUntil.take(10).split("-")
            val cal = java.util.Calendar.getInstance()
            val today = java.util.Calendar.getInstance()
            cal.set(parts[0].toInt(), parts[1].toInt() - 1, parts[2].toInt())
            val diff = (cal.timeInMillis - today.timeInMillis) / (1000 * 60 * 60 * 24)
            diff.toInt()
        }.getOrDefault(0)
    } else 0

    BrandCard(
        modifier = Modifier
            .fillMaxWidth()
            .combinedClickable(
                onClick = onClick,
                onLongClick = onLongClick,
            )
            .semantics { contentDescription = a11yDesc },
        onClick = null, // handled by combinedClickable above
    ) {
        Row(
            modifier = Modifier
                .padding(16.dp)
                .fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // L1322 — checkbox in bulk mode
            if (isBulkMode) {
                Checkbox(
                    checked = isSelected,
                    onCheckedChange = null, // handled by card click
                    modifier = Modifier.padding(end = 8.dp),
                )
            }

            Column(modifier = Modifier.weight(1f)) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Text(
                        estimateNumber,
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    // L1323 — expiring-soon chip
                    if (expiringSoon) {
                        ExpiringSoonChip(daysRemaining = daysRemaining)
                    }
                }
                Text(
                    estimate.customerName ?: "Unknown",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                if (!estimate.validUntil.isNullOrBlank()) {
                    Text(
                        "Valid until: ${estimate.validUntil.take(10)}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Column(horizontalAlignment = Alignment.End) {
                BrandStatusBadge(
                    label = estimate.status.replaceFirstChar { it.uppercase() },
                    status = estimate.status,
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    estimate.total.formatAsMoney(),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
        }
    }
}

// ── Bulk UI components ────────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BulkTopBar(
    selectedCount: Int,
    totalCount: Int,
    onSelectAll: () -> Unit,
    onClose: () -> Unit,
) {
    TopAppBar(
        title = { Text("$selectedCount selected") },
        navigationIcon = {
            IconButton(onClick = onClose) {
                Icon(Icons.Default.Close, contentDescription = "Exit selection mode")
            }
        },
        actions = {
            TextButton(onClick = onSelectAll) {
                Text("All ($totalCount)")
            }
        },
    )
}

@Composable
private fun EstimateBulkActionBar(
    selectedCount: Int,
    onSend: () -> Unit,
    onDelete: () -> Unit,
) {
    BottomAppBar {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            OutlinedButton(
                onClick = onSend,
                modifier = Modifier.weight(1f),
                enabled = selectedCount > 0,
            ) {
                Icon(Icons.Default.Send, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(4.dp))
                Text("Send ($selectedCount)")
            }
            Button(
                onClick = onDelete,
                modifier = Modifier.weight(1f),
                enabled = selectedCount > 0,
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.error,
                ),
            ) {
                Icon(Icons.Default.Delete, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(4.dp))
                Text("Delete ($selectedCount)")
            }
        }
    }
}
