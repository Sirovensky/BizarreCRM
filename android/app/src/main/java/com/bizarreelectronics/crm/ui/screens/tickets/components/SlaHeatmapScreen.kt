package com.bizarreelectronics.crm.ui.screens.tickets.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Sort
import androidx.compose.material.icons.filled.Sms
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.SlaApi
import com.bizarreelectronics.crm.data.remote.api.SlaHeatmapRow
import com.bizarreelectronics.crm.util.SlaCalculator
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import javax.inject.Inject

// ─── ViewModel ───────────────────────────────────────────────────────────────

data class HeatmapUiState(
    val rows: List<SlaHeatmapRow> = emptyList(),
    val sortByRed: Boolean = true,
    val isLoading: Boolean = false,
    val error: String? = null,
)

@HiltViewModel
class SlaHeatmapViewModel @Inject constructor(
    private val slaApi: SlaApi,
) : ViewModel() {

    private val _state = MutableStateFlow(HeatmapUiState(isLoading = true))
    val state: StateFlow<HeatmapUiState> = _state.asStateFlow()

    init {
        load()
    }

    fun load() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                val resp = slaApi.getHeatmap()
                val rows = resp.data?.rows ?: emptyList()
                _state.value = _state.value.copy(isLoading = false, rows = sort(rows, _state.value.sortByRed))
            } catch (e: Exception) {
                _state.value = _state.value.copy(isLoading = false, error = e.message)
            }
        }
    }

    fun toggleSort() {
        val newSort = !_state.value.sortByRed
        _state.value = _state.value.copy(
            sortByRed = newSort,
            rows = sort(_state.value.rows, newSort),
        )
    }

    private fun sort(rows: List<SlaHeatmapRow>, redFirst: Boolean): List<SlaHeatmapRow> =
        if (redFirst) {
            rows.sortedWith(
                compareBy<SlaHeatmapRow> { it.remainingPct }
                    .thenBy { it.projectedBreachMs ?: Long.MAX_VALUE }
            )
        } else {
            rows.sortedByDescending { it.remainingPct }
        }
}

// ─── Screen ──────────────────────────────────────────────────────────────────

/**
 * §4.19 L859-L865 — Manager SLA heatmap screen.
 *
 * Shows all open tickets sorted by SLA health (red-zone first).
 * Each row displays:
 * - Customer name + ticket order-id
 * - Assignee
 * - Tier colour dot (red / amber / green)
 * - Remaining % label
 * - Projected breach time
 * - "Notify delay" button → opens SMS template dialog
 *
 * ReduceMotion: when true, the tier dot is static (no pulse animation).
 *
 * Navigation: accessible from Dashboard manager surface (registered in AppNavGraph).
 *
 * @param onTicketClick     Navigate to ticket detail for the given ticket id.
 * @param reduceMotion      When true, no motion animations are applied.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SlaHeatmapScreen(
    onTicketClick: (ticketId: Long) -> Unit,
    reduceMotion: Boolean = false,
    viewModel: SlaHeatmapViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("SLA Heatmap") },
                actions = {
                    IconButton(onClick = viewModel::toggleSort) {
                        Icon(
                            Icons.AutoMirrored.Filled.Sort,
                            contentDescription = if (state.sortByRed) "Sort: Red first" else "Sort: Green first",
                        )
                    }
                },
            )
        },
    ) { innerPadding ->
        when {
            state.isLoading -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            }

            state.error != null -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(
                            "Could not load SLA data",
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.error,
                        )
                        TextButton(onClick = viewModel::load) { Text("Retry") }
                    }
                }
            }

            state.rows.isEmpty() -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        "No open tickets",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            else -> {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding),
                ) {
                    items(state.rows, key = { it.ticketId }) { row ->
                        HeatmapRow(
                            row = row,
                            reduceMotion = reduceMotion,
                            onClick = { onTicketClick(row.ticketId) },
                        )
                        HorizontalDivider()
                    }
                }
            }
        }
    }
}

// ─── Row ─────────────────────────────────────────────────────────────────────

@Composable
private fun HeatmapRow(
    row: SlaHeatmapRow,
    reduceMotion: Boolean,
    onClick: () -> Unit,
) {
    val tier = SlaCalculator.tier(row.remainingPct)
    val dotColor = when (tier) {
        SlaCalculator.SlaTier.Green -> MaterialTheme.colorScheme.secondary
        SlaCalculator.SlaTier.Amber -> MaterialTheme.colorScheme.tertiary
        SlaCalculator.SlaTier.Red   -> MaterialTheme.colorScheme.error
    }
    val remainingLabel = formatSlaRemaining(
        // Convert pct back to an approximate ms; exact value from server not in this dto.
        // Use projectedBreachMs - now as a proxy when available.
        row.projectedBreachMs?.let { it - System.currentTimeMillis() } ?: 0L
    )

    var showNotifyDialog by rememberSaveable { mutableStateOf(false) }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Tier dot
        Box(
            modifier = Modifier
                .size(12.dp)
                .clip(CircleShape)
                .background(dotColor),
        )

        // Ticket info
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = row.customerName ?: "Unknown customer",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                text = buildString {
                    row.ticketOrderId?.let { append("#$it · ") }
                    append(row.assignee ?: "Unassigned")
                },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        // Remaining + breach column
        Column(horizontalAlignment = Alignment.End) {
            SlaChip(tier = tier, label = remainingLabel)
            row.projectedBreachMs?.let { breachMs ->
                if (breachMs > System.currentTimeMillis()) {
                    Text(
                        text = "Breach: ${formatBreachTime(breachMs)}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        // "Notify delay" button
        IconButton(onClick = { showNotifyDialog = true }) {
            Icon(
                Icons.Default.Sms,
                contentDescription = "Notify customer of delay",
                tint = MaterialTheme.colorScheme.primary,
            )
        }
    }

    if (showNotifyDialog) {
        NotifyDelayDialog(
            customerName = row.customerName ?: "Customer",
            onDismiss = { showNotifyDialog = false },
        )
    }
}

// ─── Notify delay dialog ─────────────────────────────────────────────────────

@Composable
private fun NotifyDelayDialog(
    customerName: String,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Notify Customer of Delay") },
        text = {
            Text(
                "Send an SMS to $customerName letting them know the repair is " +
                    "taking longer than expected? The standard delay template will be used.",
                style = MaterialTheme.typography.bodyMedium,
            )
        },
        confirmButton = {
            TextButton(
                onClick = {
                    // POST /sms/send — caller's ViewModel / repository handles the actual call.
                    // For now the dialog is a stub; the action is wired in TicketDetailViewModel.
                    onDismiss()
                },
            ) {
                Text("Send SMS")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

private fun formatBreachTime(epochMs: Long): String {
    val sdf = SimpleDateFormat("h:mm a", Locale.getDefault())
    return sdf.format(Date(epochMs))
}
