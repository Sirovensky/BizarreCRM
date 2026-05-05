package com.bizarreelectronics.crm.ui.screens.inventory.components

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.patrykandpatrick.vico.compose.cartesian.CartesianChartHost
import com.patrykandpatrick.vico.compose.cartesian.axis.rememberBottom
import com.patrykandpatrick.vico.compose.cartesian.axis.rememberStart
import com.patrykandpatrick.vico.compose.cartesian.layer.rememberLine
import com.patrykandpatrick.vico.compose.cartesian.layer.rememberLineCartesianLayer
import com.patrykandpatrick.vico.compose.cartesian.rememberCartesianChart
import com.patrykandpatrick.vico.compose.common.fill
import com.patrykandpatrick.vico.core.cartesian.axis.HorizontalAxis
import com.patrykandpatrick.vico.core.cartesian.axis.VerticalAxis
import com.patrykandpatrick.vico.core.cartesian.data.CartesianChartModelProducer
import com.patrykandpatrick.vico.core.cartesian.data.CartesianValueFormatter
import com.patrykandpatrick.vico.core.cartesian.data.lineSeries
import com.patrykandpatrick.vico.core.cartesian.layer.LineCartesianLayer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Price history chart for an inventory item (L1072).
 *
 * Renders two [LineCartesianLayer] series — cost price (secondary colour) and
 * retail price (primary colour) — over time. When [priceHistory] is empty or
 * null the component shows a "No price history yet" stub instead of crashing.
 *
 * @param priceHistory List of [PricePoint] from the API, ordered chronologically.
 * @param modifier     Applied to the root [BrandCard].
 */
@Composable
fun InventoryPriceChart(
    priceHistory: List<PricePoint>?,
    modifier: Modifier = Modifier,
) {
    BrandCard(modifier = modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text("Price history", style = MaterialTheme.typography.titleSmall)
            Spacer(modifier = Modifier.height(12.dp))

            if (priceHistory.isNullOrEmpty()) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(140.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        "No price history yet",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                return@Column
            }

            PriceChartContent(
                priceHistory = priceHistory,
                modifier = Modifier.fillMaxWidth().height(180.dp),
            )
        }
    }
}

/**
 * One price sample from the API.
 *
 * @param isoDate    ISO-8601 date label for the X axis, e.g. "2026-03-15".
 * @param costCents  Cost price in cents at this date.
 * @param retailCents Retail price in cents at this date.
 */
data class PricePoint(
    val isoDate: String,
    val costCents: Long,
    val retailCents: Long,
)

@Composable
private fun PriceChartContent(
    priceHistory: List<PricePoint>,
    modifier: Modifier = Modifier,
) {
    val primaryColor = MaterialTheme.colorScheme.primary
    val secondaryColor = MaterialTheme.colorScheme.secondary

    val producer = remember { CartesianChartModelProducer() }
    val dateLabels = remember(priceHistory) {
        priceHistory.map { shortDate(it.isoDate) }
    }

    LaunchedEffect(priceHistory) {
        withContext(Dispatchers.Default) {
            producer.runTransaction {
                lineSeries {
                    // Series 0: cost price
                    series(priceHistory.map { it.costCents.toFloat() / 100f })
                    // Series 1: retail price
                    series(priceHistory.map { it.retailCents.toFloat() / 100f })
                }
            }
        }
    }

    val costFill = LineCartesianLayer.LineFill.single(fill(secondaryColor))
    val retailFill = LineCartesianLayer.LineFill.single(fill(primaryColor))
    val costLine = LineCartesianLayer.rememberLine(fill = costFill)
    val retailLine = LineCartesianLayer.rememberLine(fill = retailFill)

    val xFormatter = CartesianValueFormatter { _, value, _ ->
        dateLabels.getOrElse(value.toInt()) { "" }
    }
    val yFormatter = CartesianValueFormatter { _, value, _ ->
        "$${"%.2f".format(value)}"
    }

    val chart = rememberCartesianChart(
        rememberLineCartesianLayer(
            lineProvider = LineCartesianLayer.LineProvider.series(costLine, retailLine),
        ),
        startAxis = VerticalAxis.rememberStart(valueFormatter = yFormatter),
        bottomAxis = HorizontalAxis.rememberBottom(valueFormatter = xFormatter),
    )

    val a11yDesc = "Price history chart: ${priceHistory.size} points, " +
        "latest cost $${"%.2f".format(priceHistory.last().costCents / 100.0)}, " +
        "latest retail $${"%.2f".format(priceHistory.last().retailCents / 100.0)}"

    Box(
        modifier = modifier.semantics { contentDescription = a11yDesc },
    ) {
        CartesianChartHost(
            chart = chart,
            modelProducer = producer,
        )
    }

    // Legend
    Row(
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        modifier = Modifier.padding(top = 8.dp),
    ) {
        LegendDot(color = secondaryColor, label = "Cost")
        LegendDot(color = primaryColor, label = "Retail")
    }
}

@Composable
private fun LegendDot(color: Color, label: String) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Surface(
            modifier = Modifier.size(10.dp),
            shape = MaterialTheme.shapes.extraSmall,
            color = color,
        ) {}
        Text(label, style = MaterialTheme.typography.labelSmall)
    }
}

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
