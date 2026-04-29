package com.bizarreelectronics.crm.ui.screens.tickets.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.util.SlaCalculator.SlaTier

/**
 * §4.22 L859 — Inline SLA ring chip for ticket list rows.
 *
 * Renders a small circular progress ring centred on a 24dp × 24dp canvas.
 * The sweep angle encodes how much of the SLA budget remains (not consumed),
 * so a full ring = 0 % consumed (healthy), an empty ring = 100 % consumed (breached).
 *
 * ### Colour scheme
 * | Tier  | Consumed | Ring colour                        |
 * |-------|----------|------------------------------------|
 * | Green | < 60 %   | `secondaryContainer` / `secondary` |
 * | Amber | 60–90 %  | `tertiaryContainer` / `tertiary`   |
 * | Red   | > 90 %   | `errorContainer`   / `error`       |
 * | Black | breached | `onSurface` (post-breach)          |
 *
 * ### Reduce Motion
 * When [reduceMotion] is true the sweep angle snaps without animation.
 *
 * @param consumedPct   Percentage of the SLA budget already used (0–100+).
 *                      Values > 100 indicate a breach.
 * @param tier          Computed from [SlaCalculator.tier].
 * @param size          Outer diameter of the ring. Default 24dp.
 * @param strokeWidth   Ring stroke width. Default 3dp.
 * @param reduceMotion  Suppresses the animated sweep when true.
 * @param modifier      Layout modifier.
 */
@Composable
fun SlaRingChip(
    consumedPct: Int,
    tier: SlaTier,
    modifier: Modifier = Modifier,
    size: Dp = 24.dp,
    strokeWidth: Dp = 3.dp,
    reduceMotion: Boolean = false,
) {
    val breached = consumedPct > 100

    // remaining fraction for sweep (inverted: we draw remaining, not consumed)
    val targetFraction = ((100 - consumedPct.coerceIn(0, 100)) / 100f).coerceIn(0f, 1f)

    val animatedFraction by if (reduceMotion) {
        remember(targetFraction) { androidx.compose.runtime.mutableFloatStateOf(targetFraction) }
    } else {
        animateFloatAsState(
            targetValue = targetFraction,
            animationSpec = tween(durationMillis = 500),
            label = "sla_ring",
        )
    }

    val (trackColor, sweepColor) = slaRingColors(tier, breached)

    Canvas(
        modifier = modifier
            .size(size),
    ) {
        val stroke = Stroke(width = strokeWidth.toPx(), cap = StrokeCap.Round)
        val diameter = size.toPx() - strokeWidth.toPx()
        val topLeft = androidx.compose.ui.geometry.Offset(strokeWidth.toPx() / 2, strokeWidth.toPx() / 2)
        val ringSize = androidx.compose.ui.geometry.Size(diameter, diameter)

        // Background track (full circle, faint)
        drawArc(
            color = trackColor,
            startAngle = -90f,
            sweepAngle = 360f,
            useCenter = false,
            style = stroke,
            topLeft = topLeft,
            size = ringSize,
        )

        // Remaining arc (sweeps clockwise from top)
        if (animatedFraction > 0f) {
            drawArc(
                color = sweepColor,
                startAngle = -90f,
                sweepAngle = 360f * animatedFraction,
                useCenter = false,
                style = stroke,
                topLeft = topLeft,
                size = ringSize,
            )
        }
    }
}

/**
 * §4.22 L859 — SLA ring chip with label text centred inside the ring.
 *
 * Renders a ring + a compact label (e.g. "2h", "OD" for overdue) in the centre.
 * Suitable for ticket list rows where both colour and numeric context matter.
 *
 * @param consumedPct   Percentage of SLA budget consumed (0–100+).
 * @param tier          Computed SLA tier.
 * @param centerLabel   Short label displayed at the centre (e.g. "2h", "OD").
 * @param reduceMotion  Suppresses animated sweep.
 * @param modifier      Layout modifier.
 */
@Composable
fun SlaRingChipWithLabel(
    consumedPct: Int,
    tier: SlaTier,
    centerLabel: String,
    modifier: Modifier = Modifier,
    reduceMotion: Boolean = false,
) {
    Box(
        modifier = modifier,
        contentAlignment = Alignment.Center,
    ) {
        SlaRingChip(
            consumedPct = consumedPct,
            tier = tier,
            size = 36.dp,
            strokeWidth = 3.5.dp,
            reduceMotion = reduceMotion,
        )
        Text(
            text = centerLabel,
            style = MaterialTheme.typography.labelSmall,
            modifier = Modifier.padding(2.dp),
        )
    }
}

// ─── Colour helpers ───────────────────────────────────────────────────────────

/**
 * Returns (trackColor, sweepColor) for the SLA ring based on [tier] and whether
 * the ticket has [breached] its SLA deadline.
 *
 * Post-breach: both colors shift to `onSurface` / `surfaceVariant` (dark/grey).
 */
@Composable
private fun slaRingColors(tier: SlaTier, breached: Boolean): Pair<Color, Color> {
    val scheme = MaterialTheme.colorScheme
    if (breached) {
        return scheme.surfaceVariant to scheme.onSurface
    }
    return when (tier) {
        SlaTier.Green -> scheme.secondary.copy(alpha = 0.18f) to scheme.secondary
        SlaTier.Amber -> scheme.tertiary.copy(alpha = 0.18f) to scheme.tertiary
        SlaTier.Red   -> scheme.errorContainer.copy(alpha = 0.5f) to scheme.error
    }
}
