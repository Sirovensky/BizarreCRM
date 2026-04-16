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
    scannedBarcode: String? = null,
    onBarcodeLookupResult: (Long) -> Unit = {},
    onBarcodeLookupConsumed: () -> Unit = {},
    viewModel: InventoryListViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val types = listOf("All", "Product", "Part", "Service")
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
        topBar = {
            BrandTopAppBar(
                title = "Inventory",
                actions = {
                    IconButton(onClick = onScanClick) {
                        Icon(Icons.Default.QrCodeScanner, contentDescription = "Scan Barcode")
                    }
                    IconButton(onClick = { viewModel.loadItems() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
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
            SearchBar(
                query = state.searchQuery,
                onQueryChange = { viewModel.onSearchChanged(it) },
                placeholder = "Search inventory...",
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )

            LazyRow(
                modifier = Modifier.padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(types) { type ->
                    FilterChip(
                        selected = state.selectedType == type,
                        onClick = { viewModel.onTypeChanged(type) },
                        label = { Text(type) },
                    )
                }
            }

            Spacer(modifier = Modifier.height(8.dp))

            when {
                state.isLoading -> {
                    // Skeleton rows: replaces bare spinner for list loading
                    BrandSkeleton(
                        rows = 6,
                        modifier = Modifier.padding(top = 8.dp),
                    )
                }
                state.error != null -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        ErrorState(
                            message = state.error ?: "Failed to load inventory.",
                            onRetry = { viewModel.loadItems() },
                        )
                    }
                }
                state.items.isEmpty() -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
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
                            contentPadding = PaddingValues(vertical = 8.dp),
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

    BrandListItem(
        onClick = onClick,
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
