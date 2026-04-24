package com.bizarreelectronics.crm.ui.screens.reports

import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.screens.reports.components.ReportsExportActions

/**
 * Inventory report screen (ActionPlan §15 L1743-L1746).
 *
 * Shows:
 *   - Slow-movers: items with no sales in the last 90 days (stub)
 *   - Inventory turnover rate (stub)
 *   - Restock forecast (stub)
 *
 * Full data pending /reports/inventory endpoint.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InventoryReportScreen(
    viewModel: ReportsViewModel = hiltViewModel(),
) {
    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Inventory Report",
                actions = {
                    ReportsExportActions(
                        reportTitle = "Inventory_Report",
                        csvContent = { buildInventoryCsv() },
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
                SectionCard(
                    title = "Slow Movers",
                    body = "Items with no sales in the last 90 days will appear here once /reports/inventory ships.",
                )
            }
            item {
                SectionCard(
                    title = "Inventory Turnover",
                    body = "Turnover rate (COGS ÷ avg inventory) will appear here once the endpoint is live.",
                )
            }
            item {
                SectionCard(
                    title = "Restock Forecast",
                    body = "Predicted restock dates based on sales velocity — coming soon.",
                )
            }
        }
    }
}

@Composable
private fun SectionCard(title: String, body: String) {
    Text(
        title,
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
            body,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(12.dp),
        )
    }
}

private fun buildInventoryCsv(): String = buildString {
    appendLine("Category,Value")
    appendLine("Note,Full data pending /reports/inventory endpoint")
}
