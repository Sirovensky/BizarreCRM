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
import com.bizarreelectronics.crm.util.SlaCalculator.SlaTier

/**
 * §4.19 L825-L835 — Compact SLA status chip for ticket list rows.
 *
 * Color coding matches [SlaTier]:
 * - [SlaTier.Green] → secondary tint (informational / on-track)
 * - [SlaTier.Amber] → tertiary tint (warning — approaching deadline)
 * - [SlaTier.Red]   → errorContainer (breached)
 *
 * Label shows remaining time as a human-readable string (e.g. "2h 15m" or "Overdue").
 *
 * ReduceMotion: no animation is used; this composable is always compliant.
 *
 * @param tier          Computed from [SlaCalculator.tier].
 * @param label         Human-readable remaining time string produced by the caller.
 * @param modifier      Layout modifier.
 */
@Composable
fun SlaChip(
    tier: SlaTier,
    label: String,
    modifier: Modifier = Modifier,
) {
    val (container, text) = slaChipColors(tier)
    Surface(
        modifier = modifier,
        shape = MaterialTheme.shapes.small,
        color = container,
    ) {
        Text(
            text = label,
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
            style = MaterialTheme.typography.labelSmall,
            color = text,
            fontWeight = FontWeight.Medium,
        )
    }
}

@Composable
private fun slaChipColors(tier: SlaTier): Pair<Color, Color> {
    val scheme = MaterialTheme.colorScheme
    return when (tier) {
        SlaTier.Green -> scheme.secondary.copy(alpha = 0.14f) to scheme.secondary
        SlaTier.Amber -> scheme.tertiary.copy(alpha = 0.18f) to scheme.tertiary
        SlaTier.Red   -> scheme.errorContainer to scheme.onErrorContainer
    }
}

/**
 * Format remaining milliseconds as a human-readable string for [SlaChip].
 *
 * - Negative or zero → "Overdue"
 * - < 1 hour         → "Xm"
 * - >= 1 hour        → "Xh Ym"
 */
fun formatSlaRemaining(remainingMs: Long): String {
    if (remainingMs <= 0L) return "Overdue"
    val totalMinutes = (remainingMs / 60_000L).toInt()
    val hours   = totalMinutes / 60
    val minutes = totalMinutes % 60
    return if (hours > 0) "${hours}h ${minutes}m" else "${minutes}m"
}
