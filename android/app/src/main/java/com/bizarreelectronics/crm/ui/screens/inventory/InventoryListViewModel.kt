package com.bizarreelectronics.crm.ui.screens.inventory

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.entities.InventoryItemEntity
import com.bizarreelectronics.crm.data.remote.dto.AdjustStockRequest
import com.bizarreelectronics.crm.data.repository.InventoryRepository
import com.bizarreelectronics.crm.ui.screens.inventory.components.InventoryFilter
import com.bizarreelectronics.crm.ui.screens.inventory.components.InventorySort
import com.bizarreelectronics.crm.ui.screens.inventory.components.StockStatus
import com.bizarreelectronics.crm.ui.screens.inventory.components.applyInventorySortOrder
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
    // §6.1 additions
    val currentFilter: InventoryFilter = InventoryFilter.Empty,
    val currentSort: InventorySort = InventorySort.NameAZ,
    val selectedIds: Set<Long> = emptySet(),
    val isSelectionMode: Boolean = false,
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
            val filter = _state.value.currentFilter
            val sort = _state.value.currentSort

            val flow = if (query.isNotEmpty()) {
                inventoryRepository.searchItems(query)
            } else {
                inventoryRepository.getItems()
            }

            flow
                .map { items ->
                    items
                        .let { list ->
                            if (typeFilter != "All") {
                                list.filter { it.itemType.equals(typeFilter, ignoreCase = true) }
                            } else list
                        }
                        .let { list -> applyInventoryFilter(list, filter) }
                        .let { list -> applyInventorySortOrder(list, sort) }
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

    fun onFilterChanged(filter: InventoryFilter) {
        _state.value = _state.value.copy(currentFilter = filter)
        loadItems()
    }

    fun onSortChanged(sort: InventorySort) {
        _state.value = _state.value.copy(currentSort = sort)
        loadItems()
    }

    // -----------------------------------------------------------------------
    // Selection mode (bulk select) — tablet-gated in the UI
    // -----------------------------------------------------------------------

    fun enterSelectionMode(id: Long) {
        _state.value = _state.value.copy(
            isSelectionMode = true,
            selectedIds = setOf(id),
        )
    }

    fun toggleSelection(id: Long) {
        val current = _state.value.selectedIds
        val updated = if (id in current) current - id else current + id
        _state.value = _state.value.copy(
            selectedIds = updated,
            isSelectionMode = updated.isNotEmpty(),
        )
    }

    fun clearSelection() {
        _state.value = _state.value.copy(
            selectedIds = emptySet(),
            isSelectionMode = false,
        )
    }

    // -----------------------------------------------------------------------
    // Stock adjustment — optimistic update + SyncQueue enqueue (via Repository)
    // -----------------------------------------------------------------------

    /**
     * Adjusts stock for [id] by [delta] (positive = add, negative = remove).
     * Optimistically updates the in-memory list so the UI reflects immediately,
     * then delegates to [InventoryRepository.adjustStock] which handles
     * online/offline + SyncQueue.
     *
     * @param type   API type string ("sold", "received", "damaged", "adjusted")
     * @param reason Human-readable reason label passed as the API `reason` field.
     */
    fun adjustStockBy(id: Long, delta: Int, type: String = "adjusted", reason: String? = null) {
        // Optimistic update
        val updated = _state.value.items.map { item ->
            if (item.id == id) {
                item.copy(inStock = maxOf(0, item.inStock + delta))
            } else {
                item
            }
        }
        _state.value = _state.value.copy(items = updated)

        viewModelScope.launch {
            try {
                inventoryRepository.adjustStock(
                    id = id,
                    request = AdjustStockRequest(
                        quantity = delta,
                        type = type,
                        reason = reason,
                    ),
                )
            } catch (e: Exception) {
                Log.w(TAG, "adjustStockBy($id, $delta) failed: ${e.message}")
                // Roll back optimistic update on failure
                loadItems()
            }
        }
    }

    // -----------------------------------------------------------------------
    // Barcode lookup (unchanged)
    // -----------------------------------------------------------------------

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

    companion object {
        private const val TAG = "InventoryListVM"
    }
}

// -----------------------------------------------------------------------
// Filter predicate (pure, testable)
// -----------------------------------------------------------------------

internal fun applyInventoryFilter(
    items: List<InventoryItemEntity>,
    filter: InventoryFilter,
): List<InventoryItemEntity> {
    if (filter == InventoryFilter.Empty) return items
    return items.filter { item ->
        matchesCategory(item, filter.category) &&
            matchesSupplier(item, filter.supplier) &&
            matchesStockStatus(item, filter.stockStatus) &&
            matchesBin(item, filter.bin) &&
            matchesPrice(item, filter.minPriceCents, filter.maxPriceCents) &&
            matchesTag(item, filter.tag)
    }
}

private fun matchesCategory(item: InventoryItemEntity, category: String?): Boolean =
    category == null || item.category?.contains(category, ignoreCase = true) == true

private fun matchesSupplier(item: InventoryItemEntity, supplier: String?): Boolean =
    supplier == null || item.supplierName?.contains(supplier, ignoreCase = true) == true

private fun matchesStockStatus(item: InventoryItemEntity, status: StockStatus): Boolean =
    when (status) {
        StockStatus.All -> true
        StockStatus.InStock -> item.inStock >= item.reorderLevel && item.reorderLevel > 0
        StockStatus.LowStock -> item.inStock in 1 until item.reorderLevel
        StockStatus.OutOfStock -> item.inStock == 0
    }

private fun matchesBin(item: InventoryItemEntity, bin: String?): Boolean =
    bin == null || item.bin?.contains(bin, ignoreCase = true) == true

private fun matchesPrice(
    item: InventoryItemEntity,
    minCents: Long?,
    maxCents: Long?,
): Boolean {
    val price = item.retailPriceCents
    if (minCents != null && price < minCents) return false
    if (maxCents != null && price > maxCents) return false
    return true
}

private fun matchesTag(item: InventoryItemEntity, tag: String?): Boolean =
    // Tags are not a first-class field on InventoryItemEntity yet.
    // Always returns true until the schema exposes a `tags` column.
    tag == null
