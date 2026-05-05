package com.bizarreelectronics.crm.ui.screens.invoices.components

/**
 * Donut-arc chart showing invoice counts grouped by status (ActionPlan §7.1 line 1715).
 *
 * Pure-Compose Canvas implementation — no Vico or MPAndroidChart dependency.
 * Pattern follows [com.bizarreelectronics.crm.ui.screens.expenses.ExpenseCategoryPieChart].
 *
 * Features:
 *  - Animated sweep (Animatable 0→1, 600 ms tween); skipped when reduceMotion=true.
 *  - Center label: total invoice count.
 *  - Tappable legend rows: tap selects a slice; re-tap deselects.
 *  - Tooltip surface (secondaryContainer) for selected slice showing count + dollar total.
 *  - Inactive slices dimmed to alpha 0.35 while one is selected.
 *  - TalkBack: contentDescription enumerates all slices.
 *  - Empty state: "No invoice data" placeholder card.
 *
 * Usage (tablet/ChromeOS branch in InvoiceStatsHeader):
 * ```
 * val slices = remember(invoices) { buildInvoiceStatusSlices(invoices) }
 * InvoiceStatusPieChart(slices = slices, reduceMotion = false)
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
import com.bizarreelectronics.crm.data.local.db.entities.InvoiceEntity
import com.bizarreelectronics.crm.ui.theme.ErrorRed
import com.bizarreelectronics.crm.ui.theme.InfoBlue
import com.bizarreelectronics.crm.ui.theme.SuccessGreen
import com.bizarreelectronics.crm.ui.theme.WarningAmber
import com.bizarreelectronics.crm.util.formatAsMoney

// ─── Data ─────────────────────────────────────────────────────────────────────

/**
 * One slice of the invoice status donut chart.
 *
 * @param label      Human-readable status label (e.g. "Paid", "Unpaid").
 * @param count      Number of invoices with this status.
 * @param totalCents Sum of [InvoiceEntity.total] for invoices in this status, in cents.
 * @param color      Resolved [Color] for this slice.
 */
data class InvoiceStatusSlice(
    val label: String,
    val count: Int,
    val totalCents: Long,
    val color: Color,
)

/** Maps a normalized status string to a brand-safe color. */
private fun colorForStatus(status: String): Color = when (status.lowercase()) {
    "paid"     -> SuccessGreen
    "unpaid"   -> WarningAmber
    "partial"  -> InfoBlue
    "overdue"  -> ErrorRed
    "void"     -> Color(0xFF9E9E9E)
    else       -> Color(0xFFBDBDBD)
}

/**
 * Builds [InvoiceStatusSlice] list from a list of [InvoiceEntity] rows.
 * Groups by [InvoiceEntity.status], sorts by count descending.
 * Memoize at call site: `remember(invoices) { buildInvoiceStatusSlices(invoices) }`.
 */
fun buildInvoiceStatusSlices(invoices: List<InvoiceEntity>): List<InvoiceStatusSlice> {
    return invoices
        .groupBy { it.status }
        .map { (status, group) ->
            InvoiceStatusSlice(
                label      = status.replaceFirstChar { it.uppercaseChar() },
                count      = group.size,
                totalCents = group.sumOf { it.total },
                color      = colorForStatus(status),
            )
        }
        .sortedByDescending { it.count }
}

// ─── Composable ───────────────────────────────────────────────────────────────

/**
 * Donut chart + legend for invoice status distribution.
 *
 * @param slices       Pre-grouped slice data from [buildInvoiceStatusSlices].
 * @param modifier     Applied to the root [Column].
 * @param reduceMotion When true the sweep animation runs at duration=0.
 */
@Composable
fun InvoiceStatusPieChart(
    slices: List<InvoiceStatusSlice>,
    modifier: Modifier = Modifier,
    reduceMotion: Boolean = false,
) {
    if (slices.isEmpty()) {
        EmptyInvoiceChartState(modifier = modifier)
        return
    }

    val totalCount = slices.sumOf { it.count }

    // Accessibility: enumerate every slice
    val a11yDesc = buildString {
        append("Invoice status breakdown: ")
        slices.forEach { s ->
            val pct = if (totalCount > 0) s.count * 100 / totalCount else 0
            append("${s.label} $pct% (${s.count}), ")
        }
        append("total $totalCount invoices")
    }.trimEnd(',', ' ')

    // Animated sweep 0 → 1
    val animProgress = remember { Animatable(0f) }
    LaunchedEffect(slices) {
        animProgress.snapTo(0f)
        animProgress.animateTo(
            targetValue = 1f,
            animationSpec = if (reduceMotion) tween(durationMillis = 0)
                            else tween(durationMillis = 600),
        )
    }
    val progress by animProgress.asState()

    // Selected-slice state; reset when slice list changes
    var selectedIndex by remember(slices) { mutableStateOf<Int?>(null) }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .semantics { contentDescription = a11yDesc },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // ── Donut arc + center label ───────────────────────────────────────────
        Box(contentAlignment = Alignment.Center) {
            Canvas(modifier = Modifier.size(160.dp)) {
                val strokeWidth = size.minDimension * 0.22f
                val diameter   = size.minDimension - strokeWidth
                val topLeft    = Offset(
                    x = (size.width  - diameter) / 2f,
                    y = (size.height - diameter) / 2f,
                )
                val arcSize = Size(diameter, diameter)

                var startAngle = -90f
                slices.forEachIndexed { idx, slice ->
                    if (totalCount <= 0) return@forEachIndexed
                    val fullSweep = slice.count.toFloat() / totalCount * 360f
                    val sweep     = fullSweep * progress
                    drawArc(
                        color = if (selectedIndex == null || selectedIndex == idx) {
                            slice.color
                        } else {
                            slice.color.copy(alpha = 0.35f)
                        },
                        startAngle = startAngle,
                        sweepAngle = sweep,
                        useCenter  = false,
                        topLeft    = topLeft,
                        size       = arcSize,
                        style      = Stroke(width = strokeWidth),
                    )
                    startAngle += fullSweep  // advance by full, not animated, to keep gaps correct
                }
            }

            // Center: total count
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    text = totalCount.toString(),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Text(
                    text = "invoices",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        // ── Tooltip for selected slice ─────────────────────────────────────────
        val selectedSlice = selectedIndex?.let { slices.getOrNull(it) }
        if (selectedSlice != null) {
            Surface(
                shape = MaterialTheme.shapes.small,
                color = MaterialTheme.colorScheme.secondaryContainer,
                tonalElevation = 4.dp,
            ) {
                Text(
                    text = "${selectedSlice.label}: ${selectedSlice.count} invoices" +
                           " · ${selectedSlice.totalCents.formatAsMoney()}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSecondaryContainer,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                )
            }
        }

        // ── Legend ────────────────────────────────────────────────────────────
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 4.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            slices.forEachIndexed { idx, slice ->
                val pct       = if (totalCount > 0) slice.count.toFloat() / totalCount * 100f else 0f
                val isSelected = selectedIndex == idx
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { selectedIndex = if (isSelected) null else idx }
                        .padding(vertical = 2.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Canvas(modifier = Modifier.size(12.dp)) {
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
                        text = slice.count.toString(),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    Text(
                        text = String.format("%.0f%%", pct),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

@Composable
private fun EmptyInvoiceChartState(modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.medium,
        color = MaterialTheme.colorScheme.surfaceVariant,
        tonalElevation = 2.dp,
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(100.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = "No invoice data",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
    }
}
