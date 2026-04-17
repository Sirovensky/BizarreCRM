package com.bizarreelectronics.crm.ui.screens.search

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.dao.CustomerDao
import com.bizarreelectronics.crm.data.local.db.dao.InventoryDao
import com.bizarreelectronics.crm.data.local.db.dao.TicketDao
import com.bizarreelectronics.crm.data.remote.api.SearchApi
import com.bizarreelectronics.crm.ui.components.shared.BrandStatusBadge
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.components.shared.LoadingIndicator
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import com.bizarreelectronics.crm.util.formatPhoneDisplay
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.launch
import javax.inject.Inject

data class SearchResult(
    val type: String,
    val id: Long,
    val title: String,
    val subtitle: String,
)

data class GlobalSearchUiState(
    val query: String = "",
    val results: List<SearchResult> = emptyList(),
    val isLoading: Boolean = false,
    val error: String? = null,
    val hasSearched: Boolean = false,
)

@OptIn(FlowPreview::class)
@HiltViewModel
class GlobalSearchViewModel @Inject constructor(
    private val searchApi: SearchApi,
    private val serverMonitor: ServerReachabilityMonitor,
    private val ticketDao: TicketDao,
    private val customerDao: CustomerDao,
    private val inventoryDao: InventoryDao,
) : ViewModel() {

    private val _state = MutableStateFlow(GlobalSearchUiState())
    val state = _state.asStateFlow()

    private val _queryFlow = MutableStateFlow("")

    init {
        viewModelScope.launch {
            _queryFlow
                .debounce(300L)
                .distinctUntilChanged()
                .filter { it.isNotBlank() }
                .collectLatest { query -> performSearch(query) }
        }
    }

    fun updateQuery(value: String) {
        _state.value = _state.value.copy(query = value)
        _queryFlow.value = value
        if (value.isBlank()) {
            _state.value = _state.value.copy(
                results = emptyList(),
                hasSearched = false,
                error = null,
            )
        }
    }

    private suspend fun performSearch(query: String) {
        _state.value = _state.value.copy(isLoading = true, error = null)

        if (serverMonitor.isEffectivelyOnline.value) {
            try {
                val response = searchApi.globalSearch(query)
                val data = response.data
                val results = mutableListOf<SearchResult>()

                if (data != null) {
                    parseResultList(data["customers"], "customer")?.let { results.addAll(it) }
                    parseResultList(data["tickets"], "ticket")?.let { results.addAll(it) }
                    parseResultList(data["inventory"], "inventory")?.let { results.addAll(it) }
                    parseResultList(data["invoices"], "invoice")?.let { results.addAll(it) }
                }

                _state.value = _state.value.copy(
                    results = results,
                    isLoading = false,
                    hasSearched = true,
                )
                return
            } catch (_: Exception) {
                // Fall through to offline search
            }
        }

        // Offline: search across local Room DAOs
        try {
            val results = mutableListOf<SearchResult>()

            // Search customers
            customerDao.search(query).firstOrNull()?.forEach { c ->
                val name = listOfNotNull(c.firstName, c.lastName).joinToString(" ").trim().ifBlank { "Customer #${c.id}" }
                // CROSS8: display phone with the canonical +1 (XXX)-XXX-XXXX format.
                val formattedPhone = (c.phone ?: c.mobile)?.let { formatPhoneDisplay(it) }?.takeIf { it.isNotBlank() }
                val contact = listOfNotNull(formattedPhone, c.email).joinToString(" | ").ifBlank { "No contact info" }
                results.add(SearchResult(type = "customer", id = c.id, title = name, subtitle = contact))
            }

            // Search tickets
            ticketDao.search(query).firstOrNull()?.forEach { t ->
                val title = t.orderId.ifBlank { "T-${t.id}" }
                val subtitle = listOfNotNull(t.statusName, t.customerName).filter { it.isNotBlank() }.joinToString(" - ").ifBlank { "Ticket" }
                results.add(SearchResult(type = "ticket", id = t.id, title = title, subtitle = subtitle))
            }

            // Search inventory
            inventoryDao.search(query).firstOrNull()?.forEach { i ->
                val title = i.name.ifBlank { "Item #${i.id}" }
                val subtitle = listOfNotNull(
                    i.sku?.let { "SKU: $it" },
                    "Stock: ${i.inStock}",
                ).joinToString(" | ").ifBlank { "Inventory item" }
                results.add(SearchResult(type = "inventory", id = i.id, title = title, subtitle = subtitle))
            }

            _state.value = _state.value.copy(
                results = results,
                isLoading = false,
                hasSearched = true,
            )
        } catch (e: Exception) {
            _state.value = _state.value.copy(
                isLoading = false,
                error = e.message ?: "Search failed",
                hasSearched = true,
            )
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun parseResultList(raw: Any?, type: String): List<SearchResult>? {
        val list = raw as? List<*> ?: return null
        return list.mapNotNull { item ->
            val map = item as? Map<String, Any> ?: return@mapNotNull null
            val id = when (val rawId = map["id"]) {
                is Number -> rawId.toLong()
                is String -> rawId.toLongOrNull()
                else -> null
            } ?: return@mapNotNull null

            val title: String
            val subtitle: String

            when (type) {
                "customer" -> {
                    val first = map["first_name"]?.toString().orEmpty()
                    val last = map["last_name"]?.toString().orEmpty()
                    title = "$first $last".trim().ifBlank { "Customer #$id" }
                    // CROSS8: display phone via shared helper for canonical format.
                    val phone = (map["phone"]?.toString() ?: map["mobile"]?.toString())
                        ?.let { formatPhoneDisplay(it) }
                        ?.takeIf { it.isNotBlank() }
                    val email = map["email"]?.toString()
                    subtitle = listOfNotNull(phone, email).joinToString(" | ").ifBlank { "No contact info" }
                }
                "ticket" -> {
                    val orderId = map["order_id"]?.toString() ?: "T-$id"
                    title = orderId
                    val status = map["status_name"]?.toString() ?: map["status"]?.toString() ?: ""
                    val customer = map["customer_name"]?.toString() ?: ""
                    subtitle = listOf(status, customer).filter { it.isNotBlank() }.joinToString(" - ").ifBlank { "Ticket" }
                }
                "inventory" -> {
                    title = map["name"]?.toString() ?: "Item #$id"
                    val sku = map["sku"]?.toString()
                    val stock = map["in_stock"]?.toString()
                    subtitle = listOfNotNull(
                        sku?.let { "SKU: $it" },
                        stock?.let { "Stock: $it" },
                    ).joinToString(" | ").ifBlank { "Inventory item" }
                }
                "invoice" -> {
                    val orderId = map["order_id"]?.toString() ?: "INV-$id"
                    title = orderId
                    val status = map["status"]?.toString() ?: ""
                    // @audit-fixed: was "$$it" which renders as "$$value" — use locale-aware
                    // currency formatter so totals show as "$12.34" instead of garbled "$$12.34"
                    val total = (map["total"] as? Number)?.toDouble()
                    subtitle = listOfNotNull(
                        status.ifBlank { null },
                        total?.let { com.bizarreelectronics.crm.util.CurrencyFormatter.format(it) },
                    ).joinToString(" - ").ifBlank { "Invoice" }
                }
                else -> {
                    title = map["name"]?.toString() ?: "#$id"
                    subtitle = type
                }
            }

            SearchResult(type = type, id = id, title = title, subtitle = subtitle)
        }
    }
}

// ---------------------------------------------------------------------------
// Inline search field matching Wave 2 SearchBar visual spec, with focus support
// ---------------------------------------------------------------------------

/**
 * Search field styled to Wave 2 spec: filled surfaceVariant bg, 16dp radius,
 * teal leading icon, muted clear icon, no underline indicator.
 * Accepts [focusRequester] and [keyboardOptions] for the TopAppBar inline use case
 * where the shared [SearchBar] composable cannot be used directly (it lacks those
 * parameters). Visually identical to the shared component.
 */
@Composable
private fun InlineSearchField(
    query: String,
    onQueryChange: (String) -> Unit,
    focusRequester: FocusRequester,
    modifier: Modifier = Modifier,
) {
    TextField(
        value = query,
        onValueChange = onQueryChange,
        modifier = modifier
            .fillMaxWidth()
            .focusRequester(focusRequester),
        placeholder = {
            Text(
                "Search everything...",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodyMedium,
            )
        },
        leadingIcon = {
            Icon(
                Icons.Default.Search,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.secondary, // teal
            )
        },
        trailingIcon = {
            if (query.isNotEmpty()) {
                IconButton(onClick = { onQueryChange("") }) {
                    Icon(
                        Icons.Default.Clear,
                        contentDescription = "Clear",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        },
        singleLine = true,
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
        shape = RoundedCornerShape(16.dp),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
            unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
            disabledContainerColor = MaterialTheme.colorScheme.surfaceVariant,
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
            disabledIndicatorColor = Color.Transparent,
        ),
    )
}

// ---------------------------------------------------------------------------
// Result-group header — display-condensed ALL-CAPS (sanctioned use)
// ---------------------------------------------------------------------------

@Composable
private fun GroupHeader(type: String) {
    val label = when (type) {
        "customer"  -> "CUSTOMERS"
        "ticket"    -> "TICKETS"
        "inventory" -> "INVENTORY"
        "invoice"   -> "INVOICES"
        else        -> type.uppercase()
    }
    Text(
        text = label,
        style = MaterialTheme.typography.headlineMedium, // Barlow Condensed SemiBold via Typography.kt
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
    )
}

// ---------------------------------------------------------------------------
// No-results placeholder — EmptyState visual layout without the WaveDivider
// (wave is reserved for the idle/prompt state)
// ---------------------------------------------------------------------------

@Composable
private fun NoResultsState(query: String) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 48.dp, vertical = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(
            Icons.Default.SearchOff,
            contentDescription = null,
            modifier = Modifier.size(36.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
        )
        Text(
            "No results",
            style = MaterialTheme.typography.headlineMedium, // Barlow Condensed SemiBold
            color = MaterialTheme.colorScheme.onSurface,
        )
        Text(
            "Nothing matched \"$query\"",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.secondary, // teal
        )
    }
}

// ---------------------------------------------------------------------------
// GlobalSearchScreen
// ---------------------------------------------------------------------------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GlobalSearchScreen(
    onResult: (String, Long) -> Unit,
    viewModel: GlobalSearchViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val focusRequester = remember { FocusRequester() }

    LaunchedEffect(Unit) {
        focusRequester.requestFocus()
    }

    Scaffold(
        modifier = Modifier.imePadding(),
        topBar = {
            // Keep the inline-search-in-TopAppBar pattern; re-skin to Wave 2 spec.
            // Field bg = surfaceVariant (surface2), teal leading icon, no outline border
            // since it sits inside the bar surface. TopAppBar uses surface1 container
            // so the field's surfaceVariant bg provides a subtle lift.
            TopAppBar(
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                ),
                title = {
                    InlineSearchField(
                        query = state.query,
                        onQueryChange = viewModel::updateQuery,
                        focusRequester = focusRequester,
                    )
                },
            )
        },
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            when {
                // Idle — user hasn't typed anything yet. EmptyState includes WaveDivider.
                state.query.isBlank() -> {
                    EmptyState(
                        icon = Icons.Default.Search,
                        title = "Search",
                        subtitle = "Tickets, customers, inventory, invoices",
                    )
                }

                // Loading — in-toolbar spinner style (search is a focused action, not a list load)
                state.isLoading -> {
                    LoadingIndicator(modifier = Modifier.align(Alignment.Center))
                }

                // Error
                state.error != null -> {
                    ErrorState(
                        message = state.error ?: "Search failed",
                        onRetry = null,
                    )
                }

                // No results — EmptyState layout without WaveDivider (wave reserved for idle)
                state.hasSearched && state.results.isEmpty() -> {
                    NoResultsState(query = state.query)
                }

                // Results grouped by type
                else -> {
                    val groupedResults = state.results.groupBy { it.type }
                    LazyColumn(modifier = Modifier.fillMaxSize()) {
                        groupedResults.forEach { (type, results) ->
                            item(key = "header-$type") {
                                GroupHeader(type = type)
                            }
                            items(results, key = { "${it.type}-${it.id}" }) { result ->
                                val icon = when (result.type) {
                                    "ticket"    -> Icons.Default.ConfirmationNumber
                                    "customer"  -> Icons.Default.Person
                                    "inventory" -> Icons.Default.Inventory2
                                    "invoice"   -> Icons.Default.Receipt
                                    else        -> Icons.Default.Article
                                }
                                ListItem(
                                    modifier = Modifier.clickable { onResult(result.type, result.id) },
                                    headlineContent = {
                                        Text(
                                            result.title,
                                            style = MaterialTheme.typography.bodyMedium,
                                        )
                                    },
                                    supportingContent = {
                                        Text(
                                            result.subtitle,
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    },
                                    leadingContent = {
                                        Icon(
                                            icon,
                                            contentDescription = result.type,
                                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    },
                                    trailingContent = {
                                        // Type badge: surfaceVariant bg + single-hue text
                                        BrandStatusBadge(
                                            label = when (result.type) {
                                                "customer"  -> "Customer"
                                                "ticket"    -> "Ticket"
                                                "inventory" -> "Inventory"
                                                "invoice"   -> "Invoice"
                                                else        -> result.type.replaceFirstChar { it.uppercase() }
                                            },
                                            status = result.type,
                                        )
                                    },
                                )
                                HorizontalDivider(
                                    color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
                                    thickness = 1.dp,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
