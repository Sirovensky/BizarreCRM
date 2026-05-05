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
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.SuggestionChipDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.screens.reports.components.ReportsExportActions
import com.bizarreelectronics.crm.ui.theme.ErrorRed
import com.bizarreelectronics.crm.ui.theme.SuccessGreen
import java.util.Locale

/**
 * Tickets report screen (ActionPlan §15.3).
 *
 * Implements:
 *   - Stat tile row: Created / Closed / Avg turnaround / SLA breaches (§15.3 throughput)
 *   - Per-tech breakdown table: assigned, closed, avg turnaround, SLA % chip (§15.3 SLA compliance)
 *   - CSV + print export via [ReportsExportActions]
 *   - Loading / error / empty states
 *   - TalkBack contentDescription on every metric tile
 *
 * Rendered by ReportsScreen when [ReportType.TICKETS] is selected.
 * The ViewModel is shared with the parent; data is loaded by [ReportsViewModel.loadTicketsReport].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TicketsReportScreen(
    viewModel: ReportsViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val report = state.ticketsReport

    // Trigger load when this screen first appears, mirroring EmployeesReportScreen pattern.
    LaunchedEffect(Unit) {
        if (!state.isTicketsReportLoading && report.totalCreated == 0 && report.byTech.isEmpty()) {
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
                        csvContent = { buildTicketsCsv(report) },
                        printHtmlContent = { buildTicketsHtml(report) },
                    )
                },
            )
        },
    ) { padding ->
        if (state.isTicketsReportLoading) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                contentAlignment = Alignment.Center,
            ) {
                CircularProgressIndicator(modifier = Modifier.size(40.dp))
            }
            return@Scaffold
        }

        if (state.ticketsReportError != null) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                contentAlignment = Alignment.Center,
            ) {
                ErrorState(
                    message = state.ticketsReportError ?: "Failed to load tickets report.",
                    onRetry = { viewModel.loadTicketsReport() },
                )
            }
            return@Scaffold
        }

        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // ── Summary stat tiles ────────────────────────────────────────────
            item {
                Text(
                    text = "Summary",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.semantics { heading() },
                )
            }
            item {
                TicketStatTilesRow(report = report)
            }

            // ── Per-tech breakdown heading ─────────────────────────────────────
            if (report.byTech.isNotEmpty()) {
                item {
                    Spacer(Modifier.height(4.dp))
                    Text(
                        text = "Technician Breakdown",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.semantics { heading() },
                    )
                }

                itemsIndexed(report.byTech, key = { _, row -> row.id }) { index, tech ->
                    TechTicketsCard(tech = tech)
                    if (index < report.byTech.lastIndex) {
                        HorizontalDivider(
                            modifier = Modifier.padding(horizontal = 4.dp),
                            color = MaterialTheme.colorScheme.outlineVariant,
                        )
                    }
                }
            } else if (!state.isTicketsReportLoading) {
                item {
                    Card(
                        modifier = Modifier.fillMaxWidth(),
                        colors = CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.surfaceVariant,
                        ),
                    ) {
                        Text(
                            text = "No technician data available for this period.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(16.dp),
                        )
                    }
                }
            }
        }
    }
}

// ─── Summary stat tiles ──────────────────────────────────────────────────────

@Composable
private fun TicketStatTilesRow(report: TicketsReport) {
    val avgFormatted = if (report.avgTurnaroundHours > 0.0) {
        val h = report.avgTurnaroundHours
        if (h < 24.0) "%.1fh".format(h)
        else "%.1fd".format(h / 24.0)
    } else "—"

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        TicketStatTile(
            label = "Created",
            value = report.totalCreated.toString(),
            a11yDesc = "${report.totalCreated} tickets created",
            modifier = Modifier.weight(1f),
        )
        TicketStatTile(
            label = "Closed",
            value = report.totalClosed.toString(),
            a11yDesc = "${report.totalClosed} tickets closed",
            modifier = Modifier.weight(1f),
        )
        TicketStatTile(
            label = "Avg Time",
            value = avgFormatted,
            a11yDesc = "Average turnaround $avgFormatted",
            modifier = Modifier.weight(1f),
        )
        TicketStatTile(
            label = "SLA Breaks",
            value = report.slaBreaches.toString(),
            a11yDesc = "${report.slaBreaches} SLA breaches",
            valueColor = if (report.slaBreaches > 0) ErrorRed else null,
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
private fun TicketStatTile(
    label: String,
    value: String,
    a11yDesc: String,
    valueColor: Color? = null,
    modifier: Modifier = Modifier,
) {
    Card(
        modifier = modifier.semantics { contentDescription = a11yDesc },
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 10.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = value,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold,
                color = valueColor ?: MaterialTheme.colorScheme.primary,
            )
            Text(
                text = label,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// ─── Per-tech row ─────────────────────────────────────────────────────────────

@Composable
private fun TechTicketsCard(tech: TechTicketsRow) {
    val avgFormatted = if (tech.avgTurnaroundHours > 0.0) {
        val h = tech.avgTurnaroundHours
        if (h < 24.0) "%.1fh".format(h) else "%.1fd".format(h / 24.0)
    } else "—"

    val a11yDesc = buildString {
        append("${tech.name}: ")
        append("${tech.ticketsAssigned} assigned, ${tech.ticketsClosed} closed")
        if (tech.avgTurnaroundHours > 0) append(", avg $avgFormatted")
        tech.slaCompliancePct?.let { append(", SLA compliance %.0f%%".format(it)) }
    }

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .semantics { contentDescription = a11yDesc },
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant,
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = tech.name,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.weight(1f),
                )
                tech.slaCompliancePct?.let { pct ->
                    SlaComplianceChip(pct = pct)
                }
            }
            Spacer(Modifier.height(6.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                TechStat(label = "Assigned", value = tech.ticketsAssigned.toString())
                TechStat(label = "Closed",   value = tech.ticketsClosed.toString())
                TechStat(label = "Avg",      value = avgFormatted)
            }
        }
    }
}

@Composable
private fun TechStat(label: String, value: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            text = value,
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onSurface,
        )
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/** SLA compliance chip: green ≥ 90 %, amber 70–89 %, red < 70 %. */
@Composable
private fun SlaComplianceChip(pct: Double) {
    val (containerColor, labelColor, label) = when {
        pct >= 90.0 -> Triple(
            SuccessGreen.copy(alpha = 0.15f),
            SuccessGreen,
            "SLA %.0f%%".format(pct),
        )
        pct >= 70.0 -> Triple(
            MaterialTheme.colorScheme.tertiaryContainer,
            MaterialTheme.colorScheme.onTertiaryContainer,
            "SLA %.0f%%".format(pct),
        )
        else -> Triple(
            MaterialTheme.colorScheme.errorContainer,
            MaterialTheme.colorScheme.onErrorContainer,
            "SLA %.0f%%".format(pct),
        )
    }
    SuggestionChip(
        onClick = {},
        label = {
            Text(
                text = label,
                style = MaterialTheme.typography.labelSmall,
                color = labelColor,
            )
        },
        colors = SuggestionChipDefaults.suggestionChipColors(
            containerColor = containerColor,
        ),
        border = null,
        modifier = Modifier.semantics {
            contentDescription = "SLA compliance %.0f percent".format(pct)
        },
    )
}

// ─── CSV / HTML builders ──────────────────────────────────────────────────────

private fun buildTicketsCsv(report: TicketsReport): String = buildString {
    appendLine("Metric,Value")
    appendLine("Total Created,${report.totalCreated}")
    appendLine("Total Closed,${report.totalClosed}")
    appendLine("Avg Turnaround (h),%.2f".format(report.avgTurnaroundHours))
    appendLine("SLA Breaches,${report.slaBreaches}")
    if (report.byTech.isNotEmpty()) {
        appendLine()
        appendLine("Name,Assigned,Closed,Avg Turnaround (h),SLA Compliance %")
        report.byTech.forEach { t ->
            val sla = t.slaCompliancePct?.let { "%.1f".format(it) } ?: ""
            appendLine("${t.name},${t.ticketsAssigned},${t.ticketsClosed}," +
                "%.2f".format(t.avgTurnaroundHours)+",$sla")
        }
    }
}

private fun buildTicketsHtml(report: TicketsReport): String = buildString {
    val exported = java.text.SimpleDateFormat("MMM d, yyyy", Locale.US)
        .format(java.util.Date())
    append("""
        <html><head><meta charset="utf-8">
        <style>
          body{font-family:sans-serif;margin:24px;color:#1a1a1a}
          h1{font-size:20px;margin-bottom:4px}
          p.period{font-size:13px;color:#666;margin:0 0 16px}
          table{width:100%;border-collapse:collapse;font-size:14px}
          th{background:#2c2c2c;color:#fff;text-align:left;padding:8px 12px}
          td{padding:8px 12px;border-bottom:1px solid #e0e0e0}
          td.num{text-align:right}
          .sla-ok{color:#2e7d32} .sla-warn{color:#e65100} .sla-bad{color:#c62828}
        </style></head><body>
        <h1>Tickets Report — Bizarre Electronics</h1>
        <p class="period">Exported $exported</p>
        <table>
          <thead><tr><th>Metric</th><th>Value</th></tr></thead>
          <tbody>
            <tr><td>Total Created</td><td class="num">${report.totalCreated}</td></tr>
            <tr><td>Total Closed</td><td class="num">${report.totalClosed}</td></tr>
            <tr><td>Avg Turnaround</td><td class="num">${"%.1f".format(report.avgTurnaroundHours)} h</td></tr>
            <tr><td>SLA Breaches</td><td class="num">${report.slaBreaches}</td></tr>
          </tbody>
        </table>
    """.trimIndent())
    if (report.byTech.isNotEmpty()) {
        append("""
            <h2 style="font-size:16px;margin-top:24px">Technician Breakdown</h2>
            <table>
              <thead><tr><th>Name</th><th>Assigned</th><th>Closed</th>
                <th>Avg (h)</th><th>SLA %</th></tr></thead>
              <tbody>
        """.trimIndent())
        report.byTech.forEach { t ->
            val slaClass = when {
                t.slaCompliancePct == null -> ""
                t.slaCompliancePct >= 90.0 -> "class=\"sla-ok\""
                t.slaCompliancePct >= 70.0 -> "class=\"sla-warn\""
                else -> "class=\"sla-bad\""
            }
            val slaVal = t.slaCompliancePct?.let { "%.0f%%".format(it) } ?: "—"
            append("<tr>")
            append("<td>${t.name}</td>")
            append("<td class=\"num\">${t.ticketsAssigned}</td>")
            append("<td class=\"num\">${t.ticketsClosed}</td>")
            append("<td class=\"num\">${"%.1f".format(t.avgTurnaroundHours)}</td>")
            append("<td class=\"num\" $slaClass>$slaVal</td>")
            append("</tr>")
        }
        append("</tbody></table>")
    }
    append("</body></html>")
}
