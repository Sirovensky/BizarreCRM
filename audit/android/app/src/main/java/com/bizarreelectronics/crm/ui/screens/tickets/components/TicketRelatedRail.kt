package com.bizarreelectronics.crm.ui.screens.tickets.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.bizarreelectronics.crm.data.remote.dto.TicketListItem
import com.bizarreelectronics.crm.data.remote.dto.TicketPhoto
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.util.isMediumOrExpandedWidth

/**
 * TicketRelatedRail — §4.2 L677
 *
 * Tablet-only (width >= 600dp) right-side rail showing contextual
 * customer history. On phone form-factors this composable emits nothing
 * (zero size), so callers can unconditionally include it in their layout.
 *
 * Content sections:
 * 1. Recent tickets from the same customer (up to 5).
 * 2. Photo wallet — small thumbnail grid from [photos].
 * 3. Health score ring placeholder + LTV tier chip.
 *
 * Data comes from the parent screen's already-loaded state to avoid a
 * second repository call; if not provided the section is hidden.
 *
 * @param recentTickets Up to 5 recent tickets for the same customer.
 * @param photos        All photos for this ticket (re-used for wallet grid).
 * @param ltvTierLabel  Human-readable LTV tier (e.g. "Gold", "VIP") or null.
 * @param healthScore   0–100 health score for the customer, or null.
 * @param serverUrl     Base URL for resolving photo thumbnail URLs.
 * @param onNavigateToTicket Navigation callback when a related ticket row is tapped.
 */
@Composable
fun TicketRelatedRail(
    recentTickets: List<TicketListItem> = emptyList(),
    photos: List<TicketPhoto> = emptyList(),
    ltvTierLabel: String? = null,
    healthScore: Int? = null,
    serverUrl: String = "",
    onNavigateToTicket: (Long) -> Unit = {},
) {
    // Rail is visible only on tablet/desktop breakpoints
    if (!isMediumOrExpandedWidth()) return

    LazyColumn(
        modifier = Modifier
            .width(260.dp)
            .fillMaxHeight()
            .padding(start = 8.dp, end = 8.dp, top = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // LTV tier + health score header
        item {
            BrandCard(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text(
                        "Customer Insights",
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    if (ltvTierLabel != null) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("LTV Tier: ", style = MaterialTheme.typography.bodySmall)
                            Surface(
                                color = MaterialTheme.colorScheme.primaryContainer,
                                shape = RoundedCornerShape(12.dp),
                            ) {
                                Text(
                                    ltvTierLabel,
                                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                                    style = MaterialTheme.typography.labelSmall,
                                    fontWeight = FontWeight.SemiBold,
                                    color = MaterialTheme.colorScheme.onPrimaryContainer,
                                )
                            }
                        }
                        Spacer(modifier = Modifier.height(4.dp))
                    }
                    if (healthScore != null) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("Health: ", style = MaterialTheme.typography.bodySmall)
                            // Score ring — simple text representation; future work: Canvas arc
                            Surface(
                                color = when {
                                    healthScore >= 80 -> MaterialTheme.colorScheme.tertiaryContainer
                                    healthScore >= 50 -> MaterialTheme.colorScheme.secondaryContainer
                                    else -> MaterialTheme.colorScheme.errorContainer
                                },
                                shape = RoundedCornerShape(12.dp),
                            ) {
                                Text(
                                    "$healthScore / 100",
                                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                                    style = MaterialTheme.typography.labelSmall,
                                    fontWeight = FontWeight.SemiBold,
                                    color = MaterialTheme.colorScheme.onSurface,
                                )
                            }
                        }
                    }
                    if (ltvTierLabel == null && healthScore == null) {
                        Text(
                            "No customer insights available.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }

        // Recent tickets section
        if (recentTickets.isNotEmpty()) {
            item {
                Text(
                    "Recent Tickets",
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 4.dp),
                )
            }
            items(recentTickets.take(5), key = { it.id }) { t ->
                BrandCard(
                    modifier = Modifier.fillMaxWidth(),
                    onClick = { onNavigateToTicket(t.id) },
                ) {
                    Column(modifier = Modifier.padding(10.dp)) {
                        Text(
                            t.orderId,
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.primary,
                        )
                        Text(
                            t.statusName ?: "—",
                            style = MaterialTheme.typography.bodySmall,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
            }
        }

        // Photo wallet grid
        if (photos.isNotEmpty()) {
            item {
                Text(
                    "Photo Wallet",
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 4.dp),
                )
            }
            item {
                // 3-column grid using chunked rows
                val rows = photos.chunked(3)
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    rows.forEach { row ->
                        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            row.forEach { photo ->
                                AsyncImage(
                                    model = "$serverUrl${photo.url}",
                                    contentDescription = photo.type ?: "photo",
                                    contentScale = ContentScale.Crop,
                                    modifier = Modifier
                                        .size(76.dp)
                                        .clip(RoundedCornerShape(6.dp)),
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
