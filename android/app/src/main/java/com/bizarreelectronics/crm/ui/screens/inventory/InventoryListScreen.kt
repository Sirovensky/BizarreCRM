package com.bizarreelectronics.crm.ui.screens.inventory

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
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.ui.components.shared.BrandListItem
import com.bizarreelectronics.crm.ui.components.shared.BrandListItemDivider
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.components.shared.SearchBar
import com.bizarreelectronics.crm.ui.theme.*
import com.bizarreelectronics.crm.data.local.db.entities.InventoryItemEntity
// @audit-fixed: Section 33 / D1 — costPrice / retailPrice are now top-level
// extension shims that read from the cents columns. Explicit import required.
import com.bizarreelectronics.crm.data.local.db.entities.retailPrice
import com.bizarreelectronics.crm.data.repository.InventoryRepository
import com.bizarreelectronics.crm.util.CurrencyFormatter
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import javax.inject.Inject

data class InventoryListUiState(
    val items: List<InventoryItemEntity> = emptyList(),
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val searchQuery: String = "",
    val selectedType: String = "All",
    val barcodeLookupId: Long? = null,
    val barcodeLookupError: String? = null,
)

@HiltViewModel
class InventoryListViewModel @Inject constructor(
    private val inventoryRepository: InventoryRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(InventoryListUiState())
    val state = _state.asStateFlow()
    private var searchJob: Job? = null
    private var collectJob: Job? = null

    init {
        loadItems()
    }

    fun loadItems() {
        collectJob?.cancel()
        collectJob = viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            val query = _state.value.searchQuery.trim()
            val typeFilter = _state.value.selectedType

            val flow = if (query.isNotEmpty()) {
                inventoryRepository.searchItems(query)
            } else {
                inventoryRepository.getItems()
            }

            flow
                .map { items ->
                    if (typeFilter != "All") {
                        items.filter { it.itemType.equals(typeFilter, ignoreCase = true) }
                    } else {
                        items
                    }
                }
                .catch { e ->
                    _state.value = _state.value.copy(
                        isLoading = false,
                        isRefreshing = false,
                        error = "Failed to load inventory. Check your connection and try again.",
                    )
                }
                .collectLatest { items ->
                    _state.value = _state.value.copy(
                        items = items,
                        isLoading = false,
                        isRefreshing = false,
                    )
                }
        }
    }

    fun refresh() {
        _state.value = _state.value.copy(isRefreshing = true)
        loadItems()
    }

    fun onSearchChanged(query: String) {
        _state.value = _state.value.copy(searchQuery = query)
        searchJob?.cancel()
        searchJob = viewModelScope.launch {
            delay(300)
            loadItems()
        }
    }

    fun onTypeChanged(type: String) {
        _state.value = _state.value.copy(selectedType = type)
        loadItems()
    }

    fun lookupBarcode(code: String) {
        viewModelScope.launch {
            try {
                val entity = inventoryRepository.lookupBarcode(code)
                if (entity != null) {
                    _state.value = _state.value.copy(barcodeLookupId = entity.id, barcodeLookupError = null)
                } else {
                    _state.value = _state.value.copy(barcodeLookupError = "No item found for barcode: $code")
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(barcodeLookupError = "Barcode lookup failed: ${e.message}")
            }
        }
    }

    fun clearBarcodeLookup() {
        _state.value = _state.value.copy(barcodeLookupId = null, barcodeLookupError = null)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
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
    // CROSS3: "Service" removed from inventory type tabs — services are
    // non-stockable labor and live in the `repair_services` table, not the
    // `inventory_items` table. Ticket-wizard / POS service picker still
    // works via the repair_services path.
    val types = listOf("All", "Product", "Part")
    val snackbarHostState = remember { SnackbarHostState() }

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

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        // AND-20260414-M2: Inventory Add FAB — routes to InventoryCreateScreen.
        floatingActionButton = {
            FloatingActionButton(
                onClick = onAddClick,
                containerColor = MaterialTheme.colorScheme.primary,
                contentColor = MaterialTheme.colorScheme.onPrimary,
            ) {
                // a11y: §26 spec — "Add inventory item" (imperative, screen-specific)
                Icon(Icons.Default.Add, contentDescription = "Add inventory item")
            }
        },
        topBar = {
            BrandTopAppBar(
                title = "Inventory",
                actions = {
                    IconButton(onClick = onScanClick) {
                        // a11y: barcode scan action — screen-specific label distinguishes
                        // from other scan buttons elsewhere in the app
                        Icon(Icons.Default.QrCodeScanner, contentDescription = "Scan barcode to find item")
                    }
                    IconButton(onClick = { viewModel.loadItems() }) {
                        // a11y: screen-specific label mirrors "Refresh tickets" / "Refresh expenses" pattern
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh inventory")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .imePadding(),
        ) {
            // a11y: contentDescription on the wrapper gives TalkBack a screen-specific label
            // ("Search inventory") so it's distinguished from other search bars in the app.
            // The underlying TextField inside SearchBar handles the EditText role automatically.
            SearchBar(
                query = state.searchQuery,
                onQueryChange = { viewModel.onSearchChanged(it) },
                placeholder = "Search inventory...",
                modifier = Modifier
                    .padding(horizontal = 16.dp, vertical = 8.dp)
                    .semantics { contentDescription = "Search inventory" },
            )

            // a11y: "Type filter" heading so TalkBack heading-navigation (swipe with two fingers)
            // can jump directly to the filter row; heading() marks it in the a11y tree.
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
                        // a11y: Role.Tab + selection state so TalkBack announces
                        // "<type> tab, selected/not selected"
                        modifier = Modifier.semantics {
                            role = Role.Tab
                            contentDescription = if (isSelected) {
                                "$type tab, selected"
                            } else {
                                "$type tab, not selected"
                            }
                        },
                    )
                }
            }

            Spacer(modifier = Modifier.height(8.dp))

            when {
                state.isLoading -> {
                    // a11y: mergeDescendants + contentDescription so TalkBack announces
                    // "Loading inventory" on a single focus stop rather than each shimmer
                    // box individually.
                    Box(
                        modifier = Modifier.semantics(mergeDescendants = true) {
                            contentDescription = "Loading inventory"
                        },
                    ) {
                        // Skeleton rows: replaces bare spinner for list loading
                        BrandSkeleton(
                            rows = 6,
                            modifier = Modifier.padding(top = 8.dp),
                        )
                    }
                }
                state.error != null -> {
                    // a11y: liveRegion=Assertive so TalkBack interrupts immediately and
                    // informs the user about the error rather than leaving them in silence.
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
                    // a11y: mergeDescendants collapses the decorative icon + title + subtitle
                    // into one TalkBack node so the empty state reads as a single announcement.
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .semantics(mergeDescendants = true) {},
                        contentAlignment = Alignment.Center,
                    ) {
                        EmptyState(
                            icon = Icons.Default.Inventory2,
                            title = "No items found",
                            subtitle = if (state.searchQuery.isNotEmpty()) {
                                "Try a different search term"
                            } else {
                                "Add inventory items to get started"
                            },
                        )
                    }
                }
                else -> {
                    PullToRefreshBox(
                        isRefreshing = state.isRefreshing,
                        onRefresh = { viewModel.refresh() },
                    ) {
                        LazyColumn(
                            // CROSS16-ext: bottom inset so the last row can
                            // scroll above the bottom-nav / gesture area.
                            contentPadding = PaddingValues(top = 8.dp, bottom = 80.dp),
                        ) {
                            items(state.items, key = { it.id }) { item ->
                                InventoryListRow(item = item, onClick = { onItemClick(item.id) })
                                BrandListItemDivider()
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun InventoryListRow(item: InventoryItemEntity, onClick: () -> Unit) {
    val isLowStock = item.inStock <= item.reorderLevel && item.reorderLevel > 0

    // a11y: build the row announcement string. Prefix with "LOW STOCK" when applicable
    // so that TalkBack users immediately know the stock status before the rest of the info.
    // Format: "[LOW STOCK. ]ITEM_NAME[, SKU][, quantity X in stock], $PRICE[, CATEGORY]. Tap to open."
    val rowA11yDesc = buildString {
        if (isLowStock) append("LOW STOCK. ")
        append(item.name.ifBlank { "Unnamed" })
        if (!item.sku.isNullOrBlank()) append(", SKU ${item.sku}")
        append(", quantity ${item.inStock} in stock")
        append(", ${CurrencyFormatter.format(item.retailPrice)}")
        if (!item.itemType.isNullOrBlank()) append(", ${item.itemType.replaceFirstChar { it.uppercase() }}")
        append(". Tap to open.")
    }

    BrandListItem(
        onClick = onClick,
        // a11y: BrandListItem already applies semantics(mergeDescendants=true) + Role.Button
        // when onClick != null (§26.1 in BrandListItem.kt). We only add the contentDescription
        // here so TalkBack reads the full structured announcement rather than concatenating
        // the individual Text composables inside the row.
        modifier = Modifier.semantics { contentDescription = rowA11yDesc },
        headline = {
            Text(
                item.name.ifBlank { "Unnamed" },
                style = MaterialTheme.typography.titleSmall,
            )
        },
        support = {
            if (!item.sku.isNullOrBlank()) {
                Text(
                    "SKU: ${item.sku}",
                    // BrandMono for SKU strings per todo rule
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
        },
        trailing = {
            Column(horizontalAlignment = Alignment.End) {
                // @audit-fixed: was String.format("$%.2f", ...) — see original.
                Text(
                    CurrencyFormatter.format(item.retailPrice),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.primary,
                )
                val stockColor = if (isLowStock) MaterialTheme.colorScheme.error else SuccessGreen
                Text(
                    if (isLowStock) "Low · ${item.inStock}" else "Stock: ${item.inStock}",
                    style = MaterialTheme.typography.bodySmall,
                    color = stockColor,
                )
            }
        },
    )
}
