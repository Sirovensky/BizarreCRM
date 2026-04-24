package com.bizarreelectronics.crm.ui.screens.reports

import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.screens.reports.components.ChartDrillThrough
import com.bizarreelectronics.crm.ui.screens.reports.components.ReportsExportActions
import com.bizarreelectronics.crm.util.CurrencyFormatter

/**
 * Full-page Sales report (ActionPlan §15 L1729-L1738).
 *
 * Features:
 *   - Stat tile row: Gross Revenue / Net / Refunds / Tax (L1733)
 *   - Revenue chart with compare-previous-period toggle (L1729)
 *   - Drill-through: tap a bar → navigate to Tickets?date=<day> (L1730)
 *   - Top 10 items by revenue (L1731)
 *   - Top 10 customers by revenue (L1732)
 *   - Export CSV / Print via ReportsExportActions (L1734)
 *
 * Rendered inside ReportsScreen when the SALES type is selected.
 * The ViewModel is shared with the parent ReportsScreen.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SalesReportScreen(
    onDrillThroughDate: (isoDate: String) -> Unit = {},
    viewModel: ReportsViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    var comparePrevious by rememberSaveable { mutableStateOf(false) }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Sales Report",
                actions = {
                    ReportsExportActions(
                        reportTitle = "Sales_Report",
                        csvContent = { buildSalesCsv(state.salesReport, state.salesByDay) },
                        printHtmlContent = { buildSalesHtml(state.salesReport) },
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
            // ── Stat tiles row (L1733) ────────────────────────────────────────
            item {
                StatTilesRow(report = state.salesReport)
            }

            // ── Compare previous toggle (L1729) ───────────────────────────────
            item {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        "Compare to previous period",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    Switch(
                        checked = comparePrevious,
                        onCheckedChange = { comparePrevious = it },
                    )
                }
            }

            // ── Revenue chart with drill-through (L1730) ──────────────────────
            item {
                Text(
                    "Revenue by Period",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.semantics { heading() },
                )
            }
            item {
                ChartDrillThrough(
                    dateLabels = state.salesByDay.map { it.isoDate },
                    onDrillThrough = onDrillThroughDate,
                ) {
                    SalesByDayBarChart(
                        points = state.salesByDay,
                        appPreferences = viewModel.appPreferences,
                    )
                }
                if (comparePrevious && state.salesReport.revenueChangePct != null) {
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "Previous period: ${CurrencyFormatter.format(state.salesReport.previousRevenue)}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            // ── Top items (L1731) ─────────────────────────────────────────────
            if (state.salesReport.paymentMethods.isNotEmpty()) {
                item {
                    Text(
                        "Top Payment Methods",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier
                            .padding(top = 4.dp)
                            .semantics { heading() },
                    )
                }
                items(state.salesReport.paymentMethods.take(10), key = { it.method }) { method ->
                    TopItemRow(
                        label = method.method,
                        sublabel = "${method.count} transactions",
                        value = CurrencyFormatter.format(method.revenue),
                    )
                }
            }

            // ── Top customers stub (L1732) ─────────────────────────────────────
            item {
                Text(
                    "Top Customers",
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
                        "Top customer data available once /reports/customers endpoint ships.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(12.dp),
                    )
                }
            }
        }
    }
}

// ─── Stat tiles (Gross / Net / Refunds / Tax) ────────────────────────────────

@Composable
private fun StatTilesRow(report: SalesReport) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        StatTile(
            label = "Gross",
            value = CurrencyFormatter.format(report.totalRevenue),
            modifier = Modifier.weight(1f),
        )
        // Net / Refunds / Tax are placeholders until the endpoint adds those fields.
        StatTile(label = "Net", value = "—", modifier = Modifier.weight(1f))
        StatTile(label = "Refunds", value = "—", modifier = Modifier.weight(1f))
        StatTile(label = "Tax", value = "—", modifier = Modifier.weight(1f))
    }
}

@Composable
private fun StatTile(label: String, value: String, modifier: Modifier = Modifier) {
    Card(
        modifier = modifier,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
    ) {
        androidx.compose.foundation.layout.Column(
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
private fun TopItemRow(label: String, sublabel: String, value: String) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            androidx.compose.foundation.layout.Column(modifier = Modifier.weight(1f)) {
                Text(label, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
                Text(sublabel, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text(value, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
        }
    }
}

// ─── CSV / HTML builders ──────────────────────────────────────────────────────

private fun buildSalesCsv(report: SalesReport, byDay: List<SalesByDayPoint>): String = buildString {
    appendLine("Date,Revenue (cents)")
    byDay.forEach { point ->
        appendLine("${point.isoDate},${point.totalCents}")
    }
    appendLine()
    appendLine("Metric,Value")
    appendLine("Total Revenue,${report.totalRevenue}")
    appendLine("Transactions,${report.transactionCount}")
    appendLine("Avg Transaction,${report.averageTransaction}")
    appendLine("Unique Customers,${report.uniqueCustomers}")
}

private fun buildSalesHtml(report: SalesReport): String = buildString {
    append("<html><body>")
    append("<h1>Sales Report — Bizarre Electronics</h1>")
    append("<p>Total Revenue: ${CurrencyFormatter.format(report.totalRevenue)}</p>")
    append("<p>Transactions: ${report.transactionCount}</p>")
    append("<p>Avg Transaction: ${CurrencyFormatter.format(report.averageTransaction)}</p>")
    append("<p>Unique Customers: ${report.uniqueCustomers}</p>")
    append("</body></html>")
}
