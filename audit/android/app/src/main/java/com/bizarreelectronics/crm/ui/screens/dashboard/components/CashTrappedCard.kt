package com.bizarreelectronics.crm.ui.screens.dashboard.components

/**
 * §3.2 L504 — Cash-Trapped card.
 *
 * Shows the total value of slow-moving inventory (items in stock whose last sale
 * was more than 90 days ago). Data comes from `GET /reports/cash-trapped`.
 *
 * Tapping the card navigates to the Aging report screen.
 *
 * States:
 *  - [totalCents] == null  → "Connect Inventory data" stub (endpoint 404 / not yet wired)
 *  - [totalCents] == 0     → "No cash trapped — inventory is moving well"
 *  - [totalCents] > 0      → formatted dollar amount + item count + chevron tap
 */

import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.theme.WarningAmber

/**
 * Data class for a single overdue-receivables / slow-stock item displayed in
 * [CashTrappedCard]. Mirrors the `top_offenders` array from the server response.
 */
data class CashTrappedItem(
    val id: Long,
    val name: String,
    val valueCents: Long,
    /** Days since last sale; null = never sold. */
    val daysSinceLastSale: Int?,
)

private const val MAX_DISPLAYED = 3

/**
 * §3.2 L504 — Dashboard card showing cash trapped in slow-moving inventory.
 *
 * @param totalCents   Total value in cents.  Null = inventory endpoint not connected.
 * @param itemCount    Number of slow-moving items. Null when [totalCents] is null.
 * @param topItems     Up to 3 worst offenders for the detail rows.
 * @param onTap        Called when the card is tapped; navigates to Aging report.
 * @param modifier     Outer layout modifier.
 */
@Composable
fun CashTrappedCard(
    totalCents: Long?,
    itemCount: Int? = null,
    topItems: List<CashTrappedItem> = emptyList(),
    onTap: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val isConnected = totalCents != null
    val isHealthy = isConnected && totalCents == 0L

    val a11yDesc = when {
        !isConnected -> "Cash Trapped: inventory data not connected."
        isHealthy    -> "Cash Trapped: no slow-moving inventory — all items are moving well."
        else -> {
            val dollars = (totalCents!! / 100.0)
            "Cash Trapped: \$${String.format("%.0f", dollars)} across ${itemCount ?: 0} slow-moving items. Tap to view aging report."
        }
    }

    val borderColor = when {
        !isConnected -> MaterialTheme.colorScheme.outline
        isHealthy    -> MaterialTheme.colorScheme.outline
        else         -> WarningAmber.copy(alpha = 0.6f)
    }

    Card(
        modifier = modifier
            .fillMaxWidth()
            .border(
                width = 1.dp,
                color = borderColor,
                shape = MaterialTheme.shapes.medium,
            )
            .semantics { contentDescription = a11yDesc }
            .then(
                if (onTap != null && isConnected && !isHealthy) {
                    Modifier
                        .semantics { role = Role.Button }
                        .clickable(onClick = onTap)
                } else Modifier,
            ),
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            // Header row
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(
                    imageVector = Icons.Default.AccountBalance,
                    contentDescription = null,
                    tint = if (!isConnected || isHealthy)
                        MaterialTheme.colorScheme.onSurfaceVariant
                    else WarningAmber,
                    modifier = Modifier.size(20.dp),
                )
                Text(
                    text = "Cash Trapped",
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f),
                )
                if (onTap != null && isConnected && !isHealthy) {
                    Icon(
                        imageVector = Icons.Default.ChevronRight,
                        contentDescription = "View aging report",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(20.dp),
                    )
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            when {
                !isConnected -> {
                    // Stub / endpoint not connected
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(48.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            text = "Connect Inventory data",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                            textAlign = TextAlign.Center,
                        )
                    }
                }
                isHealthy -> {
                    // All inventory is moving
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Default.CheckCircle,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(20.dp),
                        )
                        Text(
                            text = "No slow-moving inventory",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurface,
                        )
                    }
                }
                else -> {
                    // Show total + top offenders
                    val dollars = (totalCents!! / 100.0)
                    Text(
                        text = "\$${String.format("%.2f", dollars)}",
                        style = MaterialTheme.typography.headlineSmall,
                        color = WarningAmber,
                    )
                    if (itemCount != null && itemCount > 0) {
                        Text(
                            text = "$itemCount item${if (itemCount == 1) "" else "s"} not sold in 90+ days",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }

                    if (topItems.isNotEmpty()) {
                        Spacer(modifier = Modifier.height(8.dp))
                        topItems.take(MAX_DISPLAYED).forEachIndexed { idx, item ->
                            CashTrappedRow(item = item)
                            if (idx < (topItems.take(MAX_DISPLAYED).lastIndex)) {
                                HorizontalDivider(
                                    modifier = Modifier.padding(vertical = 3.dp),
                                    thickness = 0.5.dp,
                                    color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
                                )
                            }
                        }
                        if (topItems.size > MAX_DISPLAYED) {
                            Spacer(modifier = Modifier.height(4.dp))
                            Text(
                                text = "+${topItems.size - MAX_DISPLAYED} more — tap to view all",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun CashTrappedRow(item: CashTrappedItem) {
    val itemDollars = item.valueCents / 100.0
    val ageLabel = when {
        item.daysSinceLastSale == null -> "never sold"
        item.daysSinceLastSale > 365   -> "${item.daysSinceLastSale / 365}y+ ago"
        else                           -> "${item.daysSinceLastSale}d ago"
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 3.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            text = item.name,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.weight(1f),
            maxLines = 1,
            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
        )
        Text(
            text = "\$${String.format("%.0f", itemDollars)}",
            style = MaterialTheme.typography.labelSmall,
            color = WarningAmber,
        )
        Text(
            text = ageLabel,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
        )
    }
}
