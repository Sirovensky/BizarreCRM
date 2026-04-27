package com.bizarreelectronics.crm.ui.screens.reports

import androidx.compose.material3.ExperimentalMaterial3Api
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.screens.reports.components.ReportsExportActions
import com.bizarreelectronics.crm.util.CurrencyFormatter
import java.util.Locale

/**
 * Tickets report screen (ActionPlan §15.3).
 *
 * Wired to GET /reports/tickets.  Renders:
 *   - Summary tiles: created vs closed + avg turnaround
 *   - Throughput bar chart (created-per-day via SalesByDayBarChart, reusing the ticket-count
 *     as the Y axis — the chart renders "count" not "cents" but the shape is identical)
 *   - Top technicians table
 *   - Status breakdown donut chart (derived from open/stale counts in state)
 *
 * NOTE §15.3 Label breakdowns: the server /reports/tickets endpoint does not yet return
 * a ticket-label breakdown (byLabel).  The ticket_labels table exists and labels can be
 * attached to tickets, but the aggregate query is missing from reports.routes.ts.
 * Left [ ] until server endpoint ships.
 *
 * NOTE §15.3 SLA compliance %: no per-tech SLA threshold config exists yet.
 * Left [~] — stub column shown in top-tech table.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TicketsReportScreen(
    viewModel: ReportsViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    LaunchedEffect(Unit) {
        if (state.ticketsReport.totalCreated == 0 && !state.isTicketsLoading) {
            viewModel.loadTicketsReport()
        }
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Tickets Report",
                actions = {
                    ReportsExportActions(
                        reportTitle = "Tickets_Report",
                        csvContent = { buildTicketsCsv(state.ticketsReport) },
                    )
                },
            )
        },
    ) { padding ->
        when {
            state.isTicketsLoading -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            }
            state.ticketsError != null -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    ErrorState(
                        message = state.ticketsError!!,
                        onRetry = { viewModel.loadTicketsReport() },
                    )
                }
            }
            else -> {
                val report = state.ticketsReport
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    // Summary stat tiles
                    item {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            TicketStatTile(
                                label = "Created",
                                value = "${report.totalCreated}",
                                modifier = Modifier.weight(1f),
                            )
                            TicketStatTile(
                                label = "Closed",
                                value = "${report.totalClosed}",
                                modifier = Modifier.weight(1f),
                            )
                            val turnaround = report.avgTurnaroundHours
                            TicketStatTile(
                                label = "Avg Close",
                                value = if (turnaround != null)
                                    "${String.format(Locale.US, "%.1f", turnaround)} h"
                                else "—",
                                modifier = Modifier.weight(1f),
                            )
                        }
                    }

                    // Throughput chart (created per day)
                    item {
                        Text(
                            "Throughput (Tickets Created per Day)",
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier.semantics { heading() },
                        )
                    }
                    item {
                        if (report.byDay.isEmpty()) {
                            Card(
                                modifier = Modifier.fillMaxWidth(),
                                colors = CardDefaults.cardColors(
                                    containerColor = MaterialTheme.colorScheme.surfaceVariant,
                                ),
                            ) {
                                Text(
                                    "No daily data for this period.",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.padding(12.dp),
                                )
                            }
                        } else {
                            SalesByDayBarChart(
                                points = report.byDay,
                                appPreferences = viewModel.appPreferences,
                            )
                        }
                    }

                    // Avg time-in-status (server returns a single avg_turnaround; per-status
                    // funnel not yet in endpoint — shown as informational card)
                    item {
                        Text(
                            "Avg Time to Close",
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier
                                .padding(top = 4.dp)
                                .semantics { heading() },
                        )
                        Card(
                            modifier = Modifier.fillMaxWidth(),
                            colors = CardDefaults.cardColors(
                                containerColor = MaterialTheme.colorScheme.surface,
                            ),
                            elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
                        ) {
                            val turnaround = report.avgTurnaroundHours
                            Column(modifier = Modifier.padding(16.dp)) {
                                Text(
                                    if (turnaround != null)
                                        "${String.format(Locale.US, "%.1f", turnaround)} hours"
                                    else "—",
                                    style = MaterialTheme.typography.headlineSmall,
                                    color = MaterialTheme.colorScheme.primary,
                                )
                                Text(
                                    "Active repair time only (hold/waiting time excluded).",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                Text(
                                    "NOTE: per-status funnel deferred — endpoint returns single avg.",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }

                    // Top technicians table
                    if (report.byTech.isNotEmpty()) {
                        item {
                            Text(
                                "Top Technicians",
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.SemiBold,
                                modifier = Modifier
                                    .padding(top = 4.dp)
                                    .semantics { heading() },
                            )
                        }
                        items(report.byTech.take(10), key = { it.name }) { row ->
                            TechTicketCard(row = row)
                        }
                    } else {
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
                                    "No technician data for this period.",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.padding(12.dp),
                                )
                            }
                        }
                    }

                    // Status breakdown donut from open/stale state
                    item {
                        Text(
                            "Status Breakdown",
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier
                                .padding(top = 4.dp)
                                .semantics { heading() },
                        )
                        val primary = MaterialTheme.colorScheme.primary
                        val secondary = MaterialTheme.colorScheme.secondary
                        val error = MaterialTheme.colorScheme.error
                        val openCount = state.openTickets.toDouble()
                        val staleCount = state.staleTickets.toDouble()
                        val closedEstimate = report.totalClosed.toDouble()
                        val slices = listOf(
                            CategoryBreakdownSlice("Open", openCount, primary),
                            CategoryBreakdownSlice("Stale", staleCount, error),
                            CategoryBreakdownSlice("Closed", closedEstimate, secondary),
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

                    // Label breakdowns placeholder
                    item {
                        Spacer(Modifier.height(4.dp))
                        Text(
                            "Label Breakdowns",
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier.semantics { heading() },
                        )
                        Card(
                            modifier = Modifier.fillMaxWidth(),
                            colors = CardDefaults.cardColors(
                                containerColor = MaterialTheme.colorScheme.surfaceVariant,
                            ),
                        ) {
                            Text(
                                "NOTE: label-breakdown aggregate not yet in /reports/tickets server endpoint. Left deferred.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.padding(12.dp),
                            )
                        }
                    }
                }
            }
        }
    }
}

// ─── Sub-composables ─────────────────────────────────────────────────────────

@Composable
private fun TicketStatTile(label: String, value: String, modifier: Modifier = Modifier) {
    Card(
        modifier = modifier,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
    ) {
        Column(
            modifier = Modifier.padding(10.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                value,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.primary,
            )
            Text(
                label,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun TechTicketCard(row: TechTicketRow) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {
                contentDescription = "${row.name}: ${row.closedCount} closed of ${row.ticketCount} assigned; revenue ${CurrencyFormatter.format(row.totalRevenue)}"
            },
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(row.name, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                Text(
                    "${row.closedCount}/${row.ticketCount} closed",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    CurrencyFormatter.format(row.totalRevenue),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.primary,
                )
                Text(
                    "SLA —",  // stub: no SLA threshold config yet
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

// ─── CSV builder ─────────────────────────────────────────────────────────────

private fun buildTicketsCsv(report: TicketsReport): String = buildString {
    appendLine("Metric,Value")
    appendLine("Total Created,${report.totalCreated}")
    appendLine("Total Closed,${report.totalClosed}")
    val turnaround = report.avgTurnaroundHours
    appendLine("Avg Turnaround (hrs),${if (turnaround != null) String.format(Locale.US, "%.1f", turnaround) else "n/a"}")
    appendLine()
    if (report.byTech.isNotEmpty()) {
        appendLine("Technician,Tickets Assigned,Tickets Closed,Revenue")
        report.byTech.forEach { r ->
            appendLine("${r.name},${r.ticketCount},${r.closedCount},${"%.2f".format(r.totalRevenue)}")
        }
    }
    if (report.byDay.isNotEmpty()) {
        appendLine()
        appendLine("Date,Tickets Created")
        report.byDay.forEach { p ->
            appendLine("${p.isoDate},${p.totalCents}")
        }
    }
}
