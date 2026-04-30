package com.bizarreelectronics.crm.ui.screens.employees

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.ReportApi
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

// ─── Data model ──────────────────────────────────────────────────────────────

data class LeaderboardEntry(
    val rank: Int,
    val employeeId: Long,
    val name: String,
    val ticketsClosed: Int,
    val revenueCents: Long,
    val commissionCents: Long,
)

data class LeaderboardUiState(
    val entries: List<LeaderboardEntry> = emptyList(),
    val period: String = "month",
    val isLoading: Boolean = true,
    val error: String? = null,
    val serverUnsupported: Boolean = false,
)

private val PERIOD_OPTIONS = listOf(
    "week" to "This Week",
    "month" to "This Month",
    "ytd" to "Year to Date",
)

// ─── ViewModel ───────────────────────────────────────────────────────────────

@HiltViewModel
class LeaderboardViewModel @Inject constructor(
    private val reportApi: ReportApi,
) : ViewModel() {

    private val _state = MutableStateFlow(LeaderboardUiState())
    val state = _state.asStateFlow()

    init { load() }

    fun setPeriod(period: String) {
        _state.value = _state.value.copy(period = period)
        load()
    }

    fun load() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = _state.value.entries.isEmpty(), error = null)
            runCatching { reportApi.getTechLeaderboard(period = _state.value.period) }
                .onSuccess { resp ->
                    val entries = parseEntries(resp.data)
                    _state.value = _state.value.copy(
                        isLoading = false,
                        entries = entries,
                        serverUnsupported = false,
                        error = null,
                    )
                }
                .onFailure { t ->
                    val is404 = t is retrofit2.HttpException && t.code() == 404
                    _state.value = _state.value.copy(
                        isLoading = false,
                        serverUnsupported = is404,
                        error = if (is404) null else (t.message ?: "Failed to load leaderboard"),
                    )
                }
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun parseEntries(data: Any?): List<LeaderboardEntry> {
        val map = data as? Map<*, *> ?: return emptyList()
        val list = map["leaderboard"] as? List<*> ?: return emptyList()
        return list.mapNotNull { raw ->
            val m = raw as? Map<*, *> ?: return@mapNotNull null
            LeaderboardEntry(
                rank = (m["rank"] as? Number)?.toInt() ?: 0,
                employeeId = (m["employee_id"] as? Number)?.toLong() ?: 0L,
                name = m["name"] as? String ?: "Unknown",
                ticketsClosed = (m["tickets_closed"] as? Number)?.toInt() ?: 0,
                revenueCents = (m["revenue_cents"] as? Number)?.toLong() ?: 0L,
                commissionCents = (m["commission_cents"] as? Number)?.toLong() ?: 0L,
            )
        }
    }
}

// ─── Screen ──────────────────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
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
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            // ── Period filter ─────────────────────────────────────────────────
            LazyRow(
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(PERIOD_OPTIONS) { (value, label) ->
                    FilterChip(
                        selected = state.period == value,
                        onClick = { viewModel.setPeriod(value) },
                        label = { Text(label) },
                    )
                }
            }

            when {
                state.isLoading -> Box(
                    Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center,
                ) { CircularProgressIndicator() }

                state.serverUnsupported -> EmptyState(
                    icon = Icons.Default.EmojiEvents,
                    title = "Leaderboard not available",
                    subtitle = "The leaderboard report is not configured on this server.",
                )

                state.error != null -> ErrorState(
                    message = state.error!!,
                    onRetry = { viewModel.load() },
                )

                state.entries.isEmpty() -> EmptyState(
                    icon = Icons.Default.EmojiEvents,
                    title = "No data yet",
                    subtitle = "No activity recorded for this period.",
                )

                else -> LazyColumn(
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    itemsIndexed(state.entries) { _, entry ->
                        LeaderboardRow(entry = entry)
                    }
                }
            }
        }
    }
}

// ─── Sub-components ──────────────────────────────────────────────────────────

/** Medal emoji for top 3 ranks, number string for rest. */
private fun rankLabel(rank: Int): String = when (rank) {
    1 -> "🥇"   // 🥇
    2 -> "🥈"   // 🥈
    3 -> "🥉"   // 🥉
    else -> "#$rank"
}

@Composable
private fun LeaderboardRow(entry: LeaderboardEntry) {
    OutlinedCard(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // Rank badge
            Surface(
                color = MaterialTheme.colorScheme.primaryContainer,
                shape = MaterialTheme.shapes.small,
                modifier = Modifier.size(40.dp),
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Text(
                        text = rankLabel(entry.rank),
                        style = MaterialTheme.typography.titleMedium,
                    )
                }
            }

            // Name + stats
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = entry.name,
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    text = "${entry.ticketsClosed} tickets  •  ${"$%.0f".format(entry.revenueCents / 100.0)} revenue",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            // Commission
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    text = "${"$%.2f".format(entry.commissionCents / 100.0)}",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.primary,
                )
                Text(
                    text = "commission",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}
