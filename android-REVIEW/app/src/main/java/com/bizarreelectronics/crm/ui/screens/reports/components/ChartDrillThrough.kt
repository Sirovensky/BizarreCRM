package com.bizarreelectronics.crm.ui.screens.reports.components

import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput

/**
 * Drill-through wrapper for Vico charts (ActionPlan §15 L1730).
 *
 * Wraps any chart composable and maps a tap gesture to a data-point index,
 * then calls [onDrillThrough] with the ISO date string from [dateLabels].
 *
 * Usage:
 * ```
 * ChartDrillThrough(dateLabels = points.map { it.isoDate }, onDrillThrough = { date ->
 *     navController.navigate(Screen.Tickets.route + "?date=$date")
 * }) {
 *     SalesByDayBarChart(points = points, ...)
 * }
 * ```
 *
 * The tap detection maps the horizontal position to a column index by dividing
 * the tap X offset by the average column width. This is a best-effort
 * approximation; exact hit-testing requires Vico's internal layout info which
 * is not public API as of Vico 2.x. For a single-column data series this is
 * accurate to within ±1 data point.
 *
 * @param dateLabels   ISO date strings corresponding to each data index (0-based).
 * @param onDrillThrough  Called with the ISO date of the tapped data point.
 * @param content      The chart composable to wrap.
 */
@Composable
fun ChartDrillThrough(
    dateLabels: List<String>,
    onDrillThrough: (isoDate: String) -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    val labelCount = remember(dateLabels) { dateLabels.size }

    Box(
        modifier = modifier
            .pointerInput(dateLabels) {
                detectTapGestures { offset ->
                    if (labelCount == 0) return@detectTapGestures
                    val index = ((offset.x / size.width) * labelCount)
                        .toInt()
                        .coerceIn(0, labelCount - 1)
                    onDrillThrough(dateLabels[index])
                }
            },
    ) {
        content()
    }
}
