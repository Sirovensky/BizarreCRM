package com.bizarreelectronics.crm.ui.screens.estimates

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.entities.EstimateEntity
import com.bizarreelectronics.crm.data.repository.EstimateRepository
import com.bizarreelectronics.crm.ui.components.WaveDivider
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandStatusBadge
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.components.shared.SearchBar
import com.bizarreelectronics.crm.util.formatAsMoney
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import javax.inject.Inject

data class EstimateListUiState(
    val estimates: List<EstimateEntity> = emptyList(),
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val searchQuery: String = "",
    val selectedStatus: String = "All",
)

@HiltViewModel
class EstimateListViewModel @Inject constructor(
    private val estimateRepository: EstimateRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(EstimateListUiState())
    val state = _state.asStateFlow()

    private var searchJob: Job? = null
    private var collectJob: Job? = null

    init {
        loadEstimates()
    }

    fun loadEstimates() {
        collectJob?.cancel()
        collectJob = viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = _state.value.estimates.isEmpty(), error = null)
            val query = _state.value.searchQuery.trim()
            val statusFilter = _state.value.selectedStatus

            val flow = if (query.isNotEmpty()) {
                estimateRepository.searchEstimates(query)
            } else {
                estimateRepository.getEstimates()
            }

            flow
                .map { estimates ->
                    if (statusFilter == "All") {
                        estimates
                    } else {
                        estimates.filter { it.status.equals(statusFilter, ignoreCase = true) }
                    }
                }
                .catch { e ->
                    _state.value = _state.value.copy(
                        isLoading = false,
                        isRefreshing = false,
                        error = "Failed to load estimates. Check your connection and try again.",
                    )
                }
                .collectLatest { estimates ->
                    _state.value = _state.value.copy(
                        estimates = estimates,
                        isLoading = false,
                        isRefreshing = false,
                    )
                }
        }
    }

    fun refresh() {
        _state.value = _state.value.copy(isRefreshing = true)
        loadEstimates()
    }

    fun onSearchChanged(query: String) {
        _state.value = _state.value.copy(searchQuery = query)
        searchJob?.cancel()
        searchJob = viewModelScope.launch {
            delay(300)
            loadEstimates()
        }
    }

    fun onStatusChanged(status: String) {
        _state.value = _state.value.copy(selectedStatus = status)
        loadEstimates()
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EstimateListScreen(
    onEstimateClick: (Long) -> Unit,
    viewModel: EstimateListViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val statuses = listOf("All", "Draft", "Sent", "Approved", "Rejected", "Converted")

    Scaffold(
        topBar = {
            // CROSS45: WaveDivider docked directly below the TopAppBar — canonical
            // placement for every list screen.
            Column {
                BrandTopAppBar(
                    title = "Estimates",
                    actions = {
                        IconButton(onClick = { viewModel.loadEstimates() }) {
                            // a11y: "Refresh estimates" is more specific than generic "Refresh"
                            Icon(
                                Icons.Default.Refresh,
                                contentDescription = "Refresh estimates",
                            )
                        }
                    },
                )
                WaveDivider()
            }
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .imePadding(),
        ) {
            SearchBar(
                query = state.searchQuery,
                onQueryChange = { viewModel.onSearchChanged(it) },
                placeholder = "Search estimates...",
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
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

            LazyRow(
                modifier = Modifier.padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(statuses, key = { it }) { status ->
                    val isSelected = state.selectedStatus == status
                    FilterChip(
                        selected = isSelected,
                        onClick = { viewModel.onStatusChanged(status) },
                        label = { Text(status) },
                        // a11y: Role.Tab + selection state announcement; the chip's
                        // selected param already flips the chip visually; the
                        // semantics here make TalkBack say "<status> filter, selected/not selected"
                        modifier = Modifier.semantics {
                            role = Role.Tab
                            contentDescription = if (isSelected) {
                                "$status filter, selected"
                            } else {
                                "$status filter, not selected"
                            }
                        },
                    )
                }
            }

            if (!state.isLoading && state.estimates.isNotEmpty()) {
                val estimateCount = state.estimates.size
                val countLabel = "$estimateCount ${if (estimateCount == 1) "estimate" else "estimates"}"
                // a11y: liveRegion=Polite so TalkBack announces when the count changes
                // after a filter switch, without interrupting the user mid-sentence.
                Text(
                    countLabel,
                    modifier = Modifier
                        .padding(horizontal = 16.dp, vertical = 4.dp)
                        .semantics {
                            liveRegion = LiveRegionMode.Polite
                            contentDescription = countLabel
                        },
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            Spacer(modifier = Modifier.height(4.dp))

            when {
                state.isLoading -> {
                    // a11y: mergeDescendants + contentDescription so TalkBack announces
                    // "Loading estimates" on a single focus stop rather than reading
                    // each shimmer box individually.
                    Box(
                        modifier = Modifier.semantics(mergeDescendants = true) {
                            contentDescription = "Loading estimates"
                        },
                    ) {
                        BrandSkeleton(
                            rows = 6,
                            modifier = Modifier.fillMaxSize(),
                        )
                    }
                }
                state.error != null -> {
                    // a11y: liveRegion=Assertive interrupts TalkBack immediately so the
                    // user is not left wondering why the list is empty after a network failure.
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .semantics {
                                liveRegion = LiveRegionMode.Assertive
                            },
                        contentAlignment = Alignment.Center,
                    ) {
                        ErrorState(
                            message = state.error ?: "Error",
                            onRetry = { viewModel.loadEstimates() },
                        )
                    }
                }
                state.estimates.isEmpty() -> {
                    // a11y: mergeDescendants collapses the decorative icon + title + subtitle
                    // into one TalkBack node so the empty state reads as a single announcement.
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .semantics(mergeDescendants = true) {},
                        contentAlignment = Alignment.Center,
                    ) {
                        EmptyState(
                            icon = Icons.Default.Description,
                            title = "No estimates found",
                            // CROSS43: give users context on where estimates come from.
                            // Android doesn't have a standalone create-estimate flow yet
                            // (web only) — estimates appear here after a tech converts a
                            // ticket via the web ticket detail page.
                            subtitle = if (state.searchQuery.isNotEmpty()) {
                                "Try a different search term"
                            } else {
                                "Estimates appear here when created from a ticket."
                            },
                        )
                    }
                }
                else -> {
                    PullToRefreshBox(
                        isRefreshing = state.isRefreshing,
                        onRefresh = { viewModel.refresh() },
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        LazyColumn(
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
                            items(state.estimates, key = { it.id }) { estimate ->
                                EstimateCard(
                                    estimate = estimate,
                                    onClick = { onEstimateClick(estimate.id) },
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun EstimateCard(estimate: EstimateEntity, onClick: () -> Unit) {
    // a11y: build the full announcement string once so it can be used in semantics.
    // BrandCard(onClick) carries Material 3 Card Role.Button; we add contentDescription
    // on the BrandCard modifier so TalkBack announces a single coherent sentence
    // instead of reading each child Text node individually.
    val estimateNumber = estimate.orderId.ifBlank { "EST-${estimate.id}" }
    val a11yDesc = buildString {
        append("Estimate #$estimateNumber")
        estimate.customerName?.takeIf { it.isNotBlank() }?.let { append(" for $it") }
        append(", ${estimate.total.formatAsMoney()}")
        val statusLabel = estimate.status.replaceFirstChar { it.uppercase() }
        append(", $statusLabel")
        val dateStr = estimate.validUntil?.take(10)?.takeIf { it.isNotBlank() }
        if (dateStr != null) {
            append(", dated $dateStr")
        }
        append(". Tap to open.")
    }

    BrandCard(
        // a11y: contentDescription overrides merged child-text reading; 48dp floor
        // ensures the row meets the Material 3 minimum touch target.
        modifier = Modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 48.dp)
            .semantics { contentDescription = a11yDesc },
        onClick = onClick,
    ) {
        Row(
            modifier = Modifier
                .padding(16.dp)
                .fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    estimate.orderId.ifBlank { "EST-${estimate.id}" },
                    style = MaterialTheme.typography.labelLarge.copy(
                        fontFamily = MaterialTheme.typography.labelLarge.fontFamily,
                    ),
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Text(
                    estimate.customerName ?: "Unknown",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                if (!estimate.validUntil.isNullOrBlank()) {
                    Text(
                        "Valid until: ${estimate.validUntil.take(10)}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Column(horizontalAlignment = Alignment.End) {
                BrandStatusBadge(
                    label = estimate.status.replaceFirstChar { it.uppercase() },
                    status = estimate.status,
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    estimate.total.formatAsMoney(),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
        }
    }
}
