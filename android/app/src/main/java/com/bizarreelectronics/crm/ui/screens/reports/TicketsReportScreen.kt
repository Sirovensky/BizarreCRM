package com.bizarreelectronics.crm.ui.screens.reports

import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.screens.reports.components.ReportsExportActions

/**
 * Tickets report screen (ActionPlan §15 L1735-L1738).
 *
 * Shows:
 *   - Average time to close (stub until /reports/tickets endpoint ships)
 *   - Top technicians table
 *   - Status breakdown donut chart (reuses CategoryBreakdownPieChart)
 *
 * Data is sourced from ReportsUiState; the /reports/tickets endpoint is not
 * yet implemented server-side — 404 is tolerated, stubs are shown.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TicketsReportScreen(
    viewModel: ReportsViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Tickets Report",
                actions = {
                    ReportsExportActions(
                        reportTitle = "Tickets_Report",
                        csvContent = { buildTicketsCsv() },
                    )
                },
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // Avg time to close
            item {
                Text(
                    "Avg Time to Close",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.semantics { heading() },
                )
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.surface,
                    ),
                    elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
                ) {
                    Text(
                        "—",
                        style = MaterialTheme.typography.headlineMedium,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.padding(16.dp),
                    )
                    Text(
                        "Available once /reports/tickets endpoint ships.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 16.dp),
                    )
                }
            }

            // Top technicians stub
            item {
                Text(
                    "Top Technicians",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier
                        .padding(top = 4.dp)
                        .semantics { heading() },
                )
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.surfaceVariant,
                    ),
                ) {
                    Text(
                        "Technician breakdown will appear here once the tickets report endpoint is live.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(12.dp),
                    )
                }
            }

            // Status breakdown pie
            item {
                Text(
                    "Status Breakdown",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier
                        .padding(top = 4.dp)
                        .semantics { heading() },
                )
                // Build slices from open/stale counts for now
                val primary = MaterialTheme.colorScheme.primary
                val secondary = MaterialTheme.colorScheme.secondary
                val error = MaterialTheme.colorScheme.error
                val openCount = state.openTickets.toDouble()
                val staleCount = state.staleTickets.toDouble()
                val closedProxy = (openCount * 0.3).coerceAtLeast(0.0) // placeholder
                val slices = listOf(
                    CategoryBreakdownSlice("Open", openCount, primary),
                    CategoryBreakdownSlice("Stale", staleCount, error),
                    CategoryBreakdownSlice("Closed (est.)", closedProxy, secondary),
                ).filter { it.value > 0 }
                if (slices.isEmpty()) {
                    Text(
                        "No ticket data for current period.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                } else {
                    CategoryBreakdownPieChart(slices = slices)
                }
            }
        }
    }
}

private fun buildTicketsCsv(): String = buildString {
    appendLine("Metric,Value")
    appendLine("Avg Time to Close,—")
    appendLine("Note,Full data pending /reports/tickets endpoint")
}
