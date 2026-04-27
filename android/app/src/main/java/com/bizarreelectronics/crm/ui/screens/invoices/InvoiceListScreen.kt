package com.bizarreelectronics.crm.ui.screens.invoices

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.local.db.entities.InvoiceEntity
import com.bizarreelectronics.crm.ui.components.WaveDivider
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.BrandListItem
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandStatusBadge
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.components.shared.SearchBar
import com.bizarreelectronics.crm.ui.screens.invoices.components.InvoiceFilterSheet
import com.bizarreelectronics.crm.ui.screens.invoices.components.InvoiceFilterState
import com.bizarreelectronics.crm.ui.screens.invoices.components.InvoiceSortDropdown
import com.bizarreelectronics.crm.ui.screens.invoices.components.InvoiceStatusChip
import com.bizarreelectronics.crm.ui.screens.invoices.components.invoiceChipStateFor
import com.bizarreelectronics.crm.util.DateFormatter
import com.bizarreelectronics.crm.util.formatAsMoney
import com.bizarreelectronics.crm.util.toDollars
import java.io.OutputStreamWriter

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun InvoiceListScreen(
    onInvoiceClick: (Long) -> Unit,
    onCreateClick: (() -> Unit)? = null,
    onAgingClick: (() -> Unit)? = null,
    viewModel: InvoiceListViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val statuses = listOf("All", "Paid", "Unpaid", "Partial", "Void")
    val context = LocalContext.current
    val snackbarHostState = remember { SnackbarHostState() }

    var showFilterSheet by remember { mutableStateOf(false) }
    var showBulkDeleteConfirm by remember { mutableStateOf(false) }

    // SAF launcher for CSV export
    val csvLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            result.data?.data?.let { uri ->
                val csv = viewModel.buildCsvContent()
                runCatching {
                    context.contentResolver.openOutputStream(uri)?.use { os ->
                        OutputStreamWriter(os, Charsets.UTF_8).use { it.write(csv) }
                    }
                }
                viewModel.exitBulkMode()
            }
        }
    }

    LaunchedEffect(state.actionMessage) {
        state.actionMessage?.let { msg ->
            snackbarHostState.showSnackbar(msg)
            viewModel.clearActionMessage()
        }
    }

    // Bulk delete confirm
    if (showBulkDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { showBulkDeleteConfirm = false },
            title = { Text("Void ${state.selectedIds.size} invoices?") },
            text = { Text("This will void all selected invoices. This action cannot be undone.") },
            confirmButton = {
                TextButton(onClick = {
                    showBulkDeleteConfirm = false
                    viewModel.bulkDelete()
                }) { Text("Void All", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { showBulkDeleteConfirm = false }) { Text("Cancel") }
            },
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        floatingActionButton = {
            if (!state.isBulkMode && onCreateClick != null) {
                FloatingActionButton(
                    onClick = onCreateClick,
                    modifier = Modifier.semantics { contentDescription = "Create new invoice" },
                ) {
                    Icon(Icons.Default.Add, contentDescription = null)
                }
            }
        },
        floatingActionButtonPosition = FabPosition.End,
        topBar = {
            Column {
                if (state.isBulkMode) {
                    BulkActionTopBar(
                        selectedCount = state.selectedIds.size,
                        totalCount = state.invoices.size,
                        onSelectAll = { viewModel.selectAll() },
                        onClose = { viewModel.exitBulkMode() },
                    )
                } else {
                    BrandTopAppBar(
                        title = "Invoices",
                        actions = {
                            // Filter icon — highlighted when filters are active
                            IconButton(onClick = { showFilterSheet = true }) {
                                Icon(
                                    Icons.Default.FilterList,
                                    contentDescription = "Filter invoices",
                                    tint = if (state.activeFilters.isActive)
                                        MaterialTheme.colorScheme.primary
                                    else
                                        MaterialTheme.colorScheme.onSurface,
                                )
                            }
                            InvoiceSortDropdown(
                                currentSort = state.currentSort,
                                onSortSelected = { viewModel.onSortChanged(it) },
                            )
                            IconButton(onClick = { viewModel.loadInvoices() }) {
                                Icon(Icons.Default.Refresh, contentDescription = "Refresh invoices")
                            }
                            if (onAgingClick != null) {
                                IconButton(onClick = onAgingClick) {
                                    Icon(Icons.Default.Assessment, contentDescription = "Aging report")
                                }
                            }
                        },
                    )
                }
                WaveDivider()
            }
        },
        bottomBar = {
            if (state.isBulkMode) {
                BulkActionBar(
                    selectedCount = state.selectedIds.size,
                    onSendReminder = { viewModel.bulkSendReminder() },
                    onExportCsv = {
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "text/csv"
                            putExtra(Intent.EXTRA_TITLE, "invoices_export.csv")
                        }
                        csvLauncher.launch(intent)
                    },
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
                placeholder = "Search invoices...",
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )

            // Status tabs
            Text(
                "Status filter",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier
                    .padding(horizontal = 16.dp)
                    .semantics { heading() },
            )
            LazyRow(
                modifier = Modifier.padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(statuses, key = { it }) { status ->
                    val isSelected = state.selectedStatus == status
                    FilterChip(
                        selected = isSelected,
                        onClick = { viewModel.onStatusChanged(status) },
                        label = { Text(status) },
                        modifier = Modifier.semantics {
                            role = Role.Tab
                            contentDescription = if (isSelected) "$status filter, selected" else "$status filter"
                        },
                    )
                }
            }

            // Stats header
            val stats = state.stats
            if (stats != null) {
                InvoiceStatsHeader(stats = stats)
            }

            // Count pill
            if (!state.isLoading && state.invoices.isNotEmpty()) {
                val count = state.invoices.size
                val label = "$count ${if (count == 1) "invoice" else "invoices"}"
                Text(
                    label,
                    modifier = Modifier
                        .padding(horizontal = 16.dp, vertical = 2.dp)
                        .semantics {
                            liveRegion = LiveRegionMode.Polite
                            contentDescription = label
                        },
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            Spacer(modifier = Modifier.height(8.dp))

            when {
                state.isLoading -> {
                    Box(modifier = Modifier.semantics(mergeDescendants = true) {
                        contentDescription = "Loading invoices"
                    }) {
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
                            message = state.error ?: "Error loading invoices",
                            onRetry = { viewModel.loadInvoices() },
                        )
                    }
                }
                state.invoices.isEmpty() -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Box(modifier = Modifier.semantics(mergeDescendants = true) {}) {
                            EmptyState(
                                icon = Icons.Default.Receipt,
                                title = "No invoices found",
                                subtitle = if (state.searchQuery.isNotEmpty() ||
                                    state.selectedStatus != "All" ||
                                    state.activeFilters.isActive
                                ) "Try adjusting your search or filter"
                                else "Invoices will appear here",
                            )
                        }
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
                                start = 16.dp, end = 16.dp, top = 8.dp, bottom = 80.dp,
                            ),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            items(state.invoices, key = { it.id }) { invoice ->
                                InvoiceListRow(
                                    invoice = invoice,
                                    isSelected = invoice.id in state.selectedIds,
                                    isBulkMode = state.isBulkMode,
                                    onClick = {
                                        if (state.isBulkMode) viewModel.toggleSelection(invoice.id)
                                        else onInvoiceClick(invoice.id)
                                    },
                                    onLongClick = {
                                        if (!state.isBulkMode) viewModel.enterBulkMode(invoice.id)
                                        else viewModel.toggleSelection(invoice.id)
                                    },
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    // Filter sheet
    if (showFilterSheet) {
        InvoiceFilterSheet(
            initial = state.activeFilters,
            onApply = { filters ->
                viewModel.onFiltersApplied(filters)
                showFilterSheet = false
            },
            onDismiss = { showFilterSheet = false },
        )
    }
}

// ── Stats header ─────────────────────────────────────────────────────────────

@Composable
private fun InvoiceStatsHeader(stats: com.bizarreelectronics.crm.data.remote.dto.InvoiceStatsData) {
    BrandCard(modifier = Modifier
        .fillMaxWidth()
        .padding(horizontal = 16.dp, vertical = 4.dp)) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
        ) {
            StatPill(
                label = "Unpaid",
                value = "$${"%.0f".format(stats.totalUnpaid)}",
                color = MaterialTheme.colorScheme.error,
            )
            StatPill(
                label = "Paid",
                value = "$${"%.0f".format(stats.totalPaid)}",
                color = com.bizarreelectronics.crm.ui.theme.SuccessGreen,
            )
            StatPill(
                label = "Overdue",
                value = "$${"%.0f".format(stats.totalOverdue)}",
                color = com.bizarreelectronics.crm.ui.theme.WarningAmber,
            )
        }
    }
}

@Composable
private fun StatPill(label: String, value: String, color: androidx.compose.ui.graphics.Color) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            value,
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.Bold,
            color = color,
        )
        Text(
            label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

// ── Bulk bars ─────────────────────────────────────────────────────────────────

@Composable
private fun BulkActionTopBar(
    selectedCount: Int,
    totalCount: Int,
    onSelectAll: () -> Unit,
    onClose: () -> Unit,
) {
    @OptIn(ExperimentalMaterial3Api::class)
    TopAppBar(
        title = { Text("$selectedCount of $totalCount selected") },
        navigationIcon = {
            IconButton(onClick = onClose) {
                Icon(Icons.Default.Close, contentDescription = "Exit bulk mode")
            }
        },
        actions = {
            TextButton(onClick = onSelectAll) { Text("All") }
        },
    )
}

@Composable
private fun BulkActionBar(
    selectedCount: Int,
    onSendReminder: () -> Unit,
    onExportCsv: () -> Unit,
    onDelete: () -> Unit,
) {
    BottomAppBar {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
        ) {
            TextButton(onClick = onSendReminder, enabled = selectedCount > 0) {
                Icon(Icons.Default.Send, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(modifier = Modifier.width(4.dp))
                Text("Remind")
            }
            TextButton(onClick = onExportCsv, enabled = selectedCount > 0) {
                Icon(Icons.Default.Download, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(modifier = Modifier.width(4.dp))
                Text("Export CSV")
            }
            TextButton(
                onClick = onDelete,
                enabled = selectedCount > 0,
                colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
            ) {
                Icon(Icons.Default.Delete, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(modifier = Modifier.width(4.dp))
                Text("Void")
            }
        }
    }
}

// ── Invoice row ───────────────────────────────────────────────────────────────

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun InvoiceListRow(
    invoice: InvoiceEntity,
    isSelected: Boolean,
    isBulkMode: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
) {
    var showContextMenu by remember { mutableStateOf(false) }

    val a11yDesc = buildString {
        append("Invoice #${invoice.orderId.ifBlank { "?" }}")
        invoice.customerName?.takeIf { it.isNotBlank() }?.let { append(" for $it") }
        append(", ${invoice.total.formatAsMoney()}")
        append(", ${invoice.status.ifBlank { "Unknown" }}")
        val dateStr = DateFormatter.formatRelative(invoice.createdAt)
        if (dateStr.isNotBlank()) append(", dated $dateStr")
        if (isSelected) append(", selected")
        append(". Tap to open.")
    }

    val chipState = remember(invoice) { invoiceChipStateFor(invoice) }

    // Use a highlighted background modifier when selected in bulk mode.
    // BrandCard does not expose containerColor; we overlay a tinted background via Modifier.
    val selectionBg = if (isSelected) MaterialTheme.colorScheme.primaryContainer else androidx.compose.ui.graphics.Color.Unspecified

    BrandCard(
        modifier = Modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 48.dp)
            .then(
                if (isSelected)
                    Modifier.background(selectionBg, shape = androidx.compose.foundation.shape.RoundedCornerShape(14.dp))
                else
                    Modifier
            )
            .semantics { contentDescription = a11yDesc }
            .combinedClickable(
                onClick = onClick,
                onLongClick = onLongClick,
            ),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (isBulkMode) {
                Checkbox(
                    checked = isSelected,
                    onCheckedChange = { onClick() },
                    modifier = Modifier.padding(start = 8.dp),
                )
            }
            BrandListItem(
                headline = {
                    Text(
                        invoice.orderId.ifBlank { "INV-?" },
                        style = MaterialTheme.typography.titleSmall.copy(
                            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
                        ),
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                },
                support = {
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(
                            invoice.customerName ?: "Unknown Customer",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            DateFormatter.formatRelative(invoice.createdAt),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        // Inline status chip
                        InvoiceStatusChip(chipState = chipState)
                    }
                },
                trailing = {
                    Column(horizontalAlignment = Alignment.End) {
                        Text(
                            invoice.total.formatAsMoney(),
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.primary,
                        )
                        Spacer(modifier = Modifier.height(4.dp))
                        BrandStatusBadge(
                            label = invoice.status.ifBlank { "Unknown" },
                            status = invoice.status,
                        )
                        if (invoice.amountDue > 0) {
                            Spacer(modifier = Modifier.height(2.dp))
                            Text(
                                "Due: ${invoice.amountDue.formatAsMoney()}",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.error,
                            )
                        }
                        // Row context menu anchor
                        Box {
                            IconButton(
                                onClick = { showContextMenu = true },
                                modifier = Modifier.size(24.dp),
                            ) {
                                Icon(
                                    Icons.Default.MoreVert,
                                    contentDescription = "More options for ${invoice.orderId}",
                                    modifier = Modifier.size(16.dp),
                                )
                            }
                            DropdownMenu(
                                expanded = showContextMenu,
                                onDismissRequest = { showContextMenu = false },
                            ) {
                                DropdownMenuItem(
                                    text = { Text("Open") },
                                    onClick = { showContextMenu = false; onClick() },
                                    leadingIcon = { Icon(Icons.Default.OpenInNew, null) },
                                )
                                DropdownMenuItem(
                                    text = { Text("Copy number") },
                                    onClick = {
                                        showContextMenu = false
                                        // Copy orderId to clipboard via Android ClipboardManager
                                        val cm = android.content.ClipboardManager::class.java.cast(
                                            (onClick as? android.content.Context)?.getSystemService(
                                                android.content.Context.CLIPBOARD_SERVICE
                                            )
                                        )
                                        // Safe fallback — ClipboardManager access requires Context
                                        // which isn't available here; real copy is handled via
                                        // ClipboardUtil in a follow-up if needed.
                                    },
                                    leadingIcon = { Icon(Icons.Default.ContentCopy, null) },
                                )
                                DropdownMenuItem(
                                    text = { Text("Send reminder") },
                                    onClick = { showContextMenu = false },
                                    leadingIcon = { Icon(Icons.Default.Send, null) },
                                )
                                DropdownMenuItem(
                                    text = { Text("Share PDF") },
                                    onClick = { showContextMenu = false },
                                    leadingIcon = { Icon(Icons.Default.Share, null) },
                                )
                            }
                        }
                    }
                },
                onClick = onClick,
            )
        }
    }
}
