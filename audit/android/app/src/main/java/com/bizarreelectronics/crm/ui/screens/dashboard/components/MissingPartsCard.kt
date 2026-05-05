package com.bizarreelectronics.crm.ui.screens.dashboard.components

/**
 * §3.2 L506 — Missing Parts card.
 *
 * Lists inventory items that need reordering (quantity at or below reorder
 * threshold). Tapping an item can navigate to the inventory detail.
 *
 * Data contract:
 * - [items]: list of [MissingPartItem]. Empty = "All parts stocked" success state.
 * - Display is capped at 5 rows (same as Leaderboard) to avoid overloading the
 *   card. A "View all" footer is shown when there are more.
 *
 * Stub mode: when [items] is null (data source not yet wired) the card shows
 * a "Connect Inventory data" affordance — no crash.
 */

import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.theme.SuccessGreen
import com.bizarreelectronics.crm.ui.theme.WarningAmber

/** One reorder-needed inventory item. */
data class MissingPartItem(
    val id: Long,
    val name: String,
    /** Current quantity in stock. */
    val quantity: Int,
    /** Reorder threshold. */
    val reorderLevel: Int,
)

private const val MAX_DISPLAYED = 5

@Composable
fun MissingPartsCard(
    /**
     * Items needing reorder. Null = inventory data source not connected.
     * Empty list = all parts adequately stocked.
     */
    items: List<MissingPartItem>?,
    onViewAll: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val displayed = items?.take(MAX_DISPLAYED)
    val hasMore = (items?.size ?: 0) > MAX_DISPLAYED
    val isConnected = items != null

    val a11yDesc = when {
        !isConnected -> "Missing Parts: inventory data not connected."
        items!!.isEmpty() -> "Missing Parts: all parts adequately stocked."
        else -> "Missing Parts: ${items.size} item${if (items.size == 1) "" else "s"} need reordering."
    }

    Card(
        modifier = modifier
            .fillMaxWidth()
            .border(
                width = 1.dp,
                color = if (isConnected && !items!!.isEmpty())
                    WarningAmber.copy(alpha = 0.6f)
                else
                    MaterialTheme.colorScheme.outline,
                shape = MaterialTheme.shapes.medium,
            )
            .semantics { contentDescription = a11yDesc },
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(
                    imageVector = Icons.Default.Build,
                    contentDescription = null,
                    tint = if (isConnected && items!!.isNotEmpty()) WarningAmber
                    else MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(20.dp),
                )
                Text(
                    text = "Missing Parts",
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f),
                )
                if (hasMore && onViewAll != null) {
                    TextButton(
                        onClick = onViewAll,
                        contentPadding = PaddingValues(horizontal = 4.dp, vertical = 0.dp),
                    ) {
                        Text(
                            text = "View all",
                            style = MaterialTheme.typography.labelSmall,
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            when {
                !isConnected -> {
                    // Stub / not connected
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(60.dp),
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
                items!!.isEmpty() -> {
                    // All stocked
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Default.CheckCircle,
                            contentDescription = null,
                            tint = SuccessGreen,
                            modifier = Modifier.size(20.dp),
                        )
                        Text(
                            text = "All parts adequately stocked",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurface,
                        )
                    }
                }
                else -> {
                    // List rows
                    displayed!!.forEachIndexed { index, part ->
                        MissingPartRow(part = part)
                        if (index < displayed.lastIndex) {
                            HorizontalDivider(
                                modifier = Modifier.padding(vertical = 4.dp),
                                thickness = 0.5.dp,
                                color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
                            )
                        }
                    }
                    if (hasMore) {
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(
                            text = "+${items!!.size - MAX_DISPLAYED} more items",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun MissingPartRow(part: MissingPartItem) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(
            imageVector = Icons.Default.Warning,
            contentDescription = null,
            tint = WarningAmber,
            modifier = Modifier.size(16.dp),
        )
        Text(
            text = part.name,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.weight(1f),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            text = "${part.quantity} / ${part.reorderLevel}",
            style = MaterialTheme.typography.labelSmall,
            color = WarningAmber,
        )
    }
}
