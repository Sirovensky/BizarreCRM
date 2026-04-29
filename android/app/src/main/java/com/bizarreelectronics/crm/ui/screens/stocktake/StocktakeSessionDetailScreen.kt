package com.bizarreelectronics.crm.ui.screens.stocktake

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DeleteForever
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.remote.dto.StocktakeCount
import com.bizarreelectronics.crm.data.remote.dto.StocktakeSummary
import com.bizarreelectronics.crm.ui.components.shared.ConfirmDialog
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.SearchBar

/**
 * §6.6 Stocktake session detail — barcode scan loop + running count list.
 *
 * Loads an existing open session from [GET /stocktake/:id], shows:
 *   - Variance summary header (items counted / items-with-variance / surplus / shortage).
 *   - Running count list: each row shows item name, expected qty, counted qty, variance dot.
 *   - Search bar to add items manually.
 *   - Scan FAB → [onScanClick] (callers wire CameraX scanner result back via
 *     saved-state "stocktake_barcode").
 *   - "Commit" button → confirm dialog → [POST /stocktake/:id/commit].
 *   - On commit success, calls [onCommitted] so the nav graph can navigate to
 *     the committed result or back to the sessions list.
 *
 * If the session status is not "open" (committed / cancelled), shows a read-only
 * view with no edit actions.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StocktakeSessionDetailScreen(
    onBack: () -> Unit,
    onScanClick: () -> Unit,
    onCommitted: () -> Unit,
    /** Barcode value delivered from the scanner screen, null if none. */
    scannedBarcode: String?,
    onBarcodeConsumed: () -> Unit,
    viewModel: StocktakeSessionDetailViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    // Consume barcode from scanner
    LaunchedEffect(scannedBarcode) {
        if (!scannedBarcode.isNullOrBlank()) {
            viewModel.onBarcodeScanned(scannedBarcode)
            onBarcodeConsumed()
        }
    }

    // Show errors as snackbar
    LaunchedEffect(state.error) {
        state.error?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearError()
        }
    }

    // Navigate on commit success
    LaunchedEffect(state.committedSuccess) {
        if (state.committedSuccess) {
            viewModel.consumeCommittedSuccess()
            onCommitted()
        }
    }

    val sessionStatus = state.session?.status ?: "open"
    val isOpen = sessionStatus == "open"

    var showCommitDialog by remember { mutableStateOf(false) }

    if (showCommitDialog) {
        ConfirmDialog(
            title = "Commit Stocktake?",
            message = "This will apply all ${state.counts.size} counted item(s) to inventory. This action cannot be undone.",
            confirmLabel = "Commit",
            onConfirm = {
                showCommitDialog = false
                viewModel.commitSession()
            },
            onDismiss = { showCommitDialog = false },
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = {
                    Text(state.session?.name ?: "Stocktake")
                },
                navigationIcon = {
                    IconButton(
                        onClick = onBack,
                        modifier = Modifier.semantics { contentDescription = "Back" },
                    ) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
            )
        },
        floatingActionButton = {
            if (isOpen) {
                FloatingActionButton(
                    onClick = onScanClick,
                    containerColor = MaterialTheme.colorScheme.primaryContainer,
                    modifier = Modifier.semantics { contentDescription = "Scan barcode" },
                ) {
                    Icon(Icons.Default.QrCodeScanner, contentDescription = null)
                }
            }
        },
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = state.isLoading,
            onRefresh = { viewModel.loadSession() },
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            Column(modifier = Modifier.fillMaxSize()) {

                // ── Summary header ────────────────────────────────────────────
                if (state.session != null) {
                    SummaryHeader(
                        summary = state.summary,
                        sessionStatus = sessionStatus,
                    )
                }

                // ── Search / add item (open sessions only) ────────────────────
                if (isOpen) {
                    SearchBar(
                        query = state.searchQuery,
                        onQueryChange = { viewModel.onSearchQueryChanged(it) },
                        placeholder = "Search items to add…",
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                    )
                    if (state.searchResults.isNotEmpty()) {
                        Card(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp),
                        ) {
                            LazyColumn(modifier = Modifier.heightIn(max = 240.dp)) {
                                items(state.searchResults, key = { it.id }) { item ->
                                    val existing = state.counts.firstOrNull { c -> c.inventoryItemId == item.id }
                                    ListItem(
                                        headlineContent = { Text(item.name) },
                                        supportingContent = {
                                            Text(
                                                buildString {
                                                    item.sku?.let { append("SKU: $it") }
                                                    if (item.sku != null && item.upcCode != null) append(" · ")
                                                    item.upcCode?.let { append(it) }
                                                    if (existing != null) {
                                                        if (isNotEmpty()) append(" · ")
                                                        append("Already counted: ${existing.countedQty}")
                                                    }
                                                },
                                                style = MaterialTheme.typography.labelSmall,
                                            )
                                        },
                                        trailingContent = {
                                            FilledTonalButton(
                                                onClick = {
                                                    viewModel.upsertCount(item, (existing?.countedQty ?: 0) + 1)
                                                },
                                                enabled = !state.isUpsertingCount,
                                                modifier = Modifier.semantics {
                                                    contentDescription = "Add ${item.name} to count"
                                                },
                                            ) {
                                                Icon(
                                                    Icons.Default.Add,
                                                    contentDescription = null,
                                                    modifier = Modifier.size(16.dp),
                                                )
                                            }
                                        },
                                        modifier = Modifier.fillMaxWidth(),
                                    )
                                    HorizontalDivider()
                                }
                            }
                        }
                    }
                }

                // ── Count lines ───────────────────────────────────────────────
                if (!state.isLoading && state.counts.isEmpty()) {
                    EmptyState(
                        icon = Icons.Default.Inventory2,
                        title = if (isOpen) "No items counted yet" else "No counts recorded",
                        subtitle = if (isOpen) "Tap + to scan a barcode or search items" else "",
                    )
                } else {
                    LazyColumn(
                        modifier = Modifier.weight(1f),
                        contentPadding = PaddingValues(bottom = if (isOpen) 96.dp else 16.dp),
                    ) {
                        items(state.counts, key = { it.id }) { count ->
                            SessionCountRow(
                                count = count,
                                isEditable = isOpen,
                                onQuantityChanged = { qty ->
                                    viewModel.updateCountQty(count.inventoryItemId, qty)
                                },
                            )
                            HorizontalDivider()
                        }
                    }
                }

                // ── Commit button (open sessions with items) ──────────────────
                if (isOpen && state.counts.isNotEmpty()) {
                    Surface(
                        tonalElevation = 2.dp,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        FilledTonalButton(
                            onClick = { showCommitDialog = true },
                            enabled = !state.isCommitting && !state.isUpsertingCount,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp, vertical = 12.dp)
                                .semantics { contentDescription = "Commit stocktake count" },
                        ) {
                            if (state.isCommitting) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(18.dp),
                                    strokeWidth = 2.dp,
                                )
                                Spacer(Modifier.width(8.dp))
                            } else {
                                Icon(
                                    Icons.Default.CheckCircle,
                                    contentDescription = null,
                                    modifier = Modifier.size(18.dp),
                                )
                                Spacer(Modifier.width(8.dp))
                            }
                            Text("Commit Count (${state.counts.size} items)")
                        }
                    }
                }
            }
        }
    }
}

// ─── Variance summary header ───────────────────────────────────────────────────

@Composable
private fun SummaryHeader(
    summary: StocktakeSummary,
    sessionStatus: String,
    modifier: Modifier = Modifier,
) {
    OutlinedCard(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
        ) {
            SummaryTile(
                value = "${summary.itemsCounted}",
                label = "Counted",
            )
            SummaryTile(
                value = "${summary.itemsWithVariance}",
                label = "Variances",
                valueColor = if (summary.itemsWithVariance > 0)
                    MaterialTheme.colorScheme.error
                else
                    MaterialTheme.colorScheme.onSurface,
            )
            SummaryTile(
                value = "+${summary.surplus}",
                label = "Surplus",
                valueColor = if (summary.surplus > 0)
                    MaterialTheme.colorScheme.secondary
                else
                    MaterialTheme.colorScheme.onSurfaceVariant,
            )
            SummaryTile(
                value = "-${summary.shortage}",
                label = "Shortage",
                valueColor = if (summary.shortage > 0)
                    MaterialTheme.colorScheme.error
                else
                    MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (sessionStatus != "open") {
            Text(
                text = sessionStatus.replaceFirstChar { it.uppercase() },
                style = MaterialTheme.typography.labelSmall,
                color = when (sessionStatus) {
                    "committed" -> MaterialTheme.colorScheme.primary
                    else -> MaterialTheme.colorScheme.onSurfaceVariant
                },
                modifier = Modifier.padding(start = 16.dp, bottom = 8.dp),
            )
        }
    }
}

@Composable
private fun SummaryTile(
    value: String,
    label: String,
    valueColor: androidx.compose.ui.graphics.Color = MaterialTheme.colorScheme.onSurface,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = value,
            style = MaterialTheme.typography.titleMedium,
            color = valueColor,
        )
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

// ─── Single count line row ─────────────────────────────────────────────────────

@Composable
private fun SessionCountRow(
    count: StocktakeCount,
    isEditable: Boolean,
    onQuantityChanged: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    var qtyText by remember(count.countedQty) { mutableStateOf(count.countedQty.toString()) }

    val varianceColor = when {
        count.variance > 0 -> MaterialTheme.colorScheme.secondary
        count.variance < 0 -> MaterialTheme.colorScheme.error
        else -> MaterialTheme.colorScheme.onSurfaceVariant
    }
    val varianceText = when {
        count.variance > 0 -> "+${count.variance}"
        else -> "${count.variance}"
    }

    ListItem(
        headlineContent = {
            Text(
                count.name ?: "Item #${count.inventoryItemId}",
                style = MaterialTheme.typography.bodyMedium,
            )
        },
        supportingContent = {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                count.sku?.let { sku ->
                    Text(
                        "SKU: $sku",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Text(
                    "Expected: ${count.expectedQty}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    varianceText,
                    style = MaterialTheme.typography.labelSmall,
                    color = varianceColor,
                )
            }
        },
        trailingContent = {
            if (isEditable) {
                OutlinedTextField(
                    value = qtyText,
                    onValueChange = { text ->
                        qtyText = text
                        text.toIntOrNull()?.let { qty ->
                            if (qty >= 0 && qty != count.countedQty) onQuantityChanged(qty)
                        }
                    },
                    modifier = Modifier
                        .width(72.dp)
                        .semantics {
                            contentDescription = "Counted quantity for ${count.name ?: "item"}"
                        },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    textStyle = MaterialTheme.typography.bodyMedium,
                    label = { Text("Qty", style = MaterialTheme.typography.labelSmall) },
                )
            } else {
                Text(
                    count.countedQty.toString(),
                    style = MaterialTheme.typography.titleSmall,
                )
            }
        },
        modifier = modifier,
    )
}
