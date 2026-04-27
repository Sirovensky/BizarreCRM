package com.bizarreelectronics.crm.ui.screens.dashboard.components

/**
 * §3.2 L504 — Cash-Trapped card.
 *
 * Displays the total overdue-receivables sum (invoices that are past due and
 * unpaid). A non-zero balance is highlighted in error-red so it demands
 * attention. Tapping the card routes to the Aging Report screen.
 *
 * Data contract:
 * - [overdueReceivablesCents]: total overdue balance in cents. Null = no data.
 * - [overdueCount]: number of overdue invoices. Null = unknown.
 * - [onNavigateToAging]: routes to Invoices → Aging. Null = inert card.
 *
 * Graceful degradation: null fields are safe — empty state shown; no crash.
 * Server endpoint: GET /reports/aging  (404-tolerant; null when absent).
 */

import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalanceWallet
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bizarreelectronics.crm.ui.theme.ErrorRed
import java.text.NumberFormat
import java.util.Locale

private fun formatCentsUsd(cents: Long): String =
    NumberFormat.getCurrencyInstance(Locale.US).format(cents / 100.0)

@Composable
fun CashTrappedCard(
    /** Total overdue balance in cents. Null = data not yet available. */
    overdueReceivablesCents: Long?,
    /** Count of overdue invoices. Null = unknown. */
    overdueCount: Int? = null,
    /** Routes to Aging Report. Null = card is informational-only. */
    onNavigateToAging: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val isEmpty = overdueReceivablesCents == null
    val hasBalance = !isEmpty && overdueReceivablesCents!! > 0

    val a11yDesc = when {
        isEmpty -> "Cash Trapped: overdue receivables data unavailable."
        overdueReceivablesCents == 0L -> "Cash Trapped: no overdue receivables. All invoices paid."
        else -> {
            val countPart = if (overdueCount != null) "$overdueCount invoices, " else ""
            "Cash Trapped: ${countPart}${formatCentsUsd(overdueReceivablesCents!!)} overdue. Tap to view aging report."
        }
    }

    val clickModifier = if (hasBalance && onNavigateToAging != null) {
        Modifier
            .semantics {
                contentDescription = a11yDesc
                role = Role.Button
            }
            .clickable(onClick = onNavigateToAging)
    } else {
        Modifier.semantics { contentDescription = a11yDesc }
    }

    Card(
        modifier = modifier
            .fillMaxWidth()
            .border(
                width = 1.dp,
                color = if (hasBalance)
                    ErrorRed.copy(alpha = 0.6f)
                else
                    MaterialTheme.colorScheme.outline,
                shape = MaterialTheme.shapes.medium,
            )
            .then(clickModifier),
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(
            containerColor = if (hasBalance)
                ErrorRed.copy(alpha = 0.06f)
            else
                MaterialTheme.colorScheme.surface,
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(
                imageVector = Icons.Default.AccountBalanceWallet,
                contentDescription = null,
                tint = if (hasBalance) ErrorRed
                else MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(24.dp),
            )

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "Cash Trapped",
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(modifier = Modifier.height(4.dp))
                when {
                    isEmpty -> Text(
                        text = "No data available",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                    )

                    overdueReceivablesCents == 0L -> Text(
                        text = "No overdue receivables",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface,
                    )

                    else -> {
                        Row(
                            verticalAlignment = Alignment.Bottom,
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            Text(
                                text = formatCentsUsd(overdueReceivablesCents!!),
                                style = MaterialTheme.typography.headlineMedium.copy(
                                    fontWeight = FontWeight.Bold,
                                    fontSize = 24.sp,
                                ),
                                color = ErrorRed,
                            )
                        }
                        if (overdueCount != null && overdueCount > 0) {
                            Spacer(modifier = Modifier.height(2.dp))
                            Text(
                                text = "$overdueCount overdue invoice${if (overdueCount == 1) "" else "s"}",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }

            // Chevron only when tappable
            if (hasBalance && onNavigateToAging != null) {
                Icon(
                    imageVector = Icons.Default.ChevronRight,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(20.dp),
                )
            }
        }
    }
}
