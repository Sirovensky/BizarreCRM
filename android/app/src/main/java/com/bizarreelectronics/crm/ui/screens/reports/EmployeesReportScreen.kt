package com.bizarreelectronics.crm.ui.screens.reports

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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.TrendingUp
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SuggestionChip
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
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.screens.reports.components.ReportsExportActions
import java.text.NumberFormat
import java.util.Locale

/**
 * Employee performance report screen (ActionPlan §15.4).
 *
 * Displays a leaderboard ordered by revenue generated with per-tech chips for:
 *   - Tickets assigned / closed
 *   - Hours worked
 *   - Revenue generated
 *   - Commission earned
 *
 * Data is loaded via [ReportsViewModel.loadEmployeesReport] which calls
 * `GET /reports/employees`. 404 is tolerated and shows empty state.
 *
 * Shares [ReportsViewModel] with [ReportsScreen] so the date range chosen
 * in the parent is applied here automatically.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EmployeesReportScreen(
    viewModel: ReportsViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    LaunchedEffect(Unit) {
        if (state.employeePerformanceItems.isEmpty() && !state.isEmployeesReportLoading) {
            viewModel.loadEmployeesReport()
        }
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Employee Performance",
                actions = {
                    ReportsExportActions(
                        reportTitle = "Employee_Performance_Report",
                        csvContent = { buildEmployeesCsv(state.employeePerformanceItems) },
                    )
                },
            )
        },
    ) { padding ->
        when {
            state.isEmployeesReportLoading -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator(
                        modifier = Modifier.semantics {
                            contentDescription = "Loading employee performance report"
                        },
                    )
                }
            }
            state.employeesReportError != null -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    ErrorState(
                        message = state.employeesReportError ?: "Failed to load employee performance.",
                        onRetry = { viewModel.loadEmployeesReport() },
                    )
                }
            }
            state.employeePerformanceItems.isEmpty() -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(
                            Icons.AutoMirrored.Filled.TrendingUp,
                            contentDescription = "No employee data",
                            modifier = Modifier.size(48.dp),
                            tint = MaterialTheme.colorScheme.primary,
                        )
                        Text(
                            "No employee performance data",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Text(
                            "Data will appear once /reports/employees returns results for the selected period.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
            else -> {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    item {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            modifier = Modifier.semantics { heading() },
                        ) {
                            Icon(
                                Icons.AutoMirrored.Filled.TrendingUp,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.size(20.dp),
                            )
                            Text(
                                "Leaderboard — ${state.employeePerformanceItems.size} technicians",
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.SemiBold,
                            )
                        }
                    }
                    itemsIndexed(
                        items = state.employeePerformanceItems,
                        key = { _, item -> item.id },
                    ) { index, item ->
                        EmployeePerformanceCard(rank = index + 1, item = item)
                    }
                }
            }
        }
    }
}

@Composable
internal fun EmployeePerformanceCard(
    rank: Int,
    item: EmployeePerformanceItem,
) {
    val currencyFmt = NumberFormat.getCurrencyInstance(Locale.US)

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .semantics {
                contentDescription = "Rank $rank: ${item.name}, " +
                    "${item.ticketsClosed} of ${item.ticketsAssigned} tickets closed, " +
                    "revenue ${currencyFmt.format(item.revenueGenerated)}"
            },
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // Rank badge
            Text(
                text = "#$rank",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = if (rank == 1) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.width(32.dp),
            )

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = item.name,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                Spacer(Modifier.height(6.dp))
                // Stat chips row
                EmployeeStatChipRow(item = item, currencyFmt = currencyFmt)
            }
        }
    }
}

@Composable
private fun EmployeeStatChipRow(
    item: EmployeePerformanceItem,
    currencyFmt: NumberFormat,
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        EmployeeStatChip(
            label = "${item.ticketsClosed}/${item.ticketsAssigned} tickets",
            contentDesc = "${item.ticketsClosed} tickets closed out of ${item.ticketsAssigned} assigned",
        )
        EmployeeStatChip(
            label = "${item.hoursWorked.toInt()}h worked",
            contentDesc = "${item.hoursWorked} hours worked",
        )
        EmployeeStatChip(
            label = currencyFmt.format(item.revenueGenerated),
            contentDesc = "Revenue generated: ${currencyFmt.format(item.revenueGenerated)}",
        )
        if (item.commissionEarned > 0) {
            EmployeeStatChip(
                label = "Comm: ${currencyFmt.format(item.commissionEarned)}",
                contentDesc = "Commission earned: ${currencyFmt.format(item.commissionEarned)}",
            )
        }
    }
}

@Composable
private fun EmployeeStatChip(label: String, contentDesc: String) {
    SuggestionChip(
        onClick = {},
        label = {
            Text(
                text = label,
                style = MaterialTheme.typography.labelSmall,
            )
        },
        modifier = Modifier.semantics { contentDescription = contentDesc },
    )
}

// ─── CSV export ───────────────────────────────────────────────────────────────

internal fun buildEmployeesCsv(items: List<EmployeePerformanceItem>): String = buildString {
    appendLine("Rank,Name,Tickets Assigned,Tickets Closed,Hours Worked,Revenue Generated,Commission Earned,Avg Ticket Value")
    items.forEachIndexed { index, item ->
        appendLine(
            "${index + 1}," +
                "${item.name}," +
                "${item.ticketsAssigned}," +
                "${item.ticketsClosed}," +
                "${"%.1f".format(item.hoursWorked)}," +
                "${"%.2f".format(item.revenueGenerated)}," +
                "${"%.2f".format(item.commissionEarned)}," +
                "${"%.2f".format(item.avgTicketValue)}"
        )
    }
}
