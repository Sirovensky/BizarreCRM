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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.entities.TicketEntity
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.SettingsApi
import com.bizarreelectronics.crm.data.repository.TicketRepository
import com.bizarreelectronics.crm.ui.components.WaveDivider
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
import com.bizarreelectronics.crm.ui.theme.LocalExtendedColors
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
    // CROSS1: ticket assignment feature toggle (ticket_all_employees_view_all == '0')
    val assignmentEnabled: Boolean = false,
)

@HiltViewModel
class TicketListViewModel @Inject constructor(
    private val ticketRepository: TicketRepository,
    private val authPreferences: AuthPreferences,
    private val settingsApi: SettingsApi,
) : ViewModel() {

    private val _state = MutableStateFlow(TicketListUiState())
    val state = _state.asStateFlow()

    private var searchJob: Job? = null
    private var collectJob: Job? = null

    init {
        collectTickets()
        loadAssignmentSetting()
    }

    private fun loadAssignmentSetting() {
        viewModelScope.launch {
            try {
                val cfg = settingsApi.getConfig().data ?: return@launch
                val enabled = cfg["ticket_all_employees_view_all"] == "0"
                _state.value = _state.value.copy(assignmentEnabled = enabled)
            } catch (_: Exception) {
                // Offline or server error — assume feature off (default). No filter-chip hiding change needed.
            }
        }
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
    // CROSS1: when ticket assignment feature is off (default), hide "My Tickets" chip.
    val filters = remember(state.assignmentEnabled) {
        if (state.assignmentEnabled) {
            listOf("All", "My Tickets", "Open", "In Progress", "Waiting", "Closed")
        } else {
            listOf("All", "Open", "In Progress", "Waiting", "Closed")
        }
    }
    val listState = rememberLazyListState()

    Scaffold(
        topBar = {
            // CROSS45: WaveDivider docked directly below the TopAppBar — canonical
            // placement for every list screen.
            Column {
                BrandTopAppBar(
                    title = "Tickets",
                    actions = {
                        IconButton(onClick = { viewModel.loadTickets() }) {
                            // a11y: "Refresh tickets" is more specific than generic "Refresh"
                            Icon(Icons.Default.Refresh, contentDescription = "Refresh tickets")
                        }
                    },
                )
                WaveDivider()
            }
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = onCreateClick,
                containerColor = MaterialTheme.colorScheme.primary,
            ) {
                // a11y: spec §26 — "Create new ticket" (imperative, lowercase "new")
                Icon(Icons.Default.Add, contentDescription = "Create new ticket")
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

            // a11y: "Status filter" heading so TalkBack can navigate directly to this section
            Text(
                "Status filter",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier
                    .padding(horizontal = 16.dp)
                    .semantics { heading() },
            )

            // Filter chips + count pill in same row
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                LazyRow(
                    modifier = Modifier.weight(1f),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    // CROSS23: trailing padding so the last chip ("Waiting") isn't
                    // clipped flush against the count pill.
                    contentPadding = PaddingValues(end = 24.dp),
                ) {
                    items(filters, key = { it }) { filter ->
                        val isSelected = state.selectedFilter == filter
                        FilterChip(
                            selected = isSelected,
                            onClick = { viewModel.onFilterChanged(filter) },
                            label = { Text(filter) },
                            // a11y: Role.Tab + selection state announcement; the chip's
                            // selected param already flips the chip visually; the
                            // semantics here make TalkBack say "<filter> filter, selected/not selected"
                            modifier = Modifier.semantics {
                                role = Role.Tab
                                contentDescription = if (isSelected) {
                                    "$filter filter, selected"
                                } else {
                                    "$filter filter, not selected"
                                }
                            },
                        )
                    }
                }
                if (!state.isLoading && state.tickets.isNotEmpty()) {
                    val ticketCount = state.tickets.size
                    Surface(
                        shape = MaterialTheme.shapes.small,
                        color = MaterialTheme.colorScheme.surfaceVariant,
                        modifier = Modifier.padding(start = 8.dp),
                    ) {
                        // a11y: liveRegion=Polite so TalkBack announces when the count changes
                        // after a filter switch, without interrupting the user mid-sentence.
                        Text(
                            "$ticketCount",
                            modifier = Modifier
                                .padding(horizontal = 8.dp, vertical = 3.dp)
                                .semantics {
                                    liveRegion = LiveRegionMode.Polite
                                    contentDescription = "$ticketCount tickets"
                                },
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(4.dp))

            when {
                state.isLoading -> {
                    // a11y: mergeDescendants + contentDescription so TalkBack announces
                    // "Loading tickets" on a single focus stop rather than reading
                    // each shimmer box individually.
                    Box(
                        modifier = Modifier.semantics(mergeDescendants = true) {
                            contentDescription = "Loading tickets"
                        },
                    ) {
                        BrandSkeleton(rows = 6, modifier = Modifier.padding(top = 8.dp))
                    }
                }
                state.error != null -> {
                    // a11y: liveRegion=Assertive interrupts TalkBack immediately so the
                    // user is not left wondering why the list is empty after a network failure.
                    Box(
                        modifier = Modifier.semantics {
                            liveRegion = LiveRegionMode.Assertive
                        },
                    ) {
                        ErrorState(
                            message = state.error ?: "Failed to load tickets",
                            onRetry = { viewModel.loadTickets() },
                        )
                    }
                }
                state.tickets.isEmpty() -> {
                    @OptIn(ExperimentalMaterial3Api::class)
                    androidx.compose.material3.pulltorefresh.PullToRefreshBox(
                        isRefreshing = state.isRefreshing,
                        onRefresh = { viewModel.refresh() },
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        // a11y: mergeDescendants collapses the decorative icon + title + subtitle
                        // into one TalkBack node so the empty state reads as a single announcement.
                        Box(
                            modifier = Modifier.semantics(mergeDescendants = true) {},
                        ) {
                            EmptyState(
                                icon = Icons.Default.ConfirmationNumber,
                                title = "No tickets found",
                                subtitle = if (state.searchQuery.isNotEmpty()) "Try a different search" else "Create a ticket to get started",
                            )
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
                            // CROSS16-ext: bottom inset so the last row can
                            // scroll above the bottom-nav / gesture area.
                            contentPadding = PaddingValues(top = 8.dp, bottom = 80.dp),
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
    // a11y: build the full announcement string once so it can be used in semantics.
    // BrandListItem already applies mergeDescendants=true + Role.Button on its outer Row;
    // we add contentDescription here so TalkBack announces a single coherent sentence
    // instead of reading each child Text node individually.
    val statusLabel = ticket.statusName?.ifBlank { null }
    val deviceLabel = ticket.firstDeviceName?.ifBlank { null }
    val a11yDesc = buildString {
        append("Ticket ${ticket.orderId}")
        ticket.customerName?.let { append(", $it") }
        deviceLabel?.let { append(", $it") }
        statusLabel?.let { append(", status: $it") }
        append(", ${ticket.total.formatAsMoney()}")
        append(". Tap to open.")
    }

    BrandListItem(
        // a11y: contentDescription overrides the merged child-text reading; 48dp floor
        // ensures the row meets the Material 3 minimum touch target.
        modifier = Modifier
            .defaultMinSize(minHeight = 48.dp)
            .semantics { contentDescription = a11yDesc },
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
            // a11y: visual-only trailing column. The BrandListItem modifier-level
            // contentDescription already announces group + status + total for TalkBack;
            // these child composables are decorative within the merged row node.
            Column(horizontalAlignment = Alignment.End) {
                val statusName = ticket.statusName ?: ""
                if (statusName.isNotEmpty()) {
                    // NEW-TLIST-GRP: high-level group pill + specific status badge.
                    // Group mapping infers from the ticket's closed/cancelled flags
                    // and status-name heuristics (see [ticketStatusGroupFor]).
                    val group = ticketStatusGroupFor(ticket)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        TicketGroupPill(group = group)
                        Spacer(modifier = Modifier.width(6.dp))
                        BrandStatusBadge(label = statusName, status = statusName)
                    }
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

/**
 * NEW-TLIST-GRP: high-level ticket status grouping.
 *
 * Mirrors the server's `status_group` filter in `tickets.routes.ts` so a row
 * can be scanned at a glance: green Complete, grey Cancelled, amber Waiting,
 * primary In Progress. See [ticketStatusGroupFor] for the inference rules.
 */
private enum class TicketStatusGroup(val label: String) {
    Complete("Complete"),
    Cancelled("Cancelled"),
    Waiting("Waiting"),
    InProgress("In Progress"),
}

/**
 * NEW-TLIST-GRP: infer a high-level group for a ticket row.
 *
 * Spec mapping:
 *   - is_closed=1 AND is_cancelled=0  → Complete
 *   - is_cancelled=1                  → Cancelled
 *   - status name contains "waiting"  → Waiting
 *   - else                            → In Progress
 *
 * The Android [TicketEntity] does not carry `is_cancelled` as a dedicated
 * column (only `statusIsClosed`), so we fall back to a name-based check
 * ("cancel"/"void") to catch the small closed-set of cancellation statuses
 * seeded server-side. This matches the same "LIKE '%waiting%'" style already
 * spec'd for the Waiting group.
 */
private fun ticketStatusGroupFor(ticket: TicketEntity): TicketStatusGroup {
    val name = ticket.statusName?.trim()?.lowercase().orEmpty()
    val looksCancelled = name.contains("cancel") || name.contains("void")
    return when {
        looksCancelled -> TicketStatusGroup.Cancelled
        ticket.statusIsClosed -> TicketStatusGroup.Complete
        name.contains("waiting") -> TicketStatusGroup.Waiting
        else -> TicketStatusGroup.InProgress
    }
}

/**
 * NEW-TLIST-GRP: compact group pill using the 5-hue brand discipline.
 *
 * Colors:
 *   - Complete   → SuccessGreen
 *   - Cancelled  → onSurfaceVariant (muted grey)
 *   - Waiting    → tertiary (amber/magenta on brand palette)
 *   - InProgress → primary (orange)
 *
 * Renders as a small [Surface] pill to sit to the LEFT of the specific
 * status badge. Uses a surfaceVariant bg + single-hue text color, matching
 * the [BrandStatusBadge] visual weight.
 */
@Composable
private fun TicketGroupPill(group: TicketStatusGroup) {
    val extColors = LocalExtendedColors.current  // AND-036
    val textColor: Color = when (group) {
        TicketStatusGroup.Complete -> extColors.success
        TicketStatusGroup.Cancelled -> MaterialTheme.colorScheme.onSurfaceVariant
        TicketStatusGroup.Waiting -> MaterialTheme.colorScheme.tertiary
        TicketStatusGroup.InProgress -> MaterialTheme.colorScheme.primary
    }
    Surface(
        shape = MaterialTheme.shapes.small,
        color = MaterialTheme.colorScheme.surfaceVariant,
    ) {
        Text(
            text = group.label,
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
            style = MaterialTheme.typography.labelSmall,
            color = textColor,
            fontWeight = FontWeight.Medium,
        )
    }
}
