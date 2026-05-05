package com.bizarreelectronics.crm.ui.screens.expenses

/**
 * Donut-arc chart showing expense totals grouped by category (ActionPlan §11).
 *
 * Pure-Compose Canvas implementation — no Vico dependency needed for this
 * simple donut. Pattern mirrors [com.bizarreelectronics.crm.ui.screens.reports.CategoryBreakdownPieChart]
 * from Wave 9F but adapted to show cent-denominated amounts in the legend
 * rather than percentages, and includes tappable-slice tooltip behaviour.
 *
 * Respects ReduceMotion: sweep animation is suppressed when the OS or the
 * in-app toggle requests reduced motion.
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
import com.bizarreelectronics.crm.util.formatAsMoney

// ─── Public data class ────────────────────────────────────────────────────────

/**
 * One slice of the expense donut chart.
 *
 * @param category  Human-readable category label (e.g. "Rent", "Parts & Supplies").
 * @param totalCents  Total expense amount for the category in cents (Long).
 * @param color  Resolved [Color] for this slice. Caller assigns cycling palette.
 */
data class ExpenseSlice(
    val category: String,
    val totalCents: Long,
    val color: Color,
)

// ─── Main composable ──────────────────────────────────────────────────────────

/**
 * Donut chart + legend showing expense breakdown by category.
 *
 * - Outer radius ≈ 80 dp, inner hole ≈ 50 dp (via stroke width).
 * - Center text: currency-formatted total across all slices.
 * - Legend: stacked rows with colored dot, category name, and amount.
 * - Empty state: "No expenses for this period" placeholder.
 * - TalkBack: contentDescription enumerates each slice with amount.
 * - ReduceMotion: when [reduceMotion] is true the sweep animation is skipped.
 * - Tappable slices: tapping a legend row or the chart selects a slice and
 *   shows a small tooltip with the category total.
 *
 * @param slices       Pre-grouped slice data. Caller is responsible for grouping
 *                     [ExpenseEntity] by category and assigning cycling colors.
 * @param modifier     Passed to the root [Column].
 * @param reduceMotion When true, arc sweep animation is suppressed.
 */
@Composable
fun ExpenseCategoryPieChart(
    slices: List<ExpenseSlice>,
    modifier: Modifier = Modifier,
    reduceMotion: Boolean = false,
) {
    if (slices.isEmpty()) {
        EmptyExpenseChartState(modifier = modifier)
        return
    }

    val totalCents = slices.sumOf { it.totalCents }
    val totalFormatted = totalCents.formatAsMoney()

    // Accessibility description
    val a11yDesc = buildString {
        append("Expenses by category: ")
        slices.forEach { s ->
            append("${s.category} ${s.totalCents.formatAsMoney()}, ")
        }
        append("total $totalFormatted")
    }.trimEnd(',', ' ')

    // Animated sweep progress: 0.0 → 1.0
    val animProgress = remember { Animatable(0f) }
    LaunchedEffect(slices) {
        animProgress.snapTo(0f)
        animProgress.animateTo(
            targetValue = 1f,
            animationSpec = if (reduceMotion) tween(durationMillis = 0) else tween(durationMillis = 600),
        )
    }
    val progress by animProgress.asState()

    // Selected slice state for tooltip
    var selectedIndex by remember(slices) { mutableStateOf<Int?>(null) }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .semantics { contentDescription = a11yDesc },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Donut arc with center total label
        Box(contentAlignment = Alignment.Center) {
            Canvas(modifier = Modifier.size(180.dp)) {
                val strokeWidth = size.minDimension * 0.22f   // ≈ 80 outer - 50 inner = 30 dp stroke
                val diameter = size.minDimension - strokeWidth
                val topLeft = Offset(
                    x = (size.width - diameter) / 2f,
                    y = (size.height - diameter) / 2f,
                )
                val arcSize = Size(diameter, diameter)

                var startAngle = -90f
                slices.forEachIndexed { idx, slice ->
                    if (totalCents <= 0L) return@forEachIndexed
                    val fullSweep = (slice.totalCents.toDouble() / totalCents * 360.0).toFloat()
                    val sweep = fullSweep * progress
                    drawArc(
                        color = if (selectedIndex == null || selectedIndex == idx) {
                            slice.color
                        } else {
                            slice.color.copy(alpha = 0.35f)
                        },
                        startAngle = startAngle,
                        sweepAngle = sweep,
                        useCenter = false,
                        topLeft = topLeft,
                        size = arcSize,
                        style = Stroke(width = strokeWidth),
                    )
                    startAngle += fullSweep   // advance by full angle, not animated
                }
            }

            // Center label — total amount
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    text = "Total",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    text = totalFormatted,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurface,
                    textAlign = TextAlign.Center,
                )
            }
        }

        // Tooltip for selected slice
        val selectedSlice = selectedIndex?.let { slices.getOrNull(it) }
        if (selectedSlice != null) {
            Surface(
                shape = MaterialTheme.shapes.small,
                color = MaterialTheme.colorScheme.secondaryContainer,
                tonalElevation = 4.dp,
            ) {
                Text(
                    text = "${selectedSlice.category}: ${selectedSlice.totalCents.formatAsMoney()}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSecondaryContainer,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                )
            }
        }

        // Legend rows
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 4.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            slices.forEachIndexed { idx, slice ->
                val pct = if (totalCents > 0L) slice.totalCents.toDouble() / totalCents * 100.0 else 0.0
                val isSelected = selectedIndex == idx
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable {
                            selectedIndex = if (isSelected) null else idx
                        }
                        .padding(vertical = 2.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Canvas(modifier = Modifier.size(12.dp)) {
                        drawCircle(color = slice.color)
                    }
                    Text(
                        text = slice.category,
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.weight(1f),
                        color = if (isSelected) {
                            MaterialTheme.colorScheme.primary
                        } else {
                            MaterialTheme.colorScheme.onSurface
                        },
                        fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
                    )
                    Text(
                        text = slice.totalCents.formatAsMoney(),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    Text(
                        text = String.format("%.1f%%", pct),
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
private fun EmptyExpenseChartState(modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.medium,
        color = MaterialTheme.colorScheme.surfaceVariant,
        tonalElevation = 2.dp,
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(120.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = "No expenses for this period",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
    }
}
