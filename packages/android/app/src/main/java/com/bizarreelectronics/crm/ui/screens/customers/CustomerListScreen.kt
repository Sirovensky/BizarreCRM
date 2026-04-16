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
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.components.shared.SearchBar
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
                            contentDescription = "Refresh",
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
                Icon(Icons.Default.PersonAdd, contentDescription = "Add customer")
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
                Text(
                    "${state.customers.size} customers",
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 2.dp),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            when {
                state.isLoading -> {
                    BrandSkeleton(
                        rows = 6,
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(top = 8.dp),
                    )
                }
                state.error != null -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
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
                else -> {
                    PullToRefreshBox(
                        isRefreshing = state.isRefreshing,
                        onRefresh = { viewModel.refresh() },
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        LazyColumn(modifier = Modifier.fillMaxSize()) {
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

    BrandListItem(
        leading = { CustomerAvatar(name = fullName) },
        headline = {
            Text(
                fullName,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface,
            )
        },
        support = {
            val phone = customer.mobile ?: customer.phone
            val meta = listOfNotNull(
                phone,
                customer.email?.takeIf { it.isNotBlank() },
                customer.organization?.takeIf { it.isNotBlank() },
            ).firstOrNull()
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

// ---------------------------------------------------------------------------
// CustomerAvatar — 36dp purple-container circle with initial
// ---------------------------------------------------------------------------

@Composable
private fun CustomerAvatar(name: String) {
    val initial = name.firstOrNull { it.isLetter() }?.uppercaseChar()?.toString() ?: "?"
    Box(
        modifier = Modifier
            .size(36.dp)
            .clip(CircleShape)
            .background(MaterialTheme.colorScheme.primaryContainer),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            initial,
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onPrimaryContainer,
        )
    }
}
