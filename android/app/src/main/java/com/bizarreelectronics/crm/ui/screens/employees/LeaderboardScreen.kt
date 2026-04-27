package com.bizarreelectronics.crm.ui.screens.employees

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.EmployeeApi
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.theme.SuccessGreen
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

// ── Data / state ──────────────────────────────────────────────────────────────

data class LeaderboardEntry(
    val id: Long,
    val name: String,
    val role: String,
    val totalTickets: Int,
    val closedTickets: Int,
    val totalRevenueCents: Long,
    val avgTicketValueCents: Long,
)

enum class LeaderboardSort(val label: String) {
    Tickets("Tickets closed"),
    Revenue("Revenue"),
    AvgValue("Avg ticket"),
}

data class LeaderboardUiState(
    val entries: List<LeaderboardEntry> = emptyList(),
    val isLoading: Boolean = true,
    val error: String? = null,
    val sort: LeaderboardSort = LeaderboardSort.Tickets,
) {
    val sorted: List<LeaderboardEntry>
        get() = when (sort) {
            LeaderboardSort.Tickets -> entries.sortedByDescending { it.closedTickets }
            LeaderboardSort.Revenue -> entries.sortedByDescending { it.totalRevenueCents }
            LeaderboardSort.AvgValue -> entries.sortedByDescending { it.avgTicketValueCents }
        }
}

// ── ViewModel ─────────────────────────────────────────────────────────────────

/**
 * §14.7 — Employee leaderboard.
 * Uses GET /employees/performance/all (employees.routes.ts).
 * 404-tolerant: shows empty state if endpoint returns 404.
 */
@HiltViewModel
class LeaderboardViewModel @Inject constructor(
    private val employeeApi: EmployeeApi,
) : ViewModel() {

    private val _state = MutableStateFlow(LeaderboardUiState())
    val state = _state.asStateFlow()

    init { load() }

    fun load() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                // GET /employees/performance/all returns a List of performance rows.
                // The SettingsApi.getEmployees() endpoint is used as the base Retrofit
                // instance here; we call the path directly via a separate sub-path.
                // Because SettingsApi doesn't expose /employees/performance/all, we
                // parse the raw list from the employees endpoint and fall back gracefully.
                // The actual performance/all call is issued through EmployeeApi below.
                // (SettingsApi shares the same Retrofit instance.)
                // We resolve this by calling the API through retrofit directly:
                val rawResponse = retrofitCall()
                _state.value = _state.value.copy(
                    isLoading = false,
                    entries = rawResponse,
                )
            } catch (e: retrofit2.HttpException) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = if (e.code() == 404) "Leaderboard not available" else "Failed to load (${e.code()})",
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = e.message ?: "Failed to load leaderboard",
                )
            }
        }
    }

    /**
     * Calls GET /employees/performance/all via the employees endpoint.
     * Parses the generic Any response into typed LeaderboardEntry objects.
     */
    @Suppress("UNCHECKED_CAST")
    private suspend fun retrofitCall(): List<LeaderboardEntry> {
        val response = employeeApi.getPerformanceAll()
        val list = response.data as? List<*> ?: return emptyList()
        return list.mapNotNull { item ->
            val m = item as? Map<*, *> ?: return@mapNotNull null
            val id = (m["id"] as? Number)?.toLong() ?: return@mapNotNull null
            val firstName = m["first_name"] as? String ?: ""
            val lastName = m["last_name"] as? String ?: ""
            val name = "$firstName $lastName".trim().ifBlank { "Employee #$id" }
            LeaderboardEntry(
                id = id,
                name = name,
                role = m["role"] as? String ?: "",
                totalTickets = (m["total_tickets"] as? Number)?.toInt() ?: 0,
                closedTickets = (m["closed_tickets"] as? Number)?.toInt() ?: 0,
                totalRevenueCents = ((m["total_revenue"] as? Number)?.toDouble()?.times(100))?.toLong() ?: 0L,
                avgTicketValueCents = ((m["avg_ticket_value"] as? Number)?.toDouble()?.times(100))?.toLong() ?: 0L,
            )
        }
    }

    fun setSort(sort: LeaderboardSort) {
        _state.value = _state.value.copy(sort = sort)
    }
}

// ── Screen ────────────────────────────────────────────────────────────────────

@Composable
fun LeaderboardScreen(
    onBack: () -> Unit,
    viewModel: LeaderboardViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Leaderboard",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { viewModel.load() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            // Sort chips
            LazyRow(
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(LeaderboardSort.entries.size) { i ->
                    val sort = LeaderboardSort.entries[i]
                    FilterChip(
                        selected = state.sort == sort,
                        onClick = { viewModel.setSort(sort) },
                        label = { Text(sort.label) },
                    )
                }
            }
            HorizontalDivider()

            when {
                state.isLoading -> Box(
                    Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
                state.error != null -> Box(
                    Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center,
                ) {
                    ErrorState(message = state.error!!, onRetry = { viewModel.load() })
                }
                state.entries.isEmpty() -> Box(
                    Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center,
                ) {
                    EmptyState(
                        icon = Icons.Default.EmojiEvents,
                        title = "No data yet",
                        subtitle = "Complete some tickets to see the leaderboard.",
                        includeWave = true,
                    )
                }
                else -> {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(bottom = 80.dp),
                    ) {
                        itemsIndexed(state.sorted, key = { _, entry -> entry.id }) { index, entry ->
                            LeaderboardRow(rank = index + 1, entry = entry, sort = state.sort)
                            HorizontalDivider()
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun LeaderboardRow(rank: Int, entry: LeaderboardEntry, sort: LeaderboardSort) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Rank badge
        Box(
            modifier = Modifier
                .size(36.dp)
                .background(
                    color = when (rank) {
                        1 -> Color(0xFFFFD700)   // gold
                        2 -> Color(0xFFC0C0C0)   // silver
                        3 -> Color(0xFFCD7F32)   // bronze
                        else -> MaterialTheme.colorScheme.surfaceVariant
                    },
                    shape = MaterialTheme.shapes.small,
                ),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = when (rank) {
                    1 -> "🥇"  // gold medal emoji
                    2 -> "🥈"  // silver medal emoji
                    3 -> "🥉"  // bronze medal emoji
                    else -> "#$rank"
                },
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Bold,
                color = if (rank <= 3) Color.Black else MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        Column(modifier = Modifier.weight(1f)) {
            Text(
                entry.name,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
            )
            if (entry.role.isNotBlank()) {
                Text(
                    entry.role.replaceFirstChar { it.uppercase() },
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        Column(horizontalAlignment = Alignment.End) {
            val primaryValue = when (sort) {
                LeaderboardSort.Tickets -> "${entry.closedTickets} closed"
                LeaderboardSort.Revenue -> "$%.2f".format(entry.totalRevenueCents / 100.0)
                LeaderboardSort.AvgValue -> "$%.2f".format(entry.avgTicketValueCents / 100.0)
            }
            Text(
                primaryValue,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = if (rank == 1) SuccessGreen else MaterialTheme.colorScheme.onSurface,
            )
            Text(
                "${entry.totalTickets} total tickets",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
