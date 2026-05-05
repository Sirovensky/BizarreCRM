package com.bizarreelectronics.crm.ui.screens.reports

/**
 * Vico chart composables for the Reports screen (ActionPlan §15).
 *
 * Three chart surfaces, all driven by immutable data classes supplied by
 * ReportsViewModel:
 *   - [SalesByDayBarChart]       — ColumnCartesianLayer (bar chart), one column per period
 *   - [RevenueOverTimeLineChart] — LineCartesianLayer, daily / period revenue trend
 *   - [CategoryBreakdownPieChart] — custom Canvas donut chart (Vico 2.x has no built-in
 *     pie layer; a lightweight Canvas implementation avoids pulling in a second library)
 *
 * All charts:
 *   - Respect ReduceMotion: animation is suppressed when the OS or app pref requests it.
 *   - Show "No data for this period" when the data list is empty (no crash).
 *   - Provide TalkBack contentDescription summarising data shape and key values.
 *   - Use MaterialTheme.colorScheme tokens for all series colours.
 */

import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.util.ReduceMotion
import com.patrykandpatrick.vico.compose.cartesian.CartesianChartHost
import com.patrykandpatrick.vico.compose.cartesian.axis.rememberBottom
import com.patrykandpatrick.vico.compose.cartesian.axis.rememberStart
import com.patrykandpatrick.vico.core.cartesian.axis.HorizontalAxis
import com.patrykandpatrick.vico.core.cartesian.axis.VerticalAxis
// rememberStart / rememberBottom are extension fns on the axis companions, imported above.
import com.patrykandpatrick.vico.compose.cartesian.layer.rememberColumnCartesianLayer
import com.patrykandpatrick.vico.compose.cartesian.layer.rememberLine
import com.patrykandpatrick.vico.compose.cartesian.layer.rememberLineCartesianLayer
import com.patrykandpatrick.vico.compose.cartesian.rememberCartesianChart
import com.patrykandpatrick.vico.compose.cartesian.rememberVicoScrollState
import com.patrykandpatrick.vico.compose.cartesian.rememberVicoZoomState
import com.patrykandpatrick.vico.compose.common.fill
import com.patrykandpatrick.vico.core.cartesian.data.CartesianChartModelProducer
import com.patrykandpatrick.vico.core.cartesian.data.CartesianValueFormatter
import com.patrykandpatrick.vico.core.cartesian.data.columnSeries
import com.patrykandpatrick.vico.core.cartesian.data.lineSeries
import com.patrykandpatrick.vico.core.cartesian.layer.ColumnCartesianLayer
import com.patrykandpatrick.vico.core.cartesian.layer.LineCartesianLayer
import com.patrykandpatrick.vico.core.common.component.LineComponent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.text.NumberFormat
import java.util.Locale

// ─── Public data classes ──────────────────────────────────────────────────────

/** One bar in the sales-by-day chart. totalCents is in cents to avoid float rounding. */
data class SalesByDayPoint(
    /** ISO-8601 date, e.g. "2026-04-18". Used only as an axis label. */
    val isoDate: String,
    /** Total sales in cents. */
    val totalCents: Long,
)

/** One point on the revenue-over-time line. revenueCents is in cents. */
data class RevenueOverTimePoint(
    /** ISO-8601 date. */
    val isoDate: String,
    /** Revenue for this period in cents. */
    val revenueCents: Long,
)

/** One slice in the category breakdown donut chart. */
data class CategoryBreakdownSlice(
    val label: String,
    val value: Double,
    /** Explicit colour — callers should resolve MaterialTheme tokens before constructing. */
    val color: Color,
)

// ─── Private helpers ──────────────────────────────────────────────────────────

private fun usdCurrencyFormatter(): NumberFormat =
    NumberFormat.getCurrencyInstance(Locale.US)

private fun formatCents(cents: Long): String =
    usdCurrencyFormatter().format(cents / 100.0)

/** Converts an ISO-8601 date string to a short label like "Apr 18". */
private fun shortDate(iso: String): String {
    return try {
        val parts = iso.split("-")
        if (parts.size < 3) return iso
        val monthNames = arrayOf(
            "Jan", "Feb", "Mar", "Apr", "May", "Jun",
            "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
        )
        val month = parts[1].toInt().coerceIn(1, 12)
        val day = parts[2].trimStart('0').ifEmpty { "0" }
        "${monthNames[month - 1]} $day"
    } catch (_: Exception) {
        iso
    }
}

// ─── Empty-state surface ──────────────────────────────────────────────────────

@Composable
private fun NoDataSurface(modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier,
        shape = MaterialTheme.shapes.medium,
        color = MaterialTheme.colorScheme.surfaceVariant,
        tonalElevation = 2.dp,
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(160.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = "No data for this period",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
    }
}

// ─── Sales by day — bar chart ─────────────────────────────────────────────────

/**
 * Bar chart showing total sales grouped by period (day/week/month).
 *
 * Uses Vico's [ColumnCartesianLayer]. The Y axis shows dollar amounts; the X
 * axis shows short date labels derived from [SalesByDayPoint.isoDate].
 *
 * TalkBack: contentDescription summarises point count, max value and date, and total.
 */
@Composable
fun SalesByDayBarChart(
    points: List<SalesByDayPoint>,
    appPreferences: AppPreferences,
    modifier: Modifier = Modifier,
) {
    if (points.isEmpty()) {
        NoDataSurface(modifier = modifier.fillMaxWidth())
        return
    }

    val context = LocalContext.current
    val reduceMotion = remember(context, appPreferences.reduceMotionEnabled) {
        ReduceMotion.isReduceMotion(context, appPreferences)
    }

    val maxCents = points.maxOf { it.totalCents }
    val totalCents = points.sumOf { it.totalCents }
    val maxPoint = points.maxByOrNull { it.totalCents }
    val a11yDesc = "Sales bar chart, ${points.size} data point${if (points.size == 1) "" else "s"}, " +
        "max ${formatCents(maxCents)} on ${maxPoint?.isoDate?.let { shortDate(it) } ?: ""}, " +
        "total ${formatCents(totalCents)}"

    val producer = remember { CartesianChartModelProducer() }
    val dateLabels = remember(points) { points.map { shortDate(it.isoDate) } }

    LaunchedEffect(points) {
        withContext(Dispatchers.Default) {
            producer.runTransaction {
                columnSeries {
                    series(points.map { it.totalCents.toFloat() })
                }
            }
        }
    }

    val primaryColor = MaterialTheme.colorScheme.primary
    // fill() is the Compose-side helper from vico.compose.common that converts
    // a Compose Color (inline ULong) to a vico Fill via its ARGB int value.
    // Wrapped in remember() to avoid allocating a new Fill on every recomposition.
    val columnFill = remember(primaryColor) { fill(primaryColor) }

    // CartesianValueFormatter.format(context, value: Double, position)
    val xFormatter = CartesianValueFormatter { _, value, _ ->
        dateLabels.getOrElse(value.toInt()) { "" }
    }
    val yFormatter = CartesianValueFormatter { _, value, _ ->
        usdCurrencyFormatter().format(value / 100.0)
    }

    val chart = rememberCartesianChart(
        rememberColumnCartesianLayer(
            columnProvider = ColumnCartesianLayer.ColumnProvider.series(
                LineComponent(
                    fill = columnFill,
                    thicknessDp = 8f,
                )
            ),
        ),
        startAxis = VerticalAxis.rememberStart(valueFormatter = yFormatter),
        bottomAxis = HorizontalAxis.rememberBottom(valueFormatter = xFormatter),
    )

    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(220.dp)
            .semantics { contentDescription = a11yDesc },
    ) {
        CartesianChartHost(
            chart = chart,
            modelProducer = producer,
            modifier = Modifier.fillMaxSize(),
            scrollState = rememberVicoScrollState(),
            zoomState = rememberVicoZoomState(),
            animationSpec = if (reduceMotion) null else tween(durationMillis = 400),
        )
    }
}

// ─── Revenue over time — line chart ──────────────────────────────────────────

/**
 * Line chart showing revenue trend over the selected date range.
 *
 * Uses Vico's [LineCartesianLayer]. Series colour comes from
 * [MaterialTheme.colorScheme.secondary].
 *
 * TalkBack: contentDescription summarises point count, max, and min values.
 */
@Composable
fun RevenueOverTimeLineChart(
    points: List<RevenueOverTimePoint>,
    appPreferences: AppPreferences,
    modifier: Modifier = Modifier,
) {
    if (points.isEmpty()) {
        NoDataSurface(modifier = modifier.fillMaxWidth())
        return
    }

    val context = LocalContext.current
    val reduceMotion = remember(context, appPreferences.reduceMotionEnabled) {
        ReduceMotion.isReduceMotion(context, appPreferences)
    }

    val maxCents = points.maxOf { it.revenueCents }
    val minCents = points.minOf { it.revenueCents }
    val a11yDesc = "Revenue line chart, ${points.size} data point${if (points.size == 1) "" else "s"}, " +
        "max ${formatCents(maxCents)}, min ${formatCents(minCents)}"

    val producer = remember { CartesianChartModelProducer() }
    val dateLabels = remember(points) { points.map { shortDate(it.isoDate) } }

    LaunchedEffect(points) {
        withContext(Dispatchers.Default) {
            producer.runTransaction {
                lineSeries {
                    series(points.map { it.revenueCents.toFloat() })
                }
            }
        }
    }

    val secondaryColor = MaterialTheme.colorScheme.secondary
    val lineFill = remember(secondaryColor) {
        LineCartesianLayer.LineFill.single(fill(secondaryColor))
    }

    // CartesianValueFormatter.format(context, value: Double, position)
    val xFormatter = CartesianValueFormatter { _, value, _ ->
        dateLabels.getOrElse(value.toInt()) { "" }
    }
    val yFormatter = CartesianValueFormatter { _, value, _ ->
        usdCurrencyFormatter().format(value / 100.0)
    }

    // rememberLine is a @Composable extension on LineCartesianLayer.Companion,
    // declared in com.patrykandpatrick.vico.compose.cartesian.layer. In Kotlin it is
    // called as LineCartesianLayer.rememberLine(fill = ...) via the rememberLine import.
    val line = LineCartesianLayer.rememberLine(fill = lineFill)
    val chart = rememberCartesianChart(
        rememberLineCartesianLayer(
            lineProvider = LineCartesianLayer.LineProvider.series(line),
        ),
        startAxis = VerticalAxis.rememberStart(valueFormatter = yFormatter),
        bottomAxis = HorizontalAxis.rememberBottom(valueFormatter = xFormatter),
    )

    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(220.dp)
            .semantics { contentDescription = a11yDesc },
    ) {
        CartesianChartHost(
            chart = chart,
            modelProducer = producer,
            modifier = Modifier.fillMaxSize(),
            scrollState = rememberVicoScrollState(),
            animationSpec = if (reduceMotion) null else tween(durationMillis = 400),
        )
    }
}

// ─── Category breakdown — donut chart ────────────────────────────────────────

/**
 * Custom Canvas-drawn donut chart for category breakdown.
 *
 * Vico 2.x does not provide a built-in pie/donut layer, so this composable
 * draws directly on a Compose [Canvas] — keeping the dependency tree minimal.
 *
 * Each slice is an arc drawn with a thick [Stroke]; a legend column below the
 * chart names each slice with its percentage.
 *
 * TalkBack: contentDescription lists all slices with their percentage values.
 */
@Composable
fun CategoryBreakdownPieChart(
    slices: List<CategoryBreakdownSlice>,
    modifier: Modifier = Modifier,
) {
    if (slices.isEmpty()) {
        NoDataSurface(modifier = modifier.fillMaxWidth())
        return
    }

    val total = slices.sumOf { it.value }
    val a11yDesc = buildString {
        append("Category donut chart. ")
        slices.forEach { s ->
            val pct = if (total > 0.0) s.value / total * 100.0 else 0.0
            append("${s.label}: ${String.format(Locale.US, "%.1f", pct)}%%. ")
        }
    }.trimEnd()

    Column(
        modifier = modifier
            .fillMaxWidth()
            .semantics { contentDescription = a11yDesc },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Donut arc
        Canvas(modifier = Modifier.size(180.dp)) {
            val strokeWidth = size.minDimension * 0.20f
            val diameter = size.minDimension - strokeWidth
            val topLeft = androidx.compose.ui.geometry.Offset(
                x = (size.width - diameter) / 2f,
                y = (size.height - diameter) / 2f,
            )
            val arcSize = androidx.compose.ui.geometry.Size(diameter, diameter)

            var startAngle = -90f
            slices.forEach { slice ->
                if (total <= 0.0) return@forEach
                val sweep = (slice.value / total * 360.0).toFloat()
                drawArc(
                    color = slice.color,
                    startAngle = startAngle,
                    sweepAngle = sweep,
                    useCenter = false,
                    topLeft = topLeft,
                    size = arcSize,
                    style = Stroke(width = strokeWidth),
                )
                startAngle += sweep
            }
        }

        // Legend
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            slices.forEach { slice ->
                val pct = if (total > 0.0) slice.value / total * 100.0 else 0.0
                Row(
                    modifier = Modifier.fillMaxWidth(),
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
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    Text(
                        text = String.format(Locale.US, "%.1f%%", pct),
                        style = MaterialTheme.typography.bodySmall,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                }
            }
        }
    }
}
