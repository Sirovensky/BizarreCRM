package com.bizarreelectronics.crm.ui.screens.pos

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.TicketApi
import com.bizarreelectronics.crm.data.remote.dto.TicketListItem
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class PosUiState(
    val isLoading: Boolean = true,
    val recentTickets: List<TicketListItem> = emptyList(),
    val error: String? = null,
)

@HiltViewModel
class PosViewModel @Inject constructor(
    private val ticketApi: TicketApi,
) : ViewModel() {

    private val _state = MutableStateFlow(PosUiState())
    val state: StateFlow<PosUiState> = _state.asStateFlow()

    init {
        loadRecentTickets()
    }

    fun loadRecentTickets() {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, error = null) }
            try {
                val response = ticketApi.getTickets(mapOf("pagesize" to "5"))
                if (response.success && response.data != null) {
                    _state.update { it.copy(isLoading = false, recentTickets = response.data.tickets) }
                } else {
                    _state.update { it.copy(isLoading = false, error = response.message ?: "Failed to load tickets.") }
                }
            } catch (e: Exception) {
                _state.update { it.copy(isLoading = false, error = e.message ?: "Network error.") }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PosScreen(
    onNavigateToTicketCreate: () -> Unit = {},
    onNavigateToTicket: (Long) -> Unit = {},
    viewModel: PosViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    var showQuickSaleSnackbar by remember { mutableStateOf(false) }

    LaunchedEffect(showQuickSaleSnackbar) {
        if (showQuickSaleSnackbar) {
            snackbarHostState.showSnackbar("Quick Sale: Coming soon")
            showQuickSaleSnackbar = false
        }
    }

    Scaffold(
        topBar = { TopAppBar(title = { Text("Point of Sale") }) },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // Quick actions
            item {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Button(
                        onClick = onNavigateToTicketCreate,
                        modifier = Modifier.weight(1f),
                        contentPadding = PaddingValues(vertical = 16.dp),
                    ) {
                        Icon(Icons.Default.Build, contentDescription = null, modifier = Modifier.size(20.dp))
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("New Repair")
                    }
                    OutlinedButton(
                        onClick = { showQuickSaleSnackbar = true },
                        modifier = Modifier.weight(1f),
                        contentPadding = PaddingValues(vertical = 16.dp),
                    ) {
                        Icon(Icons.Default.ShoppingCart, contentDescription = null, modifier = Modifier.size(20.dp))
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Quick Sale")
                    }
                }
            }

            // Recent tickets header
            item {
                Text(
                    "Recent Tickets",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
            }

            // Loading / error / content
            if (state.isLoading) {
                item {
                    Box(modifier = Modifier.fillMaxWidth().height(120.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                }
            } else if (state.error != null) {
                item {
                    Card(
                        modifier = Modifier.fillMaxWidth(),
                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer),
                    ) {
                        Column(
                            modifier = Modifier.padding(16.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            Text(state.error ?: "Error", color = MaterialTheme.colorScheme.onErrorContainer)
                            Spacer(modifier = Modifier.height(8.dp))
                            OutlinedButton(onClick = { viewModel.loadRecentTickets() }) { Text("Retry") }
                        }
                    }
                }
            } else if (state.recentTickets.isEmpty()) {
                item {
                    Card(
                        modifier = Modifier.fillMaxWidth(),
                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
                    ) {
                        Box(
                            modifier = Modifier.fillMaxWidth().padding(32.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                "No recent tickets",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            } else {
                items(state.recentTickets, key = { it.id }) { ticket ->
                    RecentTicketCard(
                        ticket = ticket,
                        onClick = { onNavigateToTicket(ticket.id) },
                    )
                }
            }
        }
    }
}

@Composable
private fun RecentTicketCard(
    ticket: TicketListItem,
    onClick: () -> Unit,
) {
    val statusColor = try {
        if (!ticket.statusColor.isNullOrBlank()) {
            androidx.compose.ui.graphics.Color(android.graphics.Color.parseColor(ticket.statusColor))
        } else {
            null
        }
    } catch (_: Exception) {
        null
    }

    Card(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.Top,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(
                        ticket.orderId,
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Bold,
                    )
                    val sName = ticket.statusName
                    if (sName != null) {
                        Surface(
                            shape = MaterialTheme.shapes.small,
                            color = statusColor?.copy(alpha = 0.15f) ?: MaterialTheme.colorScheme.surfaceVariant,
                        ) {
                            Text(
                                sName,
                                modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                                style = MaterialTheme.typography.labelSmall,
                                color = statusColor ?: MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
                if (ticket.customerName != "Unknown") {
                    Text(
                        ticket.customerName,
                        style = MaterialTheme.typography.bodyMedium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                val deviceNames = ticket.firstDevice?.deviceName
                if (!deviceNames.isNullOrBlank()) {
                    Text(
                        deviceNames,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            if (ticket.total != null && ticket.total > 0) {
                Text(
                    "$${String.format("%.2f", ticket.total)}",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
        }
    }
}
