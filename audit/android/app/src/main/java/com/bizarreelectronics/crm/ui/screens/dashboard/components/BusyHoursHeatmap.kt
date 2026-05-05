package com.bizarreelectronics.crm.ui.screens.dashboard.components

/**
 * §3.2 L501 — Busy Hours heatmap.
 *
 * 7 × 24 grid (day-of-week × hour-of-day) showing ticket volume intensity.
 * Cell colour is interpolated between surfaceVariant (zero) and primary (max).
 *
 * Data contract:
 * - [data]: 7-element array, each row is 24 integers (hour counts).
 *   Index 0 = Monday, index 6 = Sunday.
 *   Empty / all-zero = stub mode ("No heatmap data yet").
 *
 * Layout: horizontal scroll for the 24-column grid so it fits on phones.
 * Legend below the grid explains the colour scale.
 */

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private val DAY_LABELS = listOf("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")

@Composable
fun BusyHoursHeatmap(
    /**
     * 7×24 ticket-volume grid. data[dayIndex][hourIndex].
     * Provide an empty array to show the stub state.
     */
    data: Array<IntArray>,
    modifier: Modifier = Modifier,
) {
    val isEmpty = data.isEmpty() || data.all { row -> row.all { it == 0 } }
    val maxValue = if (isEmpty) 1 else data.maxOf { row -> row.maxOrNull() ?: 0 }.coerceAtLeast(1)

    val a11yDesc = if (isEmpty) {
        "Busy Hours heatmap: no data yet."
    } else {
        "Busy Hours heatmap: 7-day × 24-hour ticket volume grid."
    }

    Card(
        modifier = modifier
            .fillMaxWidth()
            .border(
                width = 1.dp,
                color = MaterialTheme.colorScheme.outline,
                shape = MaterialTheme.shapes.medium,
            )
            .semantics { contentDescription = a11yDesc },
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = "Busy Hours",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Spacer(modifier = Modifier.height(12.dp))

            if (isEmpty) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(100.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = "No heatmap data yet",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                    )
                }
            } else {
                HeatmapGrid(
                    data = data,
                    maxValue = maxValue,
                )
                Spacer(modifier = Modifier.height(8.dp))
                HeatmapLegend()
            }
        }
    }
}

@Composable
private fun HeatmapGrid(
    data: Array<IntArray>,
    maxValue: Int,
) {
    val emptyColor = MaterialTheme.colorScheme.surfaceVariant
    val fullColor = MaterialTheme.colorScheme.primary
    val cellSize = 14.dp
    val gap = 2.dp

    // Hour labels row
    Row(modifier = Modifier.horizontalScroll(rememberScrollState())) {
        Column {
            // Hour header
            Row(modifier = Modifier.padding(start = 28.dp)) {
                (0 until 24).forEach { hour ->
                    val label = if (hour % 6 == 0) "${hour}h" else ""
                    Box(
                        modifier = Modifier.width(cellSize + gap),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            text = label,
                            style = MaterialTheme.typography.labelSmall.copy(fontSize = 8.sp),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(2.dp))

            // Day rows
            val rows = if (data.size == 7) data.toList()
            else List(7) { idx -> data.getOrNull(idx) ?: IntArray(24) }

            rows.forEachIndexed { dayIdx, hourCounts ->
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.padding(bottom = gap),
                ) {
                    // Day label
                    Text(
                        text = DAY_LABELS.getOrElse(dayIdx) { "" },
                        style = MaterialTheme.typography.labelSmall.copy(fontSize = 9.sp),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.width(28.dp),
                    )
                    // Cells
                    (0 until 24).forEach { hour ->
                        val count = hourCounts.getOrElse(hour) { 0 }
                        val fraction = count.toFloat() / maxValue.toFloat()
                        val cellColor = lerp(emptyColor, fullColor, fraction)
                        Box(
                            modifier = Modifier
                                .size(cellSize)
                                .background(
                                    color = cellColor,
                                    shape = MaterialTheme.shapes.extraSmall,
                                ),
                        )
                        Spacer(modifier = Modifier.width(gap))
                    }
                }
            }
        }
    }
}

@Composable
private fun HeatmapLegend() {
    val emptyColor = MaterialTheme.colorScheme.surfaceVariant
    val fullColor = MaterialTheme.colorScheme.primary
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(
            text = "Low",
            style = MaterialTheme.typography.labelSmall.copy(fontSize = 9.sp),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        // Gradient swatch using 5 steps
        (0..4).forEach { step ->
            val fraction = step / 4f
            Box(
                modifier = Modifier
                    .size(12.dp)
                    .background(
                        color = lerp(emptyColor, fullColor, fraction),
                        shape = MaterialTheme.shapes.extraSmall,
                    ),
            )
        }
        Text(
            text = "High",
            style = MaterialTheme.typography.labelSmall.copy(fontSize = 9.sp),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
