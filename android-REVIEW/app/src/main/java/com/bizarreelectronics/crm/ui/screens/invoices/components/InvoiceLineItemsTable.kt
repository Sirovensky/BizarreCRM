package com.bizarreelectronics.crm.ui.screens.invoices.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.dto.InvoiceLineItem
import com.bizarreelectronics.crm.ui.theme.BrandMono

/**
 * Read-only table of [InvoiceLineItem] rows.
 *
 * Layout: Description (weight 1f) | Qty (fixed) | Unit price (fixed) | Total (fixed)
 *
 * Renders as a plain Column of rows (not a LazyColumn) so it can be embedded
 * inside the detail screen's outer LazyColumn without nesting conflicts.
 * The header row has a contrasting background. Each data row is separated by a
 * hairline divider.
 */
@Composable
fun InvoiceLineItemsTable(
    lineItems: List<InvoiceLineItem>,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.fillMaxWidth()) {
        // Header row
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.surfaceVariant)
                .padding(horizontal = 12.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                "Description",
                modifier = Modifier.weight(1f),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                "Qty",
                modifier = Modifier.padding(start = 8.dp),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontWeight = FontWeight.SemiBold,
                textAlign = TextAlign.End,
            )
            Text(
                "Unit",
                modifier = Modifier.padding(start = 8.dp),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontWeight = FontWeight.SemiBold,
                textAlign = TextAlign.End,
            )
            Text(
                "Total",
                modifier = Modifier.padding(start = 8.dp),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontWeight = FontWeight.SemiBold,
                textAlign = TextAlign.End,
            )
        }

        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

        lineItems.forEachIndexed { index, item ->
            LineItemRow(item = item)
            if (index < lineItems.lastIndex) {
                HorizontalDivider(
                    color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f),
                    thickness = 0.5.dp,
                )
            }
        }

        if (lineItems.isEmpty()) {
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                "No line items",
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(12.dp),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun LineItemRow(item: InvoiceLineItem) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.Top,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                item.name ?: "Item",
                style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.Medium,
            )
            if (!item.sku.isNullOrBlank()) {
                Text(
                    item.sku,
                    style = MaterialTheme.typography.labelSmall.copy(
                        fontFamily = BrandMono.fontFamily,
                    ),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (!item.description.isNullOrBlank() && item.description != item.name) {
                Text(
                    item.description,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        Text(
            "${item.quantity ?: 1}",
            modifier = Modifier.padding(start = 8.dp),
            style = MaterialTheme.typography.bodySmall,
            textAlign = TextAlign.End,
        )
        Text(
            "$${"%.2f".format(item.price ?: 0.0)}",
            modifier = Modifier.padding(start = 8.dp),
            style = MaterialTheme.typography.bodySmall,
            textAlign = TextAlign.End,
        )
        Text(
            "$${"%.2f".format(item.total ?: 0.0)}",
            modifier = Modifier.padding(start = 8.dp),
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.primary,
            textAlign = TextAlign.End,
        )
    }
}
