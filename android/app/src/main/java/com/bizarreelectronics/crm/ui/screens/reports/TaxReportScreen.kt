package com.bizarreelectronics.crm.ui.screens.reports

import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.screens.reports.components.ReportsExportActions

/**
 * Tax report screen (ActionPlan §15 L1747-L1750).
 *
 * Shows tax collected by class and a total row.
 * Data is a stub until /reports/tax endpoint ships.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TaxReportScreen(
    viewModel: ReportsViewModel = hiltViewModel(),
) {
    // Placeholder rows until the endpoint is live.
    val taxRows = listOf(
        TaxRow("Standard (8%)", "—"),
        TaxRow("Reduced (4%)", "—"),
        TaxRow("Zero-rated", "\$0.00"),
    )
    val total = "—"

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Tax Report",
                actions = {
                    ReportsExportActions(
                        reportTitle = "Tax_Report",
                        csvContent = { buildTaxCsv(taxRows, total) },
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
            item {
                Text(
                    "Tax Collected by Class",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.semantics { heading() },
                )
            }
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.surface,
                    ),
                    elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
                ) {
                    taxRows.forEachIndexed { index, row ->
                        TaxRowItem(row)
                        if (index < taxRows.lastIndex) {
                            HorizontalDivider(modifier = Modifier.padding(horizontal = 16.dp))
                        }
                    }
                    HorizontalDivider(modifier = Modifier.padding(horizontal = 16.dp))
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 12.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("Total", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold)
                        Text(
                            total,
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                }
            }
            item {
                Text(
                    "Full tax breakdown by class available once /reports/tax endpoint ships.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

private data class TaxRow(val label: String, val amount: String)

@Composable
private fun TaxRowItem(row: TaxRow) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(row.label, style = MaterialTheme.typography.bodyMedium)
        Text(row.amount, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
    }
}

private fun buildTaxCsv(rows: List<TaxRow>, total: String): String = buildString {
    appendLine("Tax Class,Amount Collected")
    rows.forEach { appendLine("${it.label},${it.amount}") }
    appendLine("Total,$total")
}
