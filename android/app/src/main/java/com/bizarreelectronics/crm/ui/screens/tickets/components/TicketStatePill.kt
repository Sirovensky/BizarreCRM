package com.bizarreelectronics.crm.ui.screens.tickets.components

import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.graphics.toColorInt

/**
 * plan:L794 — TicketStatePill
 *
 * Rounded pill chip that renders a ticket status name with its server-supplied
 * hex color as the container background. Used on:
 *   - TicketListScreen row trailing slot (replaces hard-coded status text)
 *   - TicketDetailScreen header (replaces plain Text status display)
 *
 * @param statusName  Display name of the status (e.g. "In Repair").
 * @param colorHex    Server-supplied hex color string (e.g. "#4CAF50"). Null/blank
 *                    falls back to [MaterialTheme.colorScheme.secondaryContainer].
 * @param modifier    Optional modifier forwarded to the [Surface].
 */
@Composable
fun TicketStatePill(
    statusName: String,
    colorHex: String?,
    modifier: Modifier = Modifier,
) {
    val containerColor = remember(colorHex) {
        if (!colorHex.isNullOrBlank()) {
            runCatching {
                val hex = if (colorHex.startsWith("#")) colorHex else "#$colorHex"
                Color(hex.toColorInt())
            }.getOrNull()
        } else {
            null
        }
    }

    // Determine whether the supplied color is "dark" so we can pick a legible text color.
    val onContainerColor = remember(containerColor) {
        if (containerColor != null) {
            // Relative luminance (simplified) — W3C formula
            val r = containerColor.red
            val g = containerColor.green
            val b = containerColor.blue
            val luminance = 0.2126f * r + 0.7152f * g + 0.0722f * b
            if (luminance > 0.5f) Color(0xFF1A1A1A) else Color.White
        } else {
            null
        }
    }

    Surface(
        shape = RoundedCornerShape(50),
        color = containerColor ?: MaterialTheme.colorScheme.secondaryContainer,
        contentColor = onContainerColor ?: MaterialTheme.colorScheme.onSecondaryContainer,
        // §26.1 — announce the status name as "Ticket status: <name>" so TalkBack
        // users hear context even when focus lands directly on the chip rather than
        // the parent list row. When the pill is inside a BrandListItem (mergeDescendants=true)
        // the chip text is still read as part of the merged announcement.
        modifier = modifier.clearAndSetSemantics {
            contentDescription = "Ticket status: $statusName"
        },
    ) {
        Text(
            text = statusName,
            style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.SemiBold),
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
            maxLines = 1,
        )
    }
}
