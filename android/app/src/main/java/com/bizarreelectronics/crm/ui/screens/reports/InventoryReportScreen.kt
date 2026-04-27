package com.bizarreelectronics.crm.ui.screens.reports

import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
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
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Inventory report screen (ActionPlan §15.5).
 *
 * Wired to GET /reports/inventory.  Renders:
 *   - Summary stat tiles: low-stock count, out-of-stock count, total cost value
 *   - Low-stock items table (items at or below reorder level)
 *   - Top-moving items (most used in repairs last 30 days)
 *   - Inventory value breakdown by item type
 *
 * NOTE §15.5 Shrinkage %: server endpoint has no shrinkage/adjustment tracking.
 * Left [ ] until an inventory-adjustments audit table + shrinkage query is added.
 *
 * NOTE §15.5 Sell-through rate: requires historical on-hand snapshots which are
 * not stored server-side.  Left [~] — deferred.
 *
 * NOTE §15.5 Dead-stock age: requires oldest-purchase-date per SKU with zero sales;
 * not in current /reports/inventory response.  Left [~] — deferred.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InventoryReportScreen(
    viewModel: ReportsViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    LaunchedEffect(Unit) {
        if (state.inventoryReport.lowStock.isEmpty() && !state.isInventoryLoading) {
            viewModel.loadInventoryReport()
        }
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Inventory Report",
                actions = {
                    ReportsExportActions(
                        reportTitle = "Inventory_Report",
                        csvContent = { buildInventoryCsv(state.inventoryReport) },
                        printHtmlContent = { buildInventoryHtml(state.inventoryReport) },
                    )
                },
            )
        },
    ) { padding ->
        when {
            state.isInventoryLoading -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            }
            state.inventoryError != null -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    ErrorState(
                        message = state.inventoryError!!,
                        onRetry = { viewModel.loadInventoryReport() },
                    )
                }
            }
            else -> {
                val report = state.inventoryReport
                LazyColumn(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    // Summary stat tiles
                    item {
                        val totalCost = report.valueSummary.sumOf { it.totalCostValue }
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            InvStatTile(
                                label = "Low Stock",
                                value = "${report.lowStock.size}",
                                modifier = Modifier.weight(1f),
                            )
                            InvStatTile(
                                label = "Out of Stock",
                                value = "${report.outOfStock}",
                                modifier = Modifier.weight(1f),
                            )
                            InvStatTile(
                                label = "Cost Value",
                                value = CurrencyFormatter.format(totalCost),
                                modifier = Modifier.weight(1f),
                            )
                        }
                    }

                    // Stock value by type
                    if (report.valueSummary.isNotEmpty()) {
                        item {
                            Text(
                                "Stock Value by Type",
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.SemiBold,
                                modifier = Modifier.semantics { heading() },
                            )
                        }
                        items(report.valueSummary, key = { it.itemType }) { row ->
                            Card(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .semantics(mergeDescendants = true) {
                                        contentDescription = "${row.itemType}: ${row.itemCount} items, cost ${CurrencyFormatter.format(row.totalCostValue)}, retail ${CurrencyFormatter.format(row.totalRetailValue)}"
                                    },
                                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                                elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
                            ) {
                                Row(
                                    modifier = Modifier.fillMaxWidth().padding(12.dp),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                ) {
                                    Column {
                                        Text(
                                            row.itemType.replaceFirstChar { it.uppercase() },
                                            style = MaterialTheme.typography.bodyMedium,
                                            fontWeight = FontWeight.SemiBold,
                                        )
                                        Text(
                                            "${row.itemCount} items · ${row.totalUnits} units",
                                            style = MaterialTheme.typography.labelSmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    }
                                    Column(horizontalAlignment = Alignment.End) {
                                        Text(
                                            CurrencyFormatter.format(row.totalRetailValue),
                                            style = MaterialTheme.typography.bodyMedium,
                                            fontWeight = FontWeight.Bold,
                                            color = MaterialTheme.colorScheme.primary,
                                        )
                                        Text(
                                            "cost ${CurrencyFormatter.format(row.totalCostValue)}",
                                            style = MaterialTheme.typography.labelSmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    }
                                }
                            }
                        }
                    }

                    // Low stock items
                    if (report.lowStock.isNotEmpty()) {
                        item {
                            Text(
                                "Low Stock Items",
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.SemiBold,
                                modifier = Modifier.semantics { heading() },
                            )
                        }
                        items(report.lowStock, key = { it.id }) { item ->
                            Card(
                                modifier = Modifier.fillMaxWidth(),
                                colors = CardDefaults.cardColors(
                                    containerColor = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.3f),
                                ),
                            ) {
                                Row(
                                    modifier = Modifier.fillMaxWidth().padding(12.dp),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(item.name, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
                                        Text(
                                            item.sku,
                                            style = MaterialTheme.typography.labelSmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    }
                                    Text(
                                        "${item.inStock} / ${item.reorderLevel}",
                                        style = MaterialTheme.typography.bodySmall,
                                        fontWeight = FontWeight.SemiBold,
                                        color = MaterialTheme.colorScheme.error,
                                    )
                                }
                            }
                        }
                    }

                    // Top moving items
                    if (report.topMoving.isNotEmpty()) {
                        item {
                            Text(
                                "Top Moving Items (Last 30 Days)",
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.SemiBold,
                                modifier = Modifier.semantics { heading() },
                            )
                        }
                        items(report.topMoving, key = { it.sku }) { item ->
                            Card(
                                modifier = Modifier.fillMaxWidth(),
                                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                                elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
                            ) {
                                Row(
                                    modifier = Modifier.fillMaxWidth().padding(12.dp),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(item.name, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
                                        Text(item.sku, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }
                                    Column(horizontalAlignment = Alignment.End) {
                                        Text(
                                            "${item.usedQty} used",
                                            style = MaterialTheme.typography.bodySmall,
                                            fontWeight = FontWeight.SemiBold,
                                            color = MaterialTheme.colorScheme.primary,
                                        )
                                        Text(
                                            "${item.inStock} in stock",
                                            style = MaterialTheme.typography.labelSmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    }
                                }
                            }
                        }
                    }

                    // Deferred items note
                    item {
                        Card(
                            modifier = Modifier.fillMaxWidth(),
                            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
                        ) {
                            Text(
                                "Shrinkage %, sell-through rate, and dead-stock age are deferred — require server-side tracking not yet implemented.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.padding(12.dp),
                                textAlign = TextAlign.Start,
                            )
                        }
                    }
                }
            }
        }
    }
}

// ─── Composables ─────────────────────────────────────────────────────────────

@Composable
private fun InvStatTile(label: String, value: String, modifier: Modifier = Modifier) {
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

// ─── CSV / HTML builders ──────────────────────────────────────────────────────

private fun buildInventoryCsv(report: InventoryReport): String = buildString {
    appendLine("Category,Value")
    appendLine("Low Stock Items,${report.lowStock.size}")
    appendLine("Out of Stock,${report.outOfStock}")
    val totalCost = report.valueSummary.sumOf { it.totalCostValue }
    val totalRetail = report.valueSummary.sumOf { it.totalRetailValue }
    appendLine("Total Cost Value,${"%.2f".format(totalCost)}")
    appendLine("Total Retail Value,${"%.2f".format(totalRetail)}")
    if (report.lowStock.isNotEmpty()) {
        appendLine()
        appendLine("Low Stock — Name,SKU,In Stock,Reorder Level")
        report.lowStock.forEach { appendLine("${it.name},${it.sku},${it.inStock},${it.reorderLevel}") }
    }
    if (report.topMoving.isNotEmpty()) {
        appendLine()
        appendLine("Top Moving — Name,SKU,Used Qty,In Stock")
        report.topMoving.forEach { appendLine("${it.name},${it.sku},${it.usedQty},${it.inStock}") }
    }
}

private fun buildInventoryHtml(report: InventoryReport): String = buildString {
    val dateStr = SimpleDateFormat("MMM d, yyyy", Locale.US).format(Date())
    val totalCost = report.valueSummary.sumOf { it.totalCostValue }
    val totalRetail = report.valueSummary.sumOf { it.totalRetailValue }
    append("""
        <html><head><meta charset="utf-8">
        <style>
          body{font-family:sans-serif;margin:24px;color:#1a1a1a}
          h1{font-size:20px;margin-bottom:4px}
          h2{font-size:16px;margin-top:24px}
          p.period{font-size:13px;color:#666;margin:0 0 16px}
          table{width:100%;border-collapse:collapse;font-size:14px}
          th{background:#2c2c2c;color:#fff;text-align:left;padding:8px 12px}
          td{padding:8px 12px;border-bottom:1px solid #e0e0e0}
          td.num{text-align:right}
          td.warn{color:#c62828}
        </style></head><body>
        <h1>Inventory Report — Bizarre Electronics</h1>
        <p class="period">Exported $dateStr</p>
        <table>
          <thead><tr><th>Metric</th><th>Value</th></tr></thead>
          <tbody>
            <tr><td>Low Stock Items</td><td class="num">${report.lowStock.size}</td></tr>
            <tr><td>Out of Stock</td><td class="num warn">${report.outOfStock}</td></tr>
            <tr><td>Total Cost Value</td><td class="num">${CurrencyFormatter.format(totalCost)}</td></tr>
            <tr><td>Total Retail Value</td><td class="num">${CurrencyFormatter.format(totalRetail)}</td></tr>
          </tbody>
        </table>
    """.trimIndent())
    if (report.lowStock.isNotEmpty()) {
        append("<h2>Low Stock Items</h2><table><thead><tr><th>Name</th><th>SKU</th><th>In Stock</th><th>Reorder Level</th></tr></thead><tbody>")
        report.lowStock.forEach { item ->
            append("<tr><td>${item.name}</td><td>${item.sku}</td><td class=\"num warn\">${item.inStock}</td><td class=\"num\">${item.reorderLevel}</td></tr>")
        }
        append("</tbody></table>")
    }
    if (report.topMoving.isNotEmpty()) {
        append("<h2>Top Moving (Last 30 Days)</h2><table><thead><tr><th>Name</th><th>SKU</th><th>Used</th><th>In Stock</th></tr></thead><tbody>")
        report.topMoving.forEach { item ->
            append("<tr><td>${item.name}</td><td>${item.sku}</td><td class=\"num\">${item.usedQty}</td><td class=\"num\">${item.inStock}</td></tr>")
        }
        append("</tbody></table>")
    }
    append("</body></html>")
}
