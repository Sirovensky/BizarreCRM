package com.bizarreelectronics.crm.ui.screens.tickets.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.local.db.entities.TicketEntity
import com.bizarreelectronics.crm.util.formatAsMoney

private const val MAX_PINNED_DISPLAY = 5

// -----------------------------------------------------------------------
// PinnedTicketsHeader — shown above the main list when pins are non-empty
// -----------------------------------------------------------------------

/**
 * Horizontal row of pinned-ticket cards, rendered above the main list.
 * Only the first [MAX_PINNED_DISPLAY] (5) pinned tickets are shown.
 * Each card is tappable to open the ticket.
 *
 * @param pinnedTickets  Pinned [TicketEntity] objects from ViewModel (max 5).
 * @param onTicketClick  Open ticket detail.
 */
@Composable
fun PinnedTicketsHeader(
    pinnedTickets: List<TicketEntity>,
    onTicketClick: (Long) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (pinnedTickets.isEmpty()) return

    Column(modifier = modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = Icons.Default.Star,
                contentDescription = null,
                modifier = Modifier.size(16.dp),
                tint = MaterialTheme.colorScheme.primary,
            )
            Spacer(modifier = Modifier.width(4.dp))
            Text(
                text = "Pinned",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontWeight = FontWeight.SemiBold,
            )
        }

        LazyRow(
            contentPadding = PaddingValues(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(
                items = pinnedTickets.take(MAX_PINNED_DISPLAY),
                key = { it.id },
            ) { ticket ->
                PinnedTicketCard(
                    ticket = ticket,
                    onClick = { onTicketClick(ticket.id) },
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PinnedTicketCard(
    ticket: TicketEntity,
    onClick: () -> Unit,
) {
    val a11yDesc = buildString {
        append("Pinned ticket ${ticket.orderId}")
        ticket.customerName?.let { append(", $it") }
        ticket.statusName?.let { append(", ${it}") }
    }
    Card(
        onClick = onClick,
        modifier = Modifier
            .width(160.dp)
            .semantics { contentDescription = a11yDesc },
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
        ),
    ) {
        Column(modifier = Modifier.padding(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = Icons.Default.Star,
                    contentDescription = null,
                    modifier = Modifier.size(14.dp),
                    tint = MaterialTheme.colorScheme.primary,
                )
                Spacer(modifier = Modifier.width(4.dp))
                Text(
                    text = ticket.orderId,
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Medium,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                )
            }
            Text(
                text = ticket.customerName ?: "Unknown",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
            )
            Text(
                text = ticket.statusName ?: "",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.primary,
                maxLines = 1,
            )
        }
    }
}

// -----------------------------------------------------------------------
// Context-menu items for pin/unpin (used in TicketListScreen DropdownMenu)
// -----------------------------------------------------------------------

/**
 * A [DropdownMenuItem]-like row that toggles the pinned state of a ticket.
 * Insert this inside the existing DropdownMenu in [TicketListRow].
 */
@Composable
fun PinToggleMenuItem(
    isPinned: Boolean,
    onClick: () -> Unit,
) {
    androidx.compose.material3.DropdownMenuItem(
        text = { Text(if (isPinned) "Unpin ticket" else "Pin ticket") },
        onClick = onClick,
        leadingIcon = {
            Icon(
                imageVector = if (isPinned) Icons.Default.Star else Icons.Default.StarBorder,
                contentDescription = null,
            )
        },
    )
}
