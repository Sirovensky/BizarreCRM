package com.bizarreelectronics.crm.ui.screens.leads

import androidx.compose.foundation.clickable
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.entities.LeadEntity
import com.bizarreelectronics.crm.data.repository.LeadRepository
import com.bizarreelectronics.crm.ui.theme.contrastTextColor
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
 * Status display metadata. The backend stores status as a lowercase string
 * (new, contacted, scheduled, qualified, proposal, converted, lost); this
 * list maps each to its label and color for the filter chips and badges.
 */
private data class LeadStatusMeta(
    val key: String,
    val label: String,
    val color: Color,
)

private val LEAD_STATUSES = listOf(
    LeadStatusMeta("new", "New", Color(0xFF3B82F6)),        // blue
    LeadStatusMeta("contacted", "Contacted", Color(0xFFF59E0B)), // amber
    LeadStatusMeta("scheduled", "Scheduled", Color(0xFF8B5CF6)), // purple
    LeadStatusMeta("qualified", "Qualified", Color(0xFF14B8A6)), // teal
    LeadStatusMeta("proposal", "Proposal", Color(0xFF6366F1)),   // indigo
    LeadStatusMeta("converted", "Converted", Color(0xFF16A34A)), // green
    LeadStatusMeta("lost", "Lost", Color(0xFFDC2626)),           // red
)

private fun statusMetaFor(status: String?): LeadStatusMeta? {
    if (status.isNullOrBlank()) return null
    return LEAD_STATUSES.firstOrNull { it.key.equals(status, ignoreCase = true) }
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

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Leads") },
                actions = {
                    IconButton(onClick = { viewModel.loadLeads() }) {
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
            // Search bar
            OutlinedTextField(
                value = state.searchQuery,
                onValueChange = { viewModel.onSearchChanged(it) },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                placeholder = { Text("Search leads...") },
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

            // Status filter chips
            LazyRow(
                modifier = Modifier.padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(filters) { filter ->
                    FilterChip(
                        selected = state.selectedStatus == filter,
                        onClick = { viewModel.onStatusChanged(filter) },
                        label = { Text(filter) },
                    )
                }
            }

            // Lead count
            if (!state.isLoading && state.leads.isNotEmpty()) {
                Text(
                    "${state.leads.size} leads",
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            Spacer(modifier = Modifier.height(4.dp))

            when {
                state.isLoading -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator()
                    }
                }
                state.error != null -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(state.error ?: "Error", color = MaterialTheme.colorScheme.error)
                            Spacer(modifier = Modifier.height(8.dp))
                            TextButton(onClick = { viewModel.loadLeads() }) { Text("Retry") }
                        }
                    }
                }
                state.leads.isEmpty() -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Icon(
                                Icons.Default.PersonSearch,
                                null,
                                modifier = Modifier.size(48.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                            Text(
                                "No leads found",
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
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
                            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
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
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
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
                val meta = statusMetaFor(lead.status)
                val statusBg = meta?.color ?: MaterialTheme.colorScheme.primary
                Surface(
                    shape = MaterialTheme.shapes.small,
                    color = statusBg,
                ) {
                    Text(
                        meta?.label ?: (lead.status ?: ""),
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                        style = MaterialTheme.typography.labelSmall,
                        color = contrastTextColor(statusBg),
                    )
                }
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
