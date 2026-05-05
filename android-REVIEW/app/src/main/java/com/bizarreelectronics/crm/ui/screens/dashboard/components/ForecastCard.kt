package com.bizarreelectronics.crm.ui.screens.dashboard.components

/**
 * §3.2 L505 — Revenue Forecast card (stub).
 *
 * Placeholder for next-30-day revenue forecast. When [forecastRevenue] is null
 * (insufficient history) the card displays:
 *   "Forecast available with 90+ days of history"
 *
 * Data contract:
 * - [forecastRevenue]: projected next-30-day revenue in cents. Null = not enough data.
 * - [historyDays]: days of history the model has. Used to compute progress toward 90.
 *
 * Stub mode: both fields null is safe — shows full empty state. No crash.
 */

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Insights
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.text.NumberFormat
import java.util.Locale

private fun formatCentsUsd(cents: Long): String =
    NumberFormat.getCurrencyInstance(Locale.US).format(cents / 100.0)

@Composable
fun ForecastCard(
    /** Next-30-day forecast in cents. Null = insufficient history. */
    forecastRevenue: Long?,
    /** Days of revenue history available. Null = unknown. */
    historyDays: Int? = null,
    modifier: Modifier = Modifier,
) {
    val hasForecast = forecastRevenue != null
    val a11yDesc = if (hasForecast) {
        "Revenue forecast: ${formatCentsUsd(forecastRevenue!!)} projected over the next 30 days."
    } else {
        "Revenue forecast unavailable. Need 90+ days of history."
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
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(
                    imageVector = Icons.Default.Insights,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.tertiary,
                    modifier = Modifier.size(20.dp),
                )
                Text(
                    text = "30-Day Forecast",
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            Spacer(modifier = Modifier.height(12.dp))

            if (hasForecast) {
                Text(
                    text = formatCentsUsd(forecastRevenue!!),
                    style = MaterialTheme.typography.displaySmall.copy(
                        fontWeight = FontWeight.Bold,
                        fontSize = 32.sp,
                    ),
                    color = MaterialTheme.colorScheme.tertiary,
                )
                Text(
                    text = "projected next 30 days",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                // Empty state with progress toward 90-day threshold
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(80.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(
                            text = "Forecast available with 90+ days of history",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center,
                        )
                        if (historyDays != null) {
                            val progress = (historyDays / 90f).coerceIn(0f, 1f)
                            LinearProgressIndicator(
                                progress = { progress },
                                modifier = Modifier.fillMaxWidth(0.7f),
                                color = MaterialTheme.colorScheme.tertiary,
                            )
                            Text(
                                text = "$historyDays / 90 days",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                            )
                        }
                    }
                }
            }
        }
    }
}
