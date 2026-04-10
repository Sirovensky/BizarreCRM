package com.bizarreelectronics.crm.ui.screens.tickets

import androidx.compose.foundation.clickable
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.entities.TicketEntity
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.repository.TicketRepository
import com.bizarreelectronics.crm.ui.theme.contrastTextColor
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
            TopAppBar(
                title = { Text("Tickets") },
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
            OutlinedTextField(
                value = state.searchQuery,
                onValueChange = { viewModel.onSearchChanged(it) },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                placeholder = { Text("Search tickets...") },
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

            // Filter chips
            LazyRow(
                modifier = Modifier.padding(horizontal = 16.dp),
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

            // Ticket count
            if (!state.isLoading && state.tickets.isNotEmpty()) {
                Text(
                    "${state.tickets.size} tickets",
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            Spacer(modifier = Modifier.height(4.dp))

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
                            TextButton(onClick = { viewModel.loadTickets() }) { Text("Retry") }
                        }
                    }
                }
                state.tickets.isEmpty() -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Icon(Icons.Default.ConfirmationNumber, null, modifier = Modifier.size(48.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                            Spacer(modifier = Modifier.height(8.dp))
                            Text("No tickets found", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
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
                            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            items(state.tickets, key = { it.id }) { ticket ->
                                TicketCard(ticket = ticket, onClick = { onTicketClick(ticket.id) })
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun TicketCard(ticket: TicketEntity, onClick: () -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
    ) {
        Row(
            modifier = Modifier.padding(16.dp).fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(ticket.orderId, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                Text(ticket.customerName ?: "Unknown", style = MaterialTheme.typography.bodyMedium)
                val deviceName = ticket.firstDeviceName ?: ""
                if (deviceName.isNotEmpty()) {
                    Text(deviceName, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Column(horizontalAlignment = Alignment.End) {
                val statusBgColor = try { Color(android.graphics.Color.parseColor(ticket.statusColor ?: "#6b7280")) } catch (_: Exception) { MaterialTheme.colorScheme.primary }
                Surface(
                    shape = MaterialTheme.shapes.small,
                    color = statusBgColor,
                ) {
                    Text(
                        ticket.statusName ?: "",
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                        style = MaterialTheme.typography.labelSmall,
                        color = contrastTextColor(statusBgColor),
                    )
                }
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    String.format("$%.2f", ticket.total),
                    style = MaterialTheme.typography.bodySmall,
                    fontWeight = FontWeight.Medium,
                )
            }
        }
    }
}
