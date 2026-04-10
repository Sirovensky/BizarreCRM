package com.bizarreelectronics.crm.ui.screens.inventory

import androidx.compose.foundation.clickable
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.ui.theme.*
import com.bizarreelectronics.crm.data.local.db.entities.InventoryItemEntity
import com.bizarreelectronics.crm.data.repository.InventoryRepository
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
            TopAppBar(
                title = { Text("Inventory") },
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
            OutlinedTextField(
                value = state.searchQuery,
                onValueChange = { viewModel.onSearchChanged(it) },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                placeholder = { Text("Search inventory...") },
                leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                singleLine = true,
                trailingIcon = {
                    if (state.searchQuery.isNotEmpty()) {
                        IconButton(onClick = { viewModel.onSearchChanged("") }) {
                            Icon(Icons.Default.Clear, contentDescription = "Clear")
                        }
                    }
                },
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
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                }
                state.error != null -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(state.error ?: "Error", color = MaterialTheme.colorScheme.error)
                            Spacer(modifier = Modifier.height(8.dp))
                            TextButton(onClick = { viewModel.loadItems() }) { Text("Retry") }
                        }
                    }
                }
                state.items.isEmpty() -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Icon(
                                Icons.Default.Inventory2,
                                contentDescription = null,
                                modifier = Modifier.size(48.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                            Text(
                                "No inventory items found",
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
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
                            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            items(state.items, key = { it.id }) { item ->
                                InventoryCard(item = item, onClick = { onItemClick(item.id) })
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun InventoryCard(item: InventoryItemEntity, onClick: () -> Unit) {
    val isLowStock = item.inStock <= item.reorderLevel && item.reorderLevel > 0

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
    ) {
        Row(
            modifier = Modifier
                .padding(16.dp)
                .fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    item.name.ifBlank { "Unnamed" },
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                if (!item.sku.isNullOrBlank()) {
                    Text(
                        "SKU: ${item.sku}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Text(
                    item.itemType ?: "unknown",
                    style = MaterialTheme.typography.labelSmall,
                )
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    String.format("$%.2f", item.retailPrice),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                )
                val stockColor = if (isLowStock) ErrorRed else SuccessGreen
                Text(
                    "Stock: ${item.inStock}",
                    style = MaterialTheme.typography.bodySmall,
                    color = stockColor,
                )
                if (isLowStock) {
                    Text(
                        "Low stock",
                        style = MaterialTheme.typography.labelSmall,
                        color = ErrorRed,
                    )
                }
            }
        }
    }
}
