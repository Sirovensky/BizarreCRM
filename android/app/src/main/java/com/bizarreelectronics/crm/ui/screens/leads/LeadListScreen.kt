package com.bizarreelectronics.crm.ui.screens.leads

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.entities.LeadEntity
import com.bizarreelectronics.crm.data.repository.LeadRepository
import com.bizarreelectronics.crm.ui.components.WaveDivider
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandStatusBadge
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.components.shared.statusToneFor
import com.bizarreelectronics.crm.util.PhoneFormatter
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class LeadListUiState(
    val leads: List<LeadEntity> = emptyList(),
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val searchQuery: String = "",
    val selectedStatus: String = "All",
)

/**
 * View mode toggle for the Leads screen (ActionPlan §9).
 *
 * [LIST] renders the existing flat list; [KANBAN] renders the pipeline board.
 */
enum class ViewMode { LIST, KANBAN }

/**
 * Status label lookup. Keys match the server's lowercase status strings.
 * Colors are intentionally removed — [BrandStatusBadge] / [statusToneFor]
 * provide the 5-hue brand discipline instead of the old 7-color rainbow.
 */
private data class LeadStatusMeta(
    val key: String,
    val label: String,
)

private val LEAD_STATUSES = listOf(
    LeadStatusMeta("new", "New"),
    LeadStatusMeta("contacted", "Contacted"),
    LeadStatusMeta("scheduled", "Scheduled"),
    LeadStatusMeta("qualified", "Qualified"),
    LeadStatusMeta("proposal", "Proposal"),
    LeadStatusMeta("converted", "Converted"),
    LeadStatusMeta("lost", "Lost"),
)

private fun statusLabelFor(status: String?): String {
    if (status.isNullOrBlank()) return ""
    return LEAD_STATUSES.firstOrNull { it.key.equals(status, ignoreCase = true) }?.label
        ?: status
}

@HiltViewModel
class LeadListViewModel @Inject constructor(
    private val leadRepository: LeadRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(LeadListUiState())
    val state = _state.asStateFlow()

    private var searchJob: Job? = null
    private var collectJob: Job? = null

    init {
        collectLeads()
    }

    fun loadLeads() = collectLeads()

    private fun collectLeads() {
        collectJob?.cancel()
        collectJob = viewModelScope.launch {
            _state.value = _state.value.copy(
                isLoading = _state.value.leads.isEmpty(),
                error = null,
            )
            val query = _state.value.searchQuery.trim()
            val status = _state.value.selectedStatus

            val flow = when {
                query.isNotEmpty() -> leadRepository.searchLeads(query)
                status == "Open" -> leadRepository.getOpenLeads()
                else -> leadRepository.getLeads()
            }

            flow.collect { leads ->
                val filtered = when (status) {
                    "All", "Open" -> leads
                    else -> leads.filter {
                        it.status.equals(status, ignoreCase = true)
                    }
                }
                _state.value = _state.value.copy(
                    leads = filtered,
                    isLoading = false,
                    isRefreshing = false,
                )
            }
        }
    }

    fun refresh() {
        _state.value = _state.value.copy(isRefreshing = true)
        collectLeads()
    }

    fun onSearchChanged(query: String) {
        _state.value = _state.value.copy(searchQuery = query)
        searchJob?.cancel()
        searchJob = viewModelScope.launch {
            delay(300)
            collectLeads()
        }
    }

    fun onStatusChanged(status: String) {
        _state.value = _state.value.copy(selectedStatus = status)
        collectLeads()
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LeadListScreen(
    onLeadClick: (Long) -> Unit,
    onCreateClick: () -> Unit,
    viewModel: LeadListViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val filters = listOf(
        "All", "Open", "New", "Contacted", "Scheduled",
        "Qualified", "Proposal", "Converted", "Lost",
    )
    val listState = rememberLazyListState()

    // §9: view-mode toggle — List (default) or Kanban pipeline board.
    var viewMode by remember { mutableStateOf(ViewMode.LIST) }

    // Derived grouping for Kanban — computed only when leads change and the
    // kanban view is active. Immutable: groupBy returns a new map each time.
    val leadsByStage by remember(state.leads) {
        derivedStateOf { state.leads.groupBy { it.status ?: "new" } }
    }

    Scaffold(
        topBar = {
            // CROSS45: WaveDivider docked directly below the TopAppBar — canonical
            // placement for every list screen.
            Column {
                TopAppBar(
                    title = { Text("Leads") },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = MaterialTheme.colorScheme.surface,
                    ),
                    actions = {
                        // §9: List / Kanban toggle pair.
                        IconButton(
                            onClick = { viewMode = ViewMode.LIST },
                            modifier = Modifier.semantics {
                                contentDescription = "Switch to list view"
                            },
                        ) {
                            Icon(
                                Icons.Default.ViewList,
                                contentDescription = null,
                                tint = if (viewMode == ViewMode.LIST)
                                    MaterialTheme.colorScheme.primary
                                else
                                    MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        IconButton(
                            onClick = { viewMode = ViewMode.KANBAN },
                            modifier = Modifier.semantics {
                                contentDescription = "Switch to kanban view"
                            },
                        ) {
                            Icon(
                                Icons.Default.ViewKanban,
                                contentDescription = null,
                                tint = if (viewMode == ViewMode.KANBAN)
                                    MaterialTheme.colorScheme.primary
                                else
                                    MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        IconButton(onClick = { viewModel.loadLeads() }) {
                            Icon(
                                Icons.Default.Refresh,
                                contentDescription = "Refresh",
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
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
                Icon(Icons.Default.Add, contentDescription = "Create Lead")
            }
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .imePadding(),
        ) {
            // Search bar — shared brand SearchBar
            com.bizarreelectronics.crm.ui.components.shared.SearchBar(
                query = state.searchQuery,
                onQueryChange = { viewModel.onSearchChanged(it) },
                placeholder = "Search leads...",
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )

            // Status filter chips
            LazyRow(
                modifier = Modifier.padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(filters, key = { it }) { filter ->
                    FilterChip(
                        selected = state.selectedStatus == filter,
                        onClick = { viewModel.onStatusChanged(filter) },
                        label = { Text(filter) },
                    )
                }
            }

            // Lead count — demoted to muted labelSmall
            if (!state.isLoading && state.leads.isNotEmpty()) {
                Text(
                    "${state.leads.size} ${if (state.leads.size == 1) "lead" else "leads"}",
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            Spacer(modifier = Modifier.height(4.dp))

            when {
                state.isLoading -> {
                    BrandSkeleton(
                        rows = 6,
                        modifier = Modifier.padding(horizontal = 16.dp),
                    )
                }
                state.error != null -> {
                    ErrorState(
                        message = state.error ?: "Error loading leads",
                        onRetry = { viewModel.loadLeads() },
                    )
                }
                state.leads.isEmpty() -> {
                    EmptyState(
                        icon = Icons.Default.PersonSearch,
                        title = "No leads found",
                        subtitle = "Add a lead with the + button below",
                    )
                }
                viewMode == ViewMode.KANBAN -> {
                    // §9: Kanban pipeline board — horizontally scrollable columns
                    // grouped by status. Stage-change callback is a no-op here;
                    // wiring a dropdown/dialog is deferred (drag-drop wave).
                    LeadKanbanBoard(
                        leadsByStage = leadsByStage,
                        stageOrder = DEFAULT_STAGE_ORDER,
                        onLeadClick = onLeadClick,
                        onStageChangeRequest = { _, _ -> /* deferred */ },
                        modifier = Modifier.fillMaxSize(),
                    )
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
                            contentPadding = PaddingValues(
                                start = 16.dp,
                                end = 16.dp,
                                top = 8.dp,
                                bottom = 80.dp,
                            ),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            items(state.leads, key = { it.id }) { lead ->
                                LeadCard(lead = lead, onClick = { onLeadClick(lead.id) })
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun LeadCard(lead: LeadEntity, onClick: () -> Unit) {
    // D5-3: use Card(onClick = ...) overload so the M3 ripple renders from the
    // first tap. Chaining .clickable on a Card without onClick broke tactile
    // feedback because the Card surface drew OVER the ripple indication.
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier
                .padding(16.dp)
                .fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.Top,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                val orderId = lead.orderId
                if (!orderId.isNullOrBlank()) {
                    Text(
                        orderId,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                val fullName = listOfNotNull(lead.firstName, lead.lastName)
                    .joinToString(" ")
                    .ifBlank { "Unknown" }
                Text(
                    fullName,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                if (!lead.phone.isNullOrBlank()) {
                    Text(
                        PhoneFormatter.format(lead.phone),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                if (!lead.source.isNullOrBlank()) {
                    Spacer(modifier = Modifier.height(2.dp))
                    Text(
                        "Source: ${lead.source}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Column(horizontalAlignment = Alignment.End) {
                // 5-hue brand badge — replaces rainbow Surface(color = hardcodedHex)
                val statusLabel = statusLabelFor(lead.status).ifBlank { lead.status ?: "" }
                BrandStatusBadge(
                    label = statusLabel,
                    status = lead.status ?: "",
                )
                Spacer(modifier = Modifier.height(6.dp))
                Text(
                    "Score: ${lead.leadScore}",
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.Medium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}
