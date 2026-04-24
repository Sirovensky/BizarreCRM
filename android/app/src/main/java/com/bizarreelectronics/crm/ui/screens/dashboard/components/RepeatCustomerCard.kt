package com.bizarreelectronics.crm.ui.screens.dashboard.components

/**
 * §3.2 L503 — Repeat Customer card.
 *
 * Shows percentage of customers who have more than 1 ticket in the last 90 days,
 * plus a trend arrow indicating direction versus the prior 90-day period.
 *
 * Data contract:
 * - [repeatPercent]: 0.0–100.0. Null = no data (shows "—").
 * - [trendDelta]: positive = improved retention, negative = worsening, null = unknown.
 */

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bizarreelectronics.crm.ui.theme.ErrorRed
import com.bizarreelectronics.crm.ui.theme.SuccessGreen

@Composable
fun RepeatCustomerCard(
    /** Percentage of customers with >1 ticket last 90 days. Null = no data. */
    repeatPercent: Double?,
    /** Delta vs prior 90-day period. Positive = more repeat customers. Null = unknown. */
    trendDelta: Double?,
    modifier: Modifier = Modifier,
) {
    val valueText = repeatPercent?.let { String.format("%.1f%%", it) } ?: "—"
    val a11yDesc = buildString {
        append("Repeat customers: $valueText in the last 90 days.")
        when {
            trendDelta == null -> Unit
            trendDelta > 0 -> append(" Up ${String.format("%.1f", trendDelta)}pp vs prior period.")
            trendDelta < 0 -> append(" Down ${String.format("%.1f", -trendDelta)}pp vs prior period.")
            else -> append(" No change vs prior period.")
        }
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
                    imageVector = Icons.Default.Repeat,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.secondary,
                    modifier = Modifier.size(20.dp),
                )
                Text(
                    text = "Repeat Customers",
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            Spacer(modifier = Modifier.height(12.dp))

            Row(
                verticalAlignment = Alignment.Bottom,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    text = valueText,
                    style = MaterialTheme.typography.displaySmall.copy(
                        fontWeight = FontWeight.Bold,
                        fontSize = 36.sp,
                    ),
                    color = if (repeatPercent != null)
                        MaterialTheme.colorScheme.secondary
                    else
                        MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
                )

                // Trend arrow
                if (trendDelta != null) {
                    TrendArrow(
                        delta = trendDelta,
                        modifier = Modifier.padding(bottom = 6.dp),
                    )
                }
            }

            Text(
                text = "had >1 ticket in last 90 days",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun TrendArrow(delta: Double, modifier: Modifier = Modifier) {
    val (icon, color) = when {
        delta > 0 -> Icons.Default.ArrowUpward to SuccessGreen
        delta < 0 -> Icons.Default.ArrowDownward to ErrorRed
        else -> Icons.Default.Remove to MaterialTheme.colorScheme.onSurfaceVariant
    }
    Icon(
        imageVector = icon,
        contentDescription = null, // covered by parent semantics
        tint = color,
        modifier = modifier.size(20.dp),
    )
}
