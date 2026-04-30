package com.bizarreelectronics.crm.ui.screens.reports

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * §15 Inventory Report — stub. The wave agent referenced VM fields
 * (`inventoryReport`, `isInventoryLoading`, `loadInventoryReport()`) that
 * never landed on `ReportsViewModel`, and the server `/reports/inventory`
 * endpoint is not deployed. Stubbed so the nav route resolves and the
 * build stays green; restore the rich UI when the VM surface + server
 * endpoint are in place.
 */
@Composable
fun InventoryReportScreen(
    @Suppress("UNUSED_PARAMETER") viewModel: ReportsViewModel? = null,
) {
    Box(
        modifier = Modifier.fillMaxSize().padding(24.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = "Inventory report — coming soon",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
