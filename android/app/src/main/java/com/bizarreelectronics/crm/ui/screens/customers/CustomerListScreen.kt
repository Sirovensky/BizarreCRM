package com.bizarreelectronics.crm.ui.screens.customers

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.entities.CustomerEntity
import com.bizarreelectronics.crm.data.repository.CustomerRepository
import com.bizarreelectronics.crm.ui.components.shared.BrandListItem
import com.bizarreelectronics.crm.ui.components.shared.BrandListItemDivider
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.CustomerAvatar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.components.shared.SearchBar
import com.bizarreelectronics.crm.util.formatPhoneDisplay
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import javax.inject.Inject

data class CustomerListUiState(
    val customers: List<CustomerEntity> = emptyList(),
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val searchQuery: String = "",
)

@HiltViewModel
class CustomerListViewModel @Inject constructor(
    private val customerRepository: CustomerRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(CustomerListUiState())
    val state = _state.asStateFlow()
    private var searchJob: Job? = null
    private var collectJob: Job? = null

    init {
        loadCustomers()
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
                flow.collectLatest { customers ->
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
            loadCustomers()
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CustomerListScreen(
    onCustomerClick: (Long) -> Unit,
    onCreateClick: () -> Unit,
    viewModel: CustomerListViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Customers",
                actions = {
                    IconButton(onClick = { viewModel.loadCustomers() }) {
                        Icon(
                            Icons.Default.Refresh,
                            // a11y: more specific than generic "Refresh" — matches Tickets pattern
                            contentDescription = "Refresh customers",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                },
            )
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = onCreateClick,
                containerColor = MaterialTheme.colorScheme.primary,
            ) {
                // a11y: imperative verb phrase matches §26 spec; "new" lower-case matches Tickets FAB pattern
                Icon(Icons.Default.PersonAdd, contentDescription = "Create new customer")
            }
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .imePadding(),
        ) {
            // Shared SearchBar — filled surface2, teal icon, muted clear
            SearchBar(
                query = state.searchQuery,
                onQueryChange = { viewModel.onSearchChanged(it) },
                placeholder = "Search customers...",
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )

            // Customer count — demoted to muted labelSmall chip
            if (!state.isLoading && state.customers.isNotEmpty()) {
                val customerCountLabel = "${state.customers.size} ${if (state.customers.size == 1) "customer" else "customers"}"
                Text(
                    customerCountLabel,
                    modifier = Modifier
                        .padding(horizontal = 16.dp, vertical = 2.dp)
                        // a11y: liveRegion=Polite so TalkBack announces the updated count
                        // when a search query changes the result set, without interrupting.
                        .semantics {
                            liveRegion = LiveRegionMode.Polite
                            contentDescription = customerCountLabel
                        },
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            when {
                state.isLoading -> {
                    // a11y: mergeDescendants + contentDescription so TalkBack announces
                    // "Loading customers" on a single focus stop rather than reading
                    // each shimmer box individually.
                    Box(
                        modifier = Modifier.semantics(mergeDescendants = true) {
                            contentDescription = "Loading customers"
                        },
                    ) {
                        BrandSkeleton(
                            rows = 6,
                            modifier = Modifier
                                .fillMaxSize()
                                .padding(top = 8.dp),
                        )
                    }
                }
                state.error != null -> {
                    // a11y: liveRegion=Assertive interrupts TalkBack immediately so the
                    // user is not left wondering why the list is empty after a network failure.
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .semantics { liveRegion = LiveRegionMode.Assertive },
                        contentAlignment = Alignment.Center,
                    ) {
                        ErrorState(
                            message = state.error ?: "Error",
                            onRetry = { viewModel.loadCustomers() },
                        )
                    }
                }
                state.customers.isEmpty() -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.TopCenter,
                    ) {
                        // a11y: mergeDescendants collapses the decorative icon + title + subtitle
                        // into one TalkBack node so the empty state reads as a single announcement.
                        Box(modifier = Modifier.semantics(mergeDescendants = true) {}) {
                            EmptyState(
                                icon = Icons.Default.People,
                                title = "No customers",
                                subtitle = if (state.searchQuery.isNotBlank())
                                    "No results for \"${state.searchQuery}\""
                                else
                                    "Add your first customer with the + button",
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
                            modifier = Modifier.fillMaxSize(),
                            // CROSS16: reserve space so the last row can scroll above the FAB.
                            contentPadding = PaddingValues(bottom = 96.dp),
                        ) {
                            items(state.customers, key = { it.id }) { customer ->
                                CustomerListRow(
                                    customer = customer,
                                    onClick = { onCustomerClick(customer.id) },
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

// ---------------------------------------------------------------------------
// CustomerListRow — BrandListItem with avatar initial + muted meta
// ---------------------------------------------------------------------------

@Composable
private fun CustomerListRow(customer: CustomerEntity, onClick: () -> Unit) {
    val fullName = listOfNotNull(customer.firstName, customer.lastName)
        .joinToString(" ")
        .ifBlank { "Unknown" }

    // a11y: build the full announcement string once so it can be used in semantics.
    // BrandListItem already applies mergeDescendants=true + Role.Button on its outer Row;
    // we add contentDescription here so TalkBack announces a single coherent sentence
    // instead of reading each child Text node individually.
    // CROSS8: route phone through shared formatPhoneDisplay so list rows
    // render the canonical `+1 (XXX)-XXX-XXXX` like the detail view.
    val phone = (customer.mobile ?: customer.phone)
        ?.let { formatPhoneDisplay(it) }
        ?.takeIf { it.isNotBlank() }
    val meta = listOfNotNull(
        phone,
        customer.email?.takeIf { it.isNotBlank() },
        customer.organization?.takeIf { it.isNotBlank() },
    ).firstOrNull()
    val a11yDesc = buildString {
        append("Customer $fullName")
        meta?.let { append(", $it") }
        append(". Tap to open.")
    }

    BrandListItem(
        // a11y: contentDescription overrides the merged child-text reading; 48dp floor
        // ensures the row meets the Material 3 minimum touch target.
        modifier = Modifier
            .defaultMinSize(minHeight = 48.dp)
            .semantics { contentDescription = a11yDesc },
        leading = { CustomerAvatar(name = fullName) },
        headline = {
            Text(
                fullName,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface,
            )
        },
        support = {
            if (meta != null) {
                Text(
                    meta,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
        onClick = onClick,
    )
}

// CROSS49: CustomerAvatar extracted to
// `components/shared/CustomerAvatar.kt` and parameterised on `size` so the
// customer detail screen can render the same circle at 72dp.
