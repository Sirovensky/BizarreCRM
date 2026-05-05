package com.bizarreelectronics.crm.ui.screens.inventory.components

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.dto.StockMovement
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.theme.BrandMono
import com.bizarreelectronics.crm.ui.theme.SuccessGreen

/**
 * Full paginated movement history for an inventory item (L1071).
 *
 * Displays movements in a [LazyColumn] with cursor-based pagination — more rows
 * are loaded when the user scrolls near the bottom. Each row shows:
 *   - Movement type badge (IN / OUT / ADJUST) colour-coded green/red/amber
 *   - Quantity delta with sign
 *   - Reason (when present)
 *   - User name + timestamp
 *
 * @param movements      Already-loaded page of movements (most-recent first).
 * @param isLoadingMore  True while the next page fetch is in-flight.
 * @param hasMore        False once the server confirms no further pages exist.
 * @param offlineMessage Non-null when movements are unavailable offline.
 * @param onLoadMore     Invoked when the list reaches the last visible item and
 *                       [hasMore] is true. Caller triggers the next page fetch.
 * @param modifier       Applied to the root composable.
 */
@Composable
fun InventoryMovementHistory(
    movements: List<StockMovement>,
    isLoadingMore: Boolean,
    hasMore: Boolean,
    offlineMessage: String?,
    onLoadMore: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val listState = rememberLazyListState()

    // Trigger next-page load when the list is near the bottom.
    val shouldLoadMore by remember {
        derivedStateOf {
            val lastVisible = listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0
            val total = listState.layoutInfo.totalItemsCount
            hasMore && !isLoadingMore && total > 0 && lastVisible >= total - 3
        }
    }

    LaunchedEffect(shouldLoadMore) {
        if (shouldLoadMore) onLoadMore()
    }

    Column(modifier = modifier.fillMaxWidth()) {
        Text(
            "Stock movements",
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.padding(bottom = 8.dp),
        )

        when {
            offlineMessage != null -> {
                BrandCard(modifier = Modifier.fillMaxWidth()) {
                    Text(
                        offlineMessage,
                        modifier = Modifier.padding(16.dp),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            movements.isEmpty() && !isLoadingMore -> {
                BrandCard(modifier = Modifier.fillMaxWidth()) {
                    Text(
                        "No stock movements recorded",
                        modifier = Modifier.padding(16.dp),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            else -> {
                MovementList(
                    movements = movements,
                    isLoadingMore = isLoadingMore,
                    listState = listState,
                )
            }
        }
    }
}

@Composable
private fun MovementList(
    movements: List<StockMovement>,
    isLoadingMore: Boolean,
    listState: LazyListState,
) {
    // Embedded non-scrolling list — the parent LazyColumn owns the scroll.
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        movements.forEach { movement ->
            MovementRow(movement = movement)
        }
        if (isLoadingMore) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(8.dp),
                contentAlignment = Alignment.Center,
            ) {
                CircularProgressIndicator(
                    modifier = Modifier.size(24.dp),
                    strokeWidth = 2.dp,
                )
            }
        }
    }
}

@Composable
private fun MovementRow(movement: StockMovement) {
    val qty = movement.quantity ?: 0
    val (typeLabel, typeColor) = when (movement.type?.lowercase()) {
        "purchase", "receive", "received", "in" -> "IN" to SuccessGreen
        "sale", "sold", "out" -> "OUT" to MaterialTheme.colorScheme.error
        else -> "ADJ" to MaterialTheme.colorScheme.tertiary
    }

    BrandCard(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .padding(12.dp)
                .fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // Type badge
            Surface(
                shape = MaterialTheme.shapes.extraSmall,
                color = typeColor.copy(alpha = 0.15f),
            ) {
                Text(
                    typeLabel,
                    modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                    style = MaterialTheme.typography.labelSmall,
                    color = typeColor,
                )
            }

            Spacer(modifier = Modifier.width(8.dp))

            // Reason + user + timestamp
            Column(modifier = Modifier.weight(1f)) {
                if (!movement.reason.isNullOrBlank()) {
                    Text(
                        movement.reason,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                val meta = buildString {
                    movement.userName?.takeIf { it.isNotBlank() }?.let { append(it) }
                    movement.createdAt?.take(16)?.replace("T", " ")?.let {
                        if (isNotEmpty()) append("  ")
                        append(it)
                    }
                }
                if (meta.isNotBlank()) {
                    Text(
                        meta,
                        style = BrandMono,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            // Delta
            Text(
                if (qty > 0) "+$qty" else "$qty",
                style = MaterialTheme.typography.titleSmall,
                color = if (qty >= 0) SuccessGreen else MaterialTheme.colorScheme.error,
            )
        }
    }
}
