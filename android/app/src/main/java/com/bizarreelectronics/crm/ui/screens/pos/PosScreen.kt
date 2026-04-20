package com.bizarreelectronics.crm.ui.screens.pos

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
import com.bizarreelectronics.crm.data.local.db.entities.TicketEntity
import com.bizarreelectronics.crm.data.repository.TicketRepository
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandStatusBadge
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.components.shared.statusToneFor
import com.bizarreelectronics.crm.ui.theme.BrandMono
import com.bizarreelectronics.crm.util.formatAsMoney
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class PosUiState(
    val isLoading: Boolean = true,
    val recentTickets: List<TicketEntity> = emptyList(),
    val error: String? = null,
)

@HiltViewModel
class PosViewModel @Inject constructor(
    private val ticketRepository: TicketRepository,
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
                // Collect from Room Flow (TicketRepository triggers background API refresh if online)
                ticketRepository.getTickets().collect { tickets ->
                    _state.update {
                        it.copy(
                            isLoading = false,
                            recentTickets = tickets.take(5),
                        )
                    }
                }
            } catch (e: Exception) {
                _state.update { it.copy(isLoading = false, error = e.message ?: "Failed to load tickets.") }
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

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        "Point of Sale",
                        style = MaterialTheme.typography.titleMedium,
                    )
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                    titleContentColor = MaterialTheme.colorScheme.onSurface,
                    actionIconContentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                ),
            )
        },
        // CROSS14 / user 2026-04-16: New Repair moved from inline button to FAB
        // for parity with every other list screen (Tickets/Customers/Inventory
        // etc.). Quick Sale button previously sat next to it and has been
        // removed until the cart/checkout flow ships on Android.
        floatingActionButton = {
            FloatingActionButton(
                onClick = onNavigateToTicketCreate,
                containerColor = MaterialTheme.colorScheme.primary,
                contentColor = MaterialTheme.colorScheme.onPrimary,
            ) {
                Icon(Icons.Default.Build, contentDescription = "New Repair")
            }
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
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
                    BrandSkeleton(rows = 5)
                }
            } else if (state.error != null) {
                item {
                    ErrorState(
                        message = state.error ?: "Error",
                        onRetry = { viewModel.loadRecentTickets() },
                    )
                }
            } else if (state.recentTickets.isEmpty()) {
                item {
                    EmptyState(
                        icon = Icons.Default.ConfirmationNumber,
                        title = "No recent tickets",
                        subtitle = "New repairs will appear here",
                    )
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
    ticket: TicketEntity,
    onClick: () -> Unit,
) {
    // D5-3: use Card(onClick = ...) overload so the ripple indication fires
    // on tap. Prior .clickable-on-top-of-Card pattern suppressed tactile
    // feedback because the surface drew over the ripple.
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
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
                    // Ticket ID in BrandMono — fixed-width data display
                    Text(
                        ticket.orderId,
                        style = BrandMono,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    val sName = ticket.statusName
                    if (sName != null) {
                        // Fully migrated to BrandStatusBadge (5-hue discipline)
                        BrandStatusBadge(
                            label = sName,
                            status = sName,
                        )
                    }
                }
                val customerName = ticket.customerName
                if (!customerName.isNullOrBlank() && customerName != "Unknown") {
                    Text(
                        customerName,
                        style = MaterialTheme.typography.bodyMedium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                val deviceName = ticket.firstDeviceName
                if (!deviceName.isNullOrBlank()) {
                    Text(
                        deviceName,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            if (ticket.total > 0) {
                Text(
                    ticket.total.formatAsMoney(),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
        }
    }
}
