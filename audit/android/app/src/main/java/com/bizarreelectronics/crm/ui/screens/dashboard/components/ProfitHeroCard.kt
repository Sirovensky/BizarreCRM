package com.bizarreelectronics.crm.ui.screens.dashboard.components

/**
 * §3.2 L500 — Profit Hero card.
 *
 * Displays net-margin percentage in a large display style with a Vico sparkline
 * showing the last 30 days of trend data.
 *
 * Data contract:
 * - [trendPoints]: list of ≤30 daily net-margin values (0.0–100.0). Empty =
 *   "Connect Profit data" affordance; non-empty = sparkline rendered.
 * - [netMarginPercent]: latest net-margin snapshot (nullable when no data).
 *
 * Stub mode: when [trendPoints] is empty the card grays out and shows a
 * "Connect Profit data" footer — no crash.
 */

import androidx.compose.animation.core.tween
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.TrendingUp
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.util.ReduceMotion
import com.patrykandpatrick.vico.compose.cartesian.CartesianChartHost
import com.patrykandpatrick.vico.compose.cartesian.layer.rememberLine
import com.patrykandpatrick.vico.compose.cartesian.layer.rememberLineCartesianLayer
import com.patrykandpatrick.vico.compose.cartesian.rememberCartesianChart
import com.patrykandpatrick.vico.compose.cartesian.rememberVicoScrollState
import com.patrykandpatrick.vico.compose.common.fill
import com.patrykandpatrick.vico.core.cartesian.data.CartesianChartModelProducer
import com.patrykandpatrick.vico.core.cartesian.data.lineSeries
import com.patrykandpatrick.vico.core.cartesian.layer.LineCartesianLayer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@Composable
fun ProfitHeroCard(
    /** Daily net-margin values (0.0–100.0), up to 30 entries. Empty = stub mode. */
    trendPoints: List<Double>,
    /** Latest net-margin snapshot. Null when no data available. */
    netMarginPercent: Double?,
    appPreferences: AppPreferences,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val reduceMotion = remember(context, appPreferences.reduceMotionEnabled) {
        ReduceMotion.isReduceMotion(context, appPreferences)
    }
    val isEmpty = trendPoints.isEmpty()

    val a11yDesc = if (isEmpty) {
        "Profit Hero: no profit data connected."
    } else {
        "Profit Hero: ${netMarginPercent?.let { String.format("%.1f%%", it) } ?: "N/A"} net margin, ${trendPoints.size}-day trend."
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
        colors = CardDefaults.cardColors(
            containerColor = if (isEmpty)
                MaterialTheme.colorScheme.surfaceVariant
            else
                MaterialTheme.colorScheme.surfaceVariant,
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(
                    imageVector = Icons.Default.TrendingUp,
                    contentDescription = null,
                    tint = if (isEmpty)
                        MaterialTheme.colorScheme.onSurfaceVariant
                    else
                        MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(20.dp),
                )
                Text(
                    text = "Profit Hero",
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            Spacer(modifier = Modifier.height(8.dp))

            if (isEmpty) {
                // Stub / disconnected state
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(80.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = "—",
                        style = MaterialTheme.typography.displayMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f),
                        textAlign = TextAlign.Center,
                    )
                }
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "Connect Profit data",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                    modifier = Modifier.fillMaxWidth(),
                    textAlign = TextAlign.Center,
                )
            } else {
                // Net margin headline
                Text(
                    text = netMarginPercent?.let { String.format("%.1f%%", it) } ?: "N/A",
                    style = MaterialTheme.typography.displaySmall.copy(
                        fontWeight = FontWeight.Bold,
                        fontSize = 40.sp,
                    ),
                    color = MaterialTheme.colorScheme.primary,
                )
                Text(
                    text = "Net margin",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )

                Spacer(modifier = Modifier.height(12.dp))

                // Vico sparkline
                ProfitSparkline(
                    points = trendPoints,
                    reduceMotion = reduceMotion,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(80.dp),
                )
            }
        }
    }
}

@Composable
private fun ProfitSparkline(
    points: List<Double>,
    reduceMotion: Boolean,
    modifier: Modifier = Modifier,
) {
    val producer = remember { CartesianChartModelProducer() }

    LaunchedEffect(points) {
        withContext(Dispatchers.Default) {
            producer.runTransaction {
                lineSeries {
                    series(points.map { it.toFloat() })
                }
            }
        }
    }

    val lineColor = MaterialTheme.colorScheme.primary
    val lineFill = remember(lineColor) {
        LineCartesianLayer.LineFill.single(fill(lineColor))
    }
    val line = LineCartesianLayer.rememberLine(fill = lineFill)
    val chart = rememberCartesianChart(
        rememberLineCartesianLayer(
            lineProvider = LineCartesianLayer.LineProvider.series(line),
        ),
        // No axes for sparkline — keep it minimal
    )

    CartesianChartHost(
        chart = chart,
        modelProducer = producer,
        modifier = modifier,
        scrollState = rememberVicoScrollState(),
        animationSpec = if (reduceMotion) null else tween(durationMillis = 400),
    )
}
