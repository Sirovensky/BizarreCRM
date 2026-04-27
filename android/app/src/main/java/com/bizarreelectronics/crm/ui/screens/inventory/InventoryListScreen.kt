package com.bizarreelectronics.crm.ui.screens.inventory

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.invisibleToUser
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import kotlinx.coroutines.delay
import com.bizarreelectronics.crm.ui.components.shared.BrandListItem
import com.bizarreelectronics.crm.ui.components.shared.BrandListItemDivider
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.components.shared.SearchBar
import com.bizarreelectronics.crm.ui.screens.inventory.components.InventoryColumn
import com.bizarreelectronics.crm.ui.screens.inventory.components.InventoryColumnsPickerSheet
import com.bizarreelectronics.crm.ui.screens.inventory.components.InventoryContextMenu
import com.bizarreelectronics.crm.ui.screens.inventory.components.InventoryFilter
import com.bizarreelectronics.crm.ui.screens.inventory.components.InventoryFilterSheet
import com.bizarreelectronics.crm.ui.screens.inventory.components.InventorySort
import com.bizarreelectronics.crm.ui.screens.inventory.components.InventorySortDropdown
import com.bizarreelectronics.crm.ui.screens.inventory.components.InventoryStockBadge
import com.bizarreelectronics.crm.ui.screens.inventory.components.QuickStockAdjust
import com.bizarreelectronics.crm.ui.screens.inventory.components.loadInventoryColumns
import com.bizarreelectronics.crm.ui.theme.*
import com.bizarreelectronics.crm.data.local.db.entities.InventoryItemEntity
import com.bizarreelectronics.crm.data.local.db.entities.costPrice
import com.bizarreelectronics.crm.data.local.db.entities.retailPrice
import com.bizarreelectronics.crm.util.CurrencyFormatter
import com.bizarreelectronics.crm.util.isMediumOrExpandedWidth

// ─── Role-gating stub ──────────────────────────────────────────────────────
// TODO(role-gate): Session.currentUserRole is not yet exposed as a ViewModel
// observable. Until that API lands, cost price is hidden by this local stub
// which defaults to non-admin (safest default). Replace with real session
// role read (e.g. from AuthViewModel / SessionManager) once the Session
// compositionLocal or StateFlow is available.
private val LocalIsAdmin = androidx.compose.runtime.staticCompositionLocalOf { false }

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun InventoryListScreen(
    onItemClick: (Long) -> Unit,
    onScanClick: () -> Unit,
    onAddClick: () -> Unit = {},
    scannedBarcode: String? = null,
    onBarcodeLookupResult: (Long) -> Unit = {},
    onBarcodeLookupConsumed: () -> Unit = {},
    viewModel: InventoryListViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val types = listOf("All", "Product", "Part")
    val snackbarHostState = remember { SnackbarHostState() }
    val isAdmin = LocalIsAdmin.current
    val isTablet = isMediumOrExpandedWidth()
    val clipboardManager = LocalClipboardManager.current

    var showFilterSheet by remember { mutableStateOf(false) }
    // §6.1: tablet column picker state (persisted via SharedPreferences)
    val context = androidx.compose.ui.platform.LocalContext.current
    var visibleColumns by remember {
        mutableStateOf(loadInventoryColumns(context))
    }
    var showColumnsPicker by remember { mutableStateOf(false) }

    // §6.5: HID-scanner support — hidden focused BasicTextField captures rapid
    // keystrokes from an external Bluetooth scanner operating in HID keyboard
    // mode. The scanner sends characters with intra-key interval < 50 ms and
    // terminates with Enter (KeyEvent.KEYCODE_ENTER / '\n'). We accumulate the
    // buffer and submit when we see a newline. Regular keyboard typing is
    // filtered out by the 50 ms threshold: human key repeat is typically > 80 ms.
    var hidBuffer by remember { mutableStateOf(TextFieldValue("")) }
    var hidLastCharMs by remember { mutableStateOf(0L) }
    val hidFocusRequester = remember { FocusRequester() }

    // Re-request focus on the hidden field whenever we're back on the list screen
    // so the scanner can always inject input without user interaction.
    LaunchedEffect(Unit) {
        // Delay slightly to let the Scaffold settle before requesting focus.
        kotlinx.coroutines.delay(300)
        try { hidFocusRequester.requestFocus() } catch (_: Exception) { /* safe to ignore */ }
    }

    // Trigger barcode lookup when a scanned barcode arrives
    LaunchedEffect(scannedBarcode) {
        if (scannedBarcode != null) {
            viewModel.lookupBarcode(scannedBarcode)
        }
    }

    // Navigate to detail when lookup succeeds
    LaunchedEffect(state.barcodeLookupId) {
        val id = state.barcodeLookupId ?: return@LaunchedEffect
        viewModel.clearBarcodeLookup()
        onBarcodeLookupConsumed()
        onBarcodeLookupResult(id)
    }

    // Show error snackbar when lookup fails
    LaunchedEffect(state.barcodeLookupError) {
        val error = state.barcodeLookupError ?: return@LaunchedEffect
        snackbarHostState.showSnackbar(error)
        viewModel.clearBarcodeLookup()
        onBarcodeLookupConsumed()
    }

    if (showFilterSheet) {
        InventoryFilterSheet(
            current = state.currentFilter,
            onApply = { filter ->
                viewModel.onFilterChanged(filter)
                showFilterSheet = false
            },
            onDismiss = { showFilterSheet = false },
        )
    }

    // §6.1: Columns picker sheet — tablet/ChromeOS only
    if (showColumnsPicker && isTablet) {
        InventoryColumnsPickerSheet(
            visibleColumns = visibleColumns,
            onColumnsChanged = { updated -> visibleColumns = updated },
            onDismiss = { showColumnsPicker = false },
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        floatingActionButton = {
            // Hide FAB during bulk selection to avoid accidental add
            if (!state.isSelectionMode) {
                FloatingActionButton(
                    onClick = onAddClick,
                    containerColor = MaterialTheme.colorScheme.primary,
                    contentColor = MaterialTheme.colorScheme.onPrimary,
                ) {
                    Icon(Icons.Default.Add, contentDescription = "Add inventory item")
                }
            }
        },
        topBar = {
            BrandTopAppBar(
                title = "Inventory",
                actions = {
                    // Filter icon with badge showing active filter count
                    val filterCount = state.currentFilter.activeCount
                    BadgedBox(
                        badge = {
                            if (filterCount > 0) {
                                Badge { Text("$filterCount") }
                            }
                        },
                    ) {
                        IconButton(onClick = { showFilterSheet = true }) {
                            Icon(
                                Icons.Default.FilterList,
                                contentDescription = "Filter inventory" +
                                    if (filterCount > 0) " ($filterCount active)" else "",
                            )
                        }
                    }
                    // Sort dropdown
                    InventorySortDropdown(
                        currentSort = state.currentSort,
                        onSortSelected = { viewModel.onSortChanged(it) },
                    )
                    // §6.1: Column picker icon — tablet/ChromeOS only
                    if (isTablet) {
                        IconButton(onClick = { showColumnsPicker = true }) {
                            Icon(Icons.Default.ViewColumn, contentDescription = "Choose visible columns")
                        }
                    }
                    IconButton(onClick = onScanClick) {
                        Icon(Icons.Default.QrCodeScanner, contentDescription = "Scan barcode to find item")
                    }
                    IconButton(onClick = { viewModel.loadItems() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh inventory")
                    }
                },
            )
        },
        // Bulk-action bar docked at bottom when in selection mode (tablet-gated)
        bottomBar = {
            if (state.isSelectionMode && isTablet) {
                BulkActionBar(
                    selectedCount = state.selectedIds.size,
                    onBulkAdjust = { /* TODO: open bulk-adjust sheet */ },
                    onBulkExport = { /* TODO: export CSV */ },
                    onDelete = { /* TODO: confirm + delete */ },
                    onClearSelection = { viewModel.clearSelection() },
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
            // §6.5: HID-scanner hidden field — zero-size, invisible to a11y.
            // External Bluetooth scanner (HID keyboard mode) injects characters
            // here; rapid bursts (< 50 ms inter-char) + newline → barcode lookup.
            BasicTextField(
                value = hidBuffer,
                onValueChange = { newVal ->
                    val nowMs = System.currentTimeMillis()
                    val deltaMs = nowMs - hidLastCharMs
                    hidLastCharMs = nowMs

                    val newText = newVal.text
                    if (newText.endsWith("\n")) {
                        // Newline = scanner terminator → submit
                        val barcode = newText.trimEnd('\n').trim()
                        if (barcode.isNotBlank()) {
                            viewModel.lookupBarcode(barcode)
                        }
                        hidBuffer = TextFieldValue("")
                    } else if (deltaMs < 50 || hidBuffer.text.isNotEmpty()) {
                        // Fast typing (< 50 ms) OR already buffering → accumulate
                        hidBuffer = newVal
                    } else {
                        // Slow typing (human) → discard so the hidden field stays empty
                        hidBuffer = TextFieldValue("")
                    }
                },
                modifier = Modifier
                    .size(0.dp)
                    .focusRequester(hidFocusRequester)
                    .semantics { invisibleToUser() },
                textStyle = TextStyle(fontSize = 0.sp),
            )

            SearchBar(
                query = state.searchQuery,
                onQueryChange = { viewModel.onSearchChanged(it) },
                placeholder = "Name, SKU, UPC, category…",
                modifier = Modifier
                    .padding(horizontal = 16.dp, vertical = 8.dp)
                    .semantics { contentDescription = "Search inventory" },
            )

            Text(
                "Type filter",
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
                items(types, key = { it }) { type ->
                    val isSelected = state.selectedType == type
                    FilterChip(
                        selected = isSelected,
                        onClick = { viewModel.onTypeChanged(type) },
                        label = { Text(type) },
                        modifier = Modifier.semantics {
                            role = Role.Tab
                            contentDescription = if (isSelected) "$type tab, selected" else "$type tab, not selected"
                        },
                    )
                }
            }

            Spacer(modifier = Modifier.height(8.dp))

            when {
                state.isLoading -> {
                    Box(
                        modifier = Modifier.semantics(mergeDescendants = true) {
                            contentDescription = "Loading inventory"
                        },
                    ) {
                        BrandSkeleton(rows = 6, modifier = Modifier.padding(top = 8.dp))
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
                            message = state.error ?: "Failed to load inventory.",
                            onRetry = { viewModel.loadItems() },
                        )
                    }
                }

                state.items.isEmpty() -> {
                    // §6.1 L1067 — filter-aware empty state
                    val hasActiveFilter = state.currentFilter != InventoryFilter.Empty ||
                        state.searchQuery.isNotEmpty()
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .semantics(mergeDescendants = true) {},
                        contentAlignment = Alignment.Center,
                    ) {
                        if (hasActiveFilter) {
                            EmptyState(
                                icon = Icons.Default.SearchOff,
                                title = "No items match",
                                subtitle = "No items match these filters. Adjust filters or import items.",
                                action = {
                                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                        OutlinedButton(
                                            onClick = {
                                                viewModel.onFilterChanged(InventoryFilter.Empty)
                                                viewModel.onSearchChanged("")
                                            },
                                        ) { Text("Clear filters") }
                                        Button(onClick = { /* TODO: import CSV stub */ }) {
                                            Text("Import CSV")
                                        }
                                    }
                                },
                            )
                        } else {
                            EmptyState(
                                icon = Icons.Default.Inventory2,
                                title = "No items found",
                                subtitle = "Add inventory items to get started",
                            )
                        }
                    }
                }

                else -> {
                    PullToRefreshBox(
                        isRefreshing = state.isRefreshing,
                        onRefresh = { viewModel.refresh() },
                    ) {
                        LazyColumn(
                            contentPadding = PaddingValues(top = 8.dp, bottom = 80.dp),
                        ) {
                            items(state.items, key = { it.id }) { item ->
                                val isSelected = item.id in state.selectedIds
                                InventoryListRow(
                                    item = item,
                                    isAdmin = isAdmin,
                                    isTablet = isTablet,
                                    isSelected = isSelected,
                                    isSelectionMode = state.isSelectionMode,
                                    onClick = {
                                        if (state.isSelectionMode) {
                                            viewModel.toggleSelection(item.id)
                                        } else {
                                            onItemClick(item.id)
                                        }
                                    },
                                    onLongClick = {
                                        if (isTablet) viewModel.enterSelectionMode(item.id)
                                        // Context menu also triggered via overflow "…"
                                    },
                                    onAdjust = { delta, type, reason ->
                                        viewModel.adjustStockBy(item.id, delta, type, reason)
                                    },
                                    onCopySku = {
                                        clipboardManager.setText(AnnotatedString(item.sku ?: ""))
                                    },
                                    onOpenItem = { onItemClick(item.id) },
                                    onPrintLabel = {
                                        android.util.Log.i("InventoryListScreen", "TODO: print label for item ${item.id}")
                                    },
                                    onDuplicate = { /* TODO: duplicate item */ },
                                    onDeactivate = { /* TODO: deactivate item */ },
                                )
                                BrandListItemDivider()
                            }
                        }
                    }
                }
            }
        }
    }
}

// ─── Row ───────────────────────────────────────────────────────────────────

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun InventoryListRow(
    item: InventoryItemEntity,
    isAdmin: Boolean,
    isTablet: Boolean,
    isSelected: Boolean,
    isSelectionMode: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
    onAdjust: (delta: Int, type: String, reason: String?) -> Unit,
    onCopySku: () -> Unit,
    onOpenItem: () -> Unit,
    onPrintLabel: () -> Unit,
    onDuplicate: () -> Unit,
    onDeactivate: () -> Unit,
) {
    val isLowStock = item.inStock in 1 until item.reorderLevel && item.reorderLevel > 0
    val isOutOfStock = item.inStock == 0

    val rowA11yDesc = buildString {
        if (isOutOfStock) append("OUT OF STOCK. ")
        else if (isLowStock) append("LOW STOCK. ")
        append(item.name.ifBlank { "Unnamed" })
        if (!item.sku.isNullOrBlank()) append(", SKU ${item.sku}")
        append(", quantity ${item.inStock} in stock")
        append(", ${CurrencyFormatter.format(item.retailPrice)}")
        if (!item.itemType.isNullOrBlank()) append(", ${item.itemType.replaceFirstChar { it.uppercase() }}")
        append(". Tap to open.")
    }

    // Context-menu state — driven by overflow "…" button
    var showMenu by remember { mutableStateOf(false) }

    Box {
        BrandListItem(
            modifier = Modifier
                .semantics { contentDescription = rowA11yDesc }
                .combinedClickable(
                    onClick = onClick,
                    onLongClick = {
                        if (isTablet) {
                            onLongClick()
                        } else {
                            showMenu = true
                        }
                    },
                )
                .then(
                    if (isSelected) Modifier.background(MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.3f))
                    else Modifier
                ),
            // headline + support + trailing provided explicitly — no onClick param to BrandListItem
            // since we handle click via Modifier.combinedClickable above.
            headline = {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    if (isSelectionMode) {
                        Checkbox(checked = isSelected, onCheckedChange = null)
                    }
                    Text(
                        item.name.ifBlank { "Unnamed" },
                        style = MaterialTheme.typography.titleSmall,
                    )
                }
            },
            support = {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    if (!item.sku.isNullOrBlank()) {
                        Text(
                            "SKU: ${item.sku}",
                            style = BrandMono,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    } else if (!item.itemType.isNullOrBlank()) {
                        Text(
                            item.itemType.replaceFirstChar { it.uppercase() },
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    // §6.1 L1058 — stock badge
                    InventoryStockBadge(stockQty = item.inStock, reorderLevel = item.reorderLevel)
                }
            },
            trailing = {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Column(horizontalAlignment = Alignment.End) {
                        Text(
                            CurrencyFormatter.format(item.retailPrice),
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.primary,
                        )
                        // §6.1 L1066 — hide cost from non-admin
                        if (isAdmin) {
                            Text(
                                "Cost: ${CurrencyFormatter.format(item.costPrice)}",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        val stockColor = when {
                            isOutOfStock -> MaterialTheme.colorScheme.error
                            isLowStock -> MaterialTheme.colorScheme.error
                            else -> SuccessGreen
                        }
                        Text(
                            when {
                                isOutOfStock -> "Out · 0"
                                isLowStock -> "Low · ${item.inStock}"
                                else -> "Stock: ${item.inStock}"
                            },
                            style = MaterialTheme.typography.bodySmall,
                            color = stockColor,
                        )
                    }

                    // §6.1 L1059 — inline +/- stepper (tablet only)
                    if (isTablet) {
                        QuickStockAdjust(
                            stockQty = item.inStock,
                            onAdjust = onAdjust,
                        )
                    }

                    // Overflow "…" → context menu
                    Box {
                        IconButton(
                            onClick = { showMenu = true },
                            modifier = Modifier.size(24.dp),
                        ) {
                            Icon(
                                Icons.Default.MoreVert,
                                contentDescription = "More options for ${item.name}",
                                modifier = Modifier.size(16.dp),
                            )
                        }
                        InventoryContextMenu(
                            expanded = showMenu,
                            onDismiss = { showMenu = false },
                            onOpen = onOpenItem,
                            onCopySku = onCopySku,
                            onAdjustStock = { /* open QuickStockAdjust sheet via long-press stub */ },
                            onPrintLabel = onPrintLabel,
                            onDuplicate = onDuplicate,
                            onDeactivate = onDeactivate,
                        )
                    }
                }
            },
        )
    }
}

// ─── Bulk Action Bar ───────────────────────────────────────────────────────

@Composable
private fun BulkActionBar(
    selectedCount: Int,
    onBulkAdjust: () -> Unit,
    onBulkExport: () -> Unit,
    onDelete: () -> Unit,
    onClearSelection: () -> Unit,
) {
    Surface(
        tonalElevation = 8.dp,
        shadowElevation = 4.dp,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                "$selectedCount selected",
                style = MaterialTheme.typography.titleSmall,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                TextButton(onClick = onBulkAdjust) { Text("Adjust") }
                TextButton(onClick = onBulkExport) { Text("Export") }
                TextButton(
                    onClick = onDelete,
                    colors = ButtonDefaults.textButtonColors(
                        contentColor = MaterialTheme.colorScheme.error,
                    ),
                ) { Text("Delete") }
                IconButton(onClick = onClearSelection) {
                    Icon(Icons.Default.Close, contentDescription = "Clear selection")
                }
            }
        }
    }
}

