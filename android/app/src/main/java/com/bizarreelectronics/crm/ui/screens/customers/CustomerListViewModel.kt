package com.bizarreelectronics.crm.ui.screens.customers

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.paging.PagingData
import androidx.paging.cachedIn
import com.bizarreelectronics.crm.data.local.db.entities.CustomerEntity
import com.bizarreelectronics.crm.data.remote.dto.CustomerStats
import com.bizarreelectronics.crm.data.remote.api.CustomerApi
import com.bizarreelectronics.crm.data.repository.CustomerRepository
import com.bizarreelectronics.crm.ui.screens.customers.components.CustomerFilter
import com.bizarreelectronics.crm.ui.screens.customers.components.CustomerSort
import com.bizarreelectronics.crm.ui.screens.customers.components.filterKey
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.launch
import javax.inject.Inject

data class CustomerListUiState(
    val customers: List<CustomerEntity> = emptyList(),
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val searchQuery: String = "",
    // Sort / filter (plan:L875/L876)
    val currentSort: CustomerSort = CustomerSort.Recent,
    val currentFilter: CustomerFilter = CustomerFilter(),
    val showFilterSheet: Boolean = false,
    // Stats header (plan:L880)
    val stats: CustomerStats? = null,
    // Bulk selection (plan:L882)
    val selectedIds: Set<Long> = emptySet(),
    val isBulkMode: Boolean = false,
    // Export state (plan:L884)
    val exportCsvContent: String? = null,
    // Snackbar (plan:L882 delete undo)
    val snackbarMessage: String? = null,
)

/** Sort + filter key used to fan-out the Paging3 flow. */
private data class PageKey(
    val sort: CustomerSort,
    val filterKey: String,
    val searchQuery: String,
)

@OptIn(ExperimentalCoroutinesApi::class)
@HiltViewModel
class CustomerListViewModel @Inject constructor(
    private val customerRepository: CustomerRepository,
    private val customerApi: CustomerApi,
) : ViewModel() {

    private val _state = MutableStateFlow(CustomerListUiState())
    val state = _state.asStateFlow()
    private var searchJob: Job? = null
    private var collectJob: Job? = null

    // Active paging key drives [customersPaged]
    private val _pageKey = MutableStateFlow(PageKey(CustomerSort.Recent, "", ""))

    /**
     * Paged flow of customers. Automatically refreshes when [_pageKey] changes.
     * Cached in [viewModelScope] so recomposition doesn't restart the flow.
     */
    val customersPaged: Flow<PagingData<CustomerEntity>> = _pageKey
        .flatMapLatest { key ->
            customerRepository.customersPaged(
                sort = key.sort.sortKey,
                filterKey = key.filterKey,
            )
        }
        .cachedIn(viewModelScope)

    init {
        loadCustomers()
        loadStats()
    }

    fun loadCustomers() {
        collectJob?.cancel()
        collectJob = viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                val query = _state.value.searchQuery.trim()
                val flow = if (query.isNotEmpty()) {
                    customerRepository.searchCustomers(query)
                } else {
                    customerRepository.getCustomers()
                }
                flow.collect { customers ->
                    _state.value = _state.value.copy(
                        customers = customers,
                        isLoading = false,
                        isRefreshing = false,
                    )
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    isRefreshing = false,
                    error = "Failed to load customers. Check your connection and try again.",
                )
            }
        }
    }

    fun refresh() {
        _state.value = _state.value.copy(isRefreshing = true)
        loadCustomers()
    }

    fun onSearchChanged(query: String) {
        _state.value = _state.value.copy(searchQuery = query)
        searchJob?.cancel()
        searchJob = viewModelScope.launch {
            delay(300)
            _pageKey.value = buildPageKey()
            loadCustomers()
        }
    }

    // -----------------------------------------------------------------------
    // Sort (plan:L875)
    // -----------------------------------------------------------------------

    fun onSortSelected(sort: CustomerSort) {
        _state.value = _state.value.copy(currentSort = sort)
        _pageKey.value = buildPageKey()
    }

    // -----------------------------------------------------------------------
    // Filter (plan:L876)
    // -----------------------------------------------------------------------

    fun showFilterSheet() {
        _state.value = _state.value.copy(showFilterSheet = true)
    }

    fun onFilterChanged(filter: CustomerFilter) {
        _state.value = _state.value.copy(currentFilter = filter, showFilterSheet = false)
        _pageKey.value = buildPageKey()
    }

    fun dismissFilterSheet() {
        _state.value = _state.value.copy(showFilterSheet = false)
    }

    // -----------------------------------------------------------------------
    // Stats header (plan:L880)
    // -----------------------------------------------------------------------

    private fun loadStats() {
        viewModelScope.launch {
            try {
                val response = customerApi.getStats()
                _state.value = _state.value.copy(stats = response.data)
            } catch (_: Exception) {
                // 404 or network failure → stats stays null → header hidden
            }
        }
    }

    // -----------------------------------------------------------------------
    // Swipe actions (plan:L877) — quick VIP / Archive
    // -----------------------------------------------------------------------

    fun onMarkVip(customerId: Long) {
        viewModelScope.launch {
            try {
                customerApi.updateCustomer(
                    customerId,
                    com.bizarreelectronics.crm.data.remote.dto.UpdateCustomerRequest(
                        customerTags = "VIP",
                    ),
                )
            } catch (_: Exception) { /* silent — list refresh will correct state */ }
        }
    }

    fun onArchive(customerId: Long) {
        viewModelScope.launch {
            try {
                customerApi.updateCustomer(
                    customerId,
                    com.bizarreelectronics.crm.data.remote.dto.UpdateCustomerRequest(
                        type = "archived",
                    ),
                )
            } catch (_: Exception) { /* silent */ }
        }
    }

    // -----------------------------------------------------------------------
    // Bulk selection (plan:L882)
    // -----------------------------------------------------------------------

    fun onLongPress(customerId: Long) {
        val current = _state.value
        _state.value = current.copy(
            isBulkMode = true,
            selectedIds = current.selectedIds + customerId,
        )
    }

    fun onToggleSelect(customerId: Long) {
        val current = _state.value
        val newIds = if (customerId in current.selectedIds) {
            current.selectedIds - customerId
        } else {
            current.selectedIds + customerId
        }
        _state.value = current.copy(
            selectedIds = newIds,
            isBulkMode = newIds.isNotEmpty(),
        )
    }

    fun clearBulkSelection() {
        _state.value = _state.value.copy(isBulkMode = false, selectedIds = emptySet())
    }

    fun onBulkDelete() {
        val ids = _state.value.selectedIds.toList()
        clearBulkSelection()
        viewModelScope.launch {
            ids.forEach { id ->
                try { customerApi.deleteCustomer(id) } catch (_: Exception) {}
            }
            _state.value = _state.value.copy(
                snackbarMessage = "Deleted ${ids.size} customer(s)",
            )
            loadCustomers()
        }
    }

    fun onBulkTag(tag: String) {
        val ids = _state.value.selectedIds.toList()
        clearBulkSelection()
        viewModelScope.launch {
            ids.forEach { id ->
                try {
                    customerApi.updateCustomer(
                        id,
                        com.bizarreelectronics.crm.data.remote.dto.UpdateCustomerRequest(customerTags = tag),
                    )
                } catch (_: Exception) {}
            }
            _state.value = _state.value.copy(snackbarMessage = "Tagged ${ids.size} customer(s) as $tag")
            loadCustomers()
        }
    }

    fun clearSnackbar() {
        _state.value = _state.value.copy(snackbarMessage = null)
    }

    // -----------------------------------------------------------------------
    // Export CSV (plan:L884)
    // -----------------------------------------------------------------------

    fun buildCsvContent(): String {
        val customers = _state.value.customers
        val header = "ID,First Name,Last Name,Email,Phone,Organization,City,State,Created At"
        val rows = customers.map { c ->
            listOf(
                c.id.toString(),
                c.firstName.csv(),
                c.lastName.csv(),
                c.email.csv(),
                (c.mobile ?: c.phone).csv(),
                c.organization.csv(),
                c.city.csv(),
                c.state.csv(),
                c.createdAt,
            ).joinToString(",")
        }
        return (listOf(header) + rows).joinToString("\n")
    }

    fun onExportReady(content: String) {
        _state.value = _state.value.copy(exportCsvContent = content)
    }

    fun clearExportCsv() {
        _state.value = _state.value.copy(exportCsvContent = null)
    }

    // -----------------------------------------------------------------------
    // Context menu helpers (plan:L878)
    // -----------------------------------------------------------------------

    fun copyPhone(customer: CustomerEntity, context: Context) {
        val phone = customer.mobile ?: customer.phone ?: return
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE)
            as android.content.ClipboardManager
        clipboard.setPrimaryClip(
            android.content.ClipData.newPlainText("Phone", phone)
        )
    }

    fun copyEmail(customer: CustomerEntity, context: Context) {
        val email = customer.email ?: return
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE)
            as android.content.ClipboardManager
        clipboard.setPrimaryClip(
            android.content.ClipData.newPlainText("Email", email)
        )
    }

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------

    private fun buildPageKey(): PageKey = PageKey(
        sort = _state.value.currentSort,
        filterKey = _state.value.currentFilter.filterKey,
        searchQuery = _state.value.searchQuery.trim(),
    )
}

private fun String?.csv(): String {
    if (this == null) return ""
    return if (contains(',') || contains('"') || contains('\n')) {
        "\"${replace("\"", "\"\"")}\""
    } else this
}
