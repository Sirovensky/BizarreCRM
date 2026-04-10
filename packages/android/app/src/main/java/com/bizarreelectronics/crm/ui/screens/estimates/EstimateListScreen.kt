package com.bizarreelectronics.crm.ui.screens.estimates

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.entities.EstimateEntity
import com.bizarreelectronics.crm.data.repository.EstimateRepository
import com.bizarreelectronics.crm.ui.theme.*
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
            TopAppBar(
                title = { Text("Estimates") },
                actions = {
                    IconButton(onClick = { viewModel.loadEstimates() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .imePadding(),
        ) {
            OutlinedTextField(
                value = state.searchQuery,
                onValueChange = { viewModel.onSearchChanged(it) },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                placeholder = { Text("Search estimates...") },
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

            LazyRow(
                modifier = Modifier.padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(statuses) { status ->
                    FilterChip(
                        selected = state.selectedStatus == status,
                        onClick = { viewModel.onStatusChanged(status) },
                        label = { Text(status) },
                    )
                }
            }

            if (!state.isLoading && state.estimates.isNotEmpty()) {
                Text(
                    "${state.estimates.size} estimates",
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
                            TextButton(onClick = { viewModel.loadEstimates() }) { Text("Retry") }
                        }
                    }
                }
                state.estimates.isEmpty() -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Icon(
                                Icons.Default.Description,
                                contentDescription = null,
                                modifier = Modifier.size(48.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                            Text(
                                "No estimates found",
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
                else -> {
                    PullToRefreshBox(
                        isRefreshing = state.isRefreshing,
                        onRefresh = { viewModel.refresh() },
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        LazyColumn(
                            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            items(state.estimates, key = { it.id }) { estimate ->
                                EstimateCard(estimate = estimate, onClick = { onEstimateClick(estimate.id) })
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
    val statusColor = estimateStatusColor(estimate.status)

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
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    estimate.orderId.ifBlank { "EST-${estimate.id}" },
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    estimate.customerName ?: "Unknown",
                    style = MaterialTheme.typography.bodyMedium,
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
                Surface(shape = MaterialTheme.shapes.small, color = statusColor) {
                    Text(
                        estimate.status.replaceFirstChar { it.uppercase() },
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                        style = MaterialTheme.typography.labelSmall,
                        color = contrastTextColor(statusColor),
                    )
                }
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    String.format("$%.2f", estimate.total),
                    style = MaterialTheme.typography.bodySmall,
                    fontWeight = FontWeight.Medium,
                )
            }
        }
    }
}

internal fun estimateStatusColor(status: String): Color = when (status.lowercase()) {
    "approved" -> SuccessGreen
    "sent" -> InfoBlue
    "rejected" -> ErrorRed
    "converted" -> RefundedPurple
    "draft" -> Color.Gray
    else -> Color.Gray
}
