package com.bizarreelectronics.crm.ui.screens.tickets

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.entities.TicketEntity
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.repository.TicketRepository
import com.bizarreelectronics.crm.ui.components.shared.BrandListItem
import com.bizarreelectronics.crm.ui.components.shared.BrandListItemDivider
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandStatusBadge
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.components.shared.SearchBar
import com.bizarreelectronics.crm.ui.components.shared.statusToneFor
import com.bizarreelectronics.crm.ui.theme.BrandMono
import com.bizarreelectronics.crm.util.formatAsMoney
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class TicketListUiState(
    val tickets: List<TicketEntity> = emptyList(),
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val searchQuery: String = "",
    val selectedFilter: String = "All",
)

@HiltViewModel
class TicketListViewModel @Inject constructor(
    private val ticketRepository: TicketRepository,
    private val authPreferences: AuthPreferences,
) : ViewModel() {

    private val _state = MutableStateFlow(TicketListUiState())
    val state = _state.asStateFlow()

    private var searchJob: Job? = null
    private var collectJob: Job? = null

    init {
        collectTickets()
    }

    fun loadTickets() = collectTickets()

    private fun collectTickets() {
        collectJob?.cancel()
        collectJob = viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = _state.value.tickets.isEmpty(), error = null)
            val query = _state.value.searchQuery.trim()
            val filter = _state.value.selectedFilter

            val flow = when {
                query.isNotEmpty() -> ticketRepository.searchTickets(query)
                filter == "My Tickets" -> ticketRepository.getByAssignedTo(authPreferences.userId)
                filter == "Open" || filter == "In Progress" || filter == "Waiting" -> ticketRepository.getOpenTickets()
                filter == "Closed" -> ticketRepository.getTickets() // Room doesn't have closed-only query, filter in-memory
                else -> ticketRepository.getTickets()
            }

            flow.collect { tickets ->
                val filtered = if (filter == "Closed") {
                    tickets.filter { it.statusIsClosed }
                } else if (filter == "In Progress") {
                    tickets.filter { it.statusName.equals("In Progress", ignoreCase = true) }
                } else if (filter == "Waiting") {
                    tickets.filter { it.statusName.equals("Waiting", ignoreCase = true) || it.statusName.equals("Waiting for Parts", ignoreCase = true) }
                } else {
                    tickets
                }
                _state.value = _state.value.copy(
                    tickets = filtered,
                    isLoading = false,
                    isRefreshing = false,
                )
            }
        }
    }

    fun refresh() {
        _state.value = _state.value.copy(isRefreshing = true)
        collectTickets()
    }

    fun onSearchChanged(query: String) {
        _state.value = _state.value.copy(searchQuery = query)
        searchJob?.cancel()
        searchJob = viewModelScope.launch {
            delay(300)
            collectTickets()
        }
    }

    fun onFilterChanged(filter: String) {
        _state.value = _state.value.copy(selectedFilter = filter)
        collectTickets()
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TicketListScreen(
    onTicketClick: (Long) -> Unit,
    onCreateClick: () -> Unit,
    viewModel: TicketListViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val filters = listOf("All", "My Tickets", "Open", "In Progress", "Waiting", "Closed")
    val listState = rememberLazyListState()

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Tickets",
                actions = {
                    IconButton(onClick = { viewModel.loadTickets() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
                    }
                },
            )
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = onCreateClick,
                containerColor = MaterialTheme.colorScheme.primary,
            ) {
                Icon(Icons.Default.Add, contentDescription = "Create Ticket")
            }
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .imePadding(),
        ) {
            // Search bar
            SearchBar(
                query = state.searchQuery,
                onQueryChange = { viewModel.onSearchChanged(it) },
                placeholder = "Search tickets...",
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
            )

            // Filter chips + count pill in same row
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                LazyRow(
                    modifier = Modifier.weight(1f),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(filters) { filter ->
                        FilterChip(
                            selected = state.selectedFilter == filter,
                            onClick = { viewModel.onFilterChanged(filter) },
                            label = { Text(filter) },
                        )
                    }
                }
                if (!state.isLoading && state.tickets.isNotEmpty()) {
                    Surface(
                        shape = MaterialTheme.shapes.small,
                        color = MaterialTheme.colorScheme.surfaceVariant,
                        modifier = Modifier.padding(start = 8.dp),
                    ) {
                        Text(
                            "${state.tickets.size}",
                            modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(4.dp))

            when {
                state.isLoading -> {
                    BrandSkeleton(rows = 6, modifier = Modifier.padding(top = 8.dp))
                }
                state.error != null -> {
                    ErrorState(
                        message = state.error ?: "Failed to load tickets",
                        onRetry = { viewModel.loadTickets() },
                    )
                }
                state.tickets.isEmpty() -> {
                    @OptIn(ExperimentalMaterial3Api::class)
                    androidx.compose.material3.pulltorefresh.PullToRefreshBox(
                        isRefreshing = state.isRefreshing,
                        onRefresh = { viewModel.refresh() },
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        EmptyState(
                            icon = Icons.Default.ConfirmationNumber,
                            title = "No tickets found",
                            subtitle = if (state.searchQuery.isNotEmpty()) "Try a different search" else "Create a ticket to get started",
                        )
                    }
                }
                else -> {
                    @OptIn(ExperimentalMaterial3Api::class)
                    androidx.compose.material3.pulltorefresh.PullToRefreshBox(
                        isRefreshing = state.isRefreshing,
                        onRefresh = { viewModel.refresh() },
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        LazyColumn(
                            state = listState,
                            contentPadding = PaddingValues(vertical = 8.dp),
                        ) {
                            items(state.tickets, key = { it.id }) { ticket ->
                                TicketListRow(
                                    ticket = ticket,
                                    onClick = { onTicketClick(ticket.id) },
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

/**
 * Single ticket list row. Uses [BrandListItem] for the brand left-accent
 * pattern. Ticket order ID is displayed in [BrandMono]; status uses
 * [BrandStatusBadge] for the 5-hue discipline.
 *
 * NOTE: The server-provided `ticket.statusColor` hex is intentionally NOT used
 * here — the rainbow parse has been replaced by the 5-hue StatusTone mapping
 * via [BrandStatusBadge]. The raw color field is left on the entity for
 * backward-compat (CROSS-PLATFORM: seed migration needed on server side).
 */
@Composable
private fun TicketListRow(ticket: TicketEntity, onClick: () -> Unit) {
    BrandListItem(
        headline = {
            Text(
                ticket.orderId,
                style = BrandMono.copy(
                    fontSize = MaterialTheme.typography.titleSmall.fontSize,
                ),
                fontWeight = FontWeight.Medium,
                color = MaterialTheme.colorScheme.onSurface,
            )
        },
        support = {
            Text(
                ticket.customerName ?: "Unknown",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            val deviceName = ticket.firstDeviceName
            if (!deviceName.isNullOrBlank()) {
                Text(
                    deviceName,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
        trailing = {
            Column(horizontalAlignment = Alignment.End) {
                val statusName = ticket.statusName ?: ""
                if (statusName.isNotEmpty()) {
                    BrandStatusBadge(label = statusName, status = statusName)
                }
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    ticket.total.formatAsMoney(),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.primary,
                    fontWeight = FontWeight.Medium,
                )
            }
        },
        onClick = onClick,
    )
}
