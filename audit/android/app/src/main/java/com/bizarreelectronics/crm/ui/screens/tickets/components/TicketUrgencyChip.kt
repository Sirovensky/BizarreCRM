package com.bizarreelectronics.crm.ui.screens.tickets.components

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.local.db.entities.TicketEntity

/**
 * Urgency level for a ticket.
 *
 * TODO(plan:L637): TicketEntity currently has no dedicated `urgency` or `priority` column.
 * Urgency is derived from heuristics in [ticketUrgencyFor]. Once the server adds a
 * `priority` or `urgency` field (tracked as CROSS-PLATFORM), replace the derivation
 * logic with a direct field read and add a Room column to TicketEntity.
 */
enum class TicketUrgency(val label: String) {
    Critical("Critical"),
    High("High"),
    Medium("Medium"),
    Normal("Normal"),
    Low("Low"),
}

/**
 * Derives [TicketUrgency] from available ticket fields.
 *
 * Heuristic rules (in priority order):
 *  1. Closed tickets → [TicketUrgency.Low] (no action needed).
 *  2. Status name contains "urgent" or "critical" → [TicketUrgency.Critical].
 *  3. Status name contains "waiting" or "parts" → [TicketUrgency.High].
 *  4. Status name contains "in progress" or "repair" → [TicketUrgency.Medium].
 *  5. Anything else open → [TicketUrgency.Normal].
 */
fun ticketUrgencyFor(ticket: TicketEntity): TicketUrgency {
    if (ticket.statusIsClosed) return TicketUrgency.Low
    val name = ticket.statusName?.trim()?.lowercase().orEmpty()
    return when {
        name.contains("urgent") || name.contains("critical") -> TicketUrgency.Critical
        name.contains("waiting") || name.contains("parts") -> TicketUrgency.High
        name.contains("in progress") || name.contains("repair") -> TicketUrgency.Medium
        else -> TicketUrgency.Normal
    }
}

/**
 * Compact urgency chip displayed inline in a ticket list row.
 *
 * Color mapping (Material 3 color roles):
 *   - Critical → errorContainer bg + onErrorContainer text
 *   - High     → tertiary tint bg + tertiary text (orange-ish on brand palette)
 *   - Medium   → secondary tint bg + secondary text (teal — informational)
 *   - Normal   → surfaceVariant bg + onSurfaceVariant text (neutral)
 *   - Low      → faded surfaceVariant (subtle, closed tickets)
 */
@Composable
fun TicketUrgencyChip(urgency: TicketUrgency, modifier: Modifier = Modifier) {
    val (containerColor, textColor) = urgencyColors(urgency)
    Surface(
        modifier = modifier,
        shape = MaterialTheme.shapes.small,
        color = containerColor,
    ) {
        Text(
            text = urgency.label,
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
            style = MaterialTheme.typography.labelSmall,
            color = textColor,
            fontWeight = FontWeight.Medium,
        )
    }
}

@Composable
private fun urgencyColors(urgency: TicketUrgency): Pair<Color, Color> {
    val scheme = MaterialTheme.colorScheme
    return when (urgency) {
        TicketUrgency.Critical -> scheme.errorContainer to scheme.onErrorContainer
        TicketUrgency.High     -> scheme.tertiary.copy(alpha = 0.18f) to scheme.tertiary
        TicketUrgency.Medium   -> scheme.secondary.copy(alpha = 0.14f) to scheme.secondary
        TicketUrgency.Normal   -> scheme.surfaceVariant to scheme.onSurfaceVariant
        TicketUrgency.Low      -> scheme.surfaceVariant.copy(alpha = 0.6f) to scheme.onSurfaceVariant.copy(alpha = 0.6f)
    }
}
