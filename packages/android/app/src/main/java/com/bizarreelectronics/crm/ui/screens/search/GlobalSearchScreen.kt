package com.bizarreelectronics.crm.ui.screens.search

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.dao.CustomerDao
import com.bizarreelectronics.crm.data.local.db.dao.InventoryDao
import com.bizarreelectronics.crm.data.local.db.dao.TicketDao
import com.bizarreelectronics.crm.data.remote.api.SearchApi
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
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
                val contact = listOfNotNull(c.phone ?: c.mobile, c.email).joinToString(" | ").ifBlank { "No contact info" }
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
                    val phone = map["phone"]?.toString() ?: map["mobile"]?.toString()
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
            TopAppBar(
                title = {
                    OutlinedTextField(
                        value = state.query,
                        onValueChange = viewModel::updateQuery,
                        modifier = Modifier
                            .fillMaxWidth()
                            .focusRequester(focusRequester),
                        placeholder = { Text("Search everything...") },
                        singleLine = true,
                        // @audit-fixed: keyboard had no Search action; users were stuck
                        // with the default newline button which didn't trigger anything.
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                        trailingIcon = {
                            if (state.query.isNotEmpty()) {
                                IconButton(onClick = { viewModel.updateQuery("") }) {
                                    Icon(Icons.Default.Clear, contentDescription = "Clear")
                                }
                            }
                        },
                    )
                },
            )
        },
    ) { padding ->
        when {
            state.query.isBlank() -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(
                            Icons.Default.Search,
                            contentDescription = null,
                            modifier = Modifier.size(48.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            "Search tickets, customers, inventory, invoices",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            state.isLoading -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            }

            state.error != null -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        state.error ?: "Search failed",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            }

            state.hasSearched && state.results.isEmpty() -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        "No results for \"${state.query}\"",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            else -> {
                val groupedResults = state.results.groupBy { it.type }
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                ) {
                    groupedResults.forEach { (type, results) ->
                        item(key = "header-$type") {
                            Text(
                                text = when (type) {
                                    "customer" -> "Customers"
                                    "ticket" -> "Tickets"
                                    "inventory" -> "Inventory"
                                    "invoice" -> "Invoices"
                                    else -> type.replaceFirstChar { it.uppercase() }
                                },
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                            )
                        }
                        items(results, key = { "${it.type}-${it.id}" }) { result ->
                            val icon = when (result.type) {
                                "ticket" -> Icons.Default.ConfirmationNumber
                                "customer" -> Icons.Default.Person
                                "inventory" -> Icons.Default.Inventory2
                                "invoice" -> Icons.Default.Receipt
                                else -> Icons.Default.Article
                            }
                            ListItem(
                                modifier = Modifier.clickable { onResult(result.type, result.id) },
                                headlineContent = { Text(result.title, fontWeight = FontWeight.Medium) },
                                supportingContent = { Text(result.subtitle) },
                                leadingContent = { Icon(icon, contentDescription = result.type) },
                                trailingContent = {
                                    Surface(
                                        shape = MaterialTheme.shapes.small,
                                        color = MaterialTheme.colorScheme.surfaceVariant,
                                    ) {
                                        Text(
                                            result.type.replaceFirstChar { it.uppercase() },
                                            modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                                            style = MaterialTheme.typography.labelSmall,
                                        )
                                    }
                                },
                            )
                            HorizontalDivider()
                        }
                    }
                }
            }
        }
    }
}
