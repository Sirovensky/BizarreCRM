package com.bizarreelectronics.crm.ui.screens.invoices.components

/**
 * §7.1 line 1407 — Invoice status donut-arc chart for tablet / ChromeOS surfaces.
 *
 * Draws a two-ring donut chart using pure Compose [Canvas] (no third-party chart
 * library required). Outer ring = status breakdown (Unpaid / Overdue / Paid);
 * inner ring = relative invoice counts for the same three buckets when count data
 * is available.
 *
 * Payment-method pie is deferred until the server exposes
 * `GET /invoices/stats` with `by_payment_method` breakdown.
 *
 * Design contract:
 * - Slice colors: Unpaid = [MaterialTheme.colorScheme.error],
 *   Overdue = [WarningAmber], Paid = [SuccessGreen].
 * - Center label shows grand total formatted as money.
 * - Legend row per slice: colored dot + label + formatted amount + percentage.
 * - Tapping a legend row highlights the corresponding arc and shows an amount tooltip.
 * - ReduceMotion: sweep animation is suppressed when [reduceMotion] is true.
 * - TalkBack: outer [Canvas] carries a full `contentDescription` listing each slice.
 * - Empty / zero-data: replaced with a neutral placeholder surface.
 *
 * Usage:
 * ```kotlin
 * if (stats != null && isMediumOrExpandedWidth()) {
 *     InvoiceStatusPieChart(stats = stats, reduceMotion = reduceMotion)
 * }
 * ```
 */

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.dto.InvoiceStatsData
import com.bizarreelectronics.crm.ui.theme.SuccessGreen
import com.bizarreelectronics.crm.ui.theme.WarningAmber
import com.bizarreelectronics.crm.util.formatAsMoney

// ─── Internal slice model ────────────────────────────────────────────────────

private data class StatusSlice(
    val label: String,
    val valueDollars: Double,
    val color: Color,
)

// ─── Public composable ───────────────────────────────────────────────────────

/**
 * Donut arc chart visualising the invoice status breakdown from [InvoiceStatsData].
 *
 * @param stats        Pre-loaded stats from `GET /invoices/stats`.
 * @param modifier     Applied to the root [Column].
 * @param reduceMotion When true, the sweep-in animation is replaced with an instant snap.
 */
@Composable
fun InvoiceStatusPieChart(
    stats: InvoiceStatsData,
    modifier: Modifier = Modifier,
    reduceMotion: Boolean = false,
) {
    val slices = remember(stats) {
        buildList {
            if (stats.totalUnpaid > 0.0)
                add(StatusSlice("Unpaid", stats.totalUnpaid, Color(0xFFEF5350)))
            if (stats.totalOverdue > 0.0)
                add(StatusSlice("Overdue", stats.totalOverdue, WarningAmber))
            val paid = stats.totalPaid - stats.totalOverdue
            if (paid > 0.0)
                add(StatusSlice("Paid", paid, SuccessGreen))
        }
    }

    if (slices.isEmpty() || slices.all { it.valueDollars <= 0.0 }) {
        EmptyInvoiceChartState(modifier = modifier)
        return
    }

    val grandTotal = slices.sumOf { it.valueDollars }
    val grandTotalLabel = (grandTotal * 100).toLong().formatAsMoney()

    // Accessibility description — read by TalkBack in lieu of visual chart.
    val a11yDesc = buildString {
        append("Invoice status breakdown: ")
        slices.forEach { s ->
            val pct = if (grandTotal > 0.0) s.valueDollars / grandTotal * 100.0 else 0.0
            val amtFormatted = "%.0f".format(s.valueDollars)
            val pctFormatted = "%.1f".format(pct)
            append("${s.label} ${pctFormatted}% ($${amtFormatted}), ")
        }
        append("total $grandTotalLabel")
    }.trimEnd(',', ' ')

    // Animated sweep: 0 → 1
    val sweepProg = remember { Animatable(0f) }
    LaunchedEffect(slices) {
        sweepProg.snapTo(0f)
        sweepProg.animateTo(
            targetValue = 1f,
            animationSpec = if (reduceMotion) tween(durationMillis = 0) else tween(durationMillis = 650),
        )
    }
    val progress by sweepProg.asState()

    var selectedIdx by remember(slices) { mutableStateOf<Int?>(null) }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // ── Donut + centre label ─────────────────────────────────────────────
        Box(contentAlignment = Alignment.Center) {
            Canvas(
                modifier = Modifier
                    .size(176.dp)
                    .semantics { contentDescription = a11yDesc },
            ) {
                val strokeWidth = size.minDimension * 0.21f
                val diameter = size.minDimension - strokeWidth
                val topLeft = Offset(
                    x = (size.width - diameter) / 2f,
                    y = (size.height - diameter) / 2f,
                )
                val arcSize = Size(diameter, diameter)

                var startAngle = -90f
                slices.forEachIndexed { idx, slice ->
                    val fullSweep = (slice.valueDollars / grandTotal * 360.0).toFloat()
                    val animatedSweep = fullSweep * progress
                    val alpha = when {
                        selectedIdx == null -> 1f
                        selectedIdx == idx  -> 1f
                        else               -> 0.30f
                    }
                    drawArc(
                        color = slice.color.copy(alpha = alpha),
                        startAngle = startAngle,
                        sweepAngle = animatedSweep,
                        useCenter = false,
                        topLeft = topLeft,
                        size = arcSize,
                        style = Stroke(width = strokeWidth),
                    )
                    startAngle += fullSweep
                }

                // Track-ring background (subtle grey)
                drawArc(
                    color = Color.Gray.copy(alpha = 0.08f),
                    startAngle = 0f,
                    sweepAngle = 360f,
                    useCenter = false,
                    topLeft = topLeft,
                    size = arcSize,
                    style = Stroke(width = strokeWidth * 0.12f),
                )
            }

            // Centre total
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    text = "Total",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    text = grandTotalLabel,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurface,
                    textAlign = TextAlign.Center,
                )
            }
        }

        // ── Tooltip for selected slice ────────────────────────────────────────
        val selSlice = selectedIdx?.let { slices.getOrNull(it) }
        if (selSlice != null) {
            Surface(
                shape = MaterialTheme.shapes.small,
                color = MaterialTheme.colorScheme.secondaryContainer,
                tonalElevation = 4.dp,
            ) {
                val selPct = if (grandTotal > 0.0) selSlice.valueDollars / grandTotal * 100.0 else 0.0
                Text(
                    text = "${selSlice.label}: $${"%.0f".format(selSlice.valueDollars)} (${"%.1f".format(selPct)}%)",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSecondaryContainer,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                )
            }
        }

        // ── Legend ────────────────────────────────────────────────────────────
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            slices.forEachIndexed { idx, slice ->
                val pct = if (grandTotal > 0.0) slice.valueDollars / grandTotal * 100.0 else 0.0
                val isSelected = selectedIdx == idx
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { selectedIdx = if (isSelected) null else idx }
                        .padding(vertical = 3.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Canvas(modifier = Modifier.size(11.dp)) {
                        drawCircle(color = slice.color)
                    }
                    Text(
                        text = slice.label,
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.weight(1f),
                        color = if (isSelected) MaterialTheme.colorScheme.primary
                        else MaterialTheme.colorScheme.onSurface,
                        fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
                    )
                    Text(
                        text = "$${"%.0f".format(slice.valueDollars)}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    Text(
                        text = "${"%.1f".format(pct)}%",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

// ─── Empty / zero state ──────────────────────────────────────────────────────

@Composable
private fun EmptyInvoiceChartState(modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        shape = MaterialTheme.shapes.medium,
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        tonalElevation = 0.dp,
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(100.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = "No invoice data available",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
    }
}
