package com.bizarreelectronics.crm.ui.screens.dashboard.components

/**
 * §3.2 L504 — Churn Alert card (stub).
 *
 * Shows the count of "at risk" customers (customers with no ticket in the last
 * 90 days who previously had recurring tickets). Tapping the card routes to a
 * filtered customer list.
 *
 * Data contract:
 * - [atRiskCount]: number of customers flagged at risk. Null = no data.
 * - [onViewAtRisk]: navigation callback. Null = card is informational-only.
 *
 * Stub note: "at risk" classification logic lives server-side. Until the
 * endpoint ships, [atRiskCount] will be null and the card shows a "Data
 * unavailable" notice — no crash.
 */

import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PersonOff
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bizarreelectronics.crm.ui.theme.WarningAmber

@Composable
fun ChurnAlertCard(
    /** Count of at-risk customers. Null = server data unavailable. */
    atRiskCount: Int?,
    /** Opens filtered at-risk customer list. Null = no tap-through yet. */
    onViewAtRisk: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val isEmpty = atRiskCount == null
    val a11yDesc = when {
        isEmpty -> "Churn Alert: data unavailable."
        atRiskCount == 0 -> "Churn Alert: no at-risk customers. Good shape."
        else -> "Churn Alert: $atRiskCount customers at risk. Tap to view list."
    }

    val clickModifier = if (atRiskCount != null && atRiskCount > 0 && onViewAtRisk != null) {
        Modifier
            .semantics {
                contentDescription = a11yDesc
                role = Role.Button
            }
            .clickable(onClick = onViewAtRisk)
    } else {
        Modifier.semantics { contentDescription = a11yDesc }
    }

    Card(
        modifier = modifier
            .fillMaxWidth()
            .border(
                width = 1.dp,
                color = if (!isEmpty && atRiskCount!! > 0)
                    WarningAmber.copy(alpha = 0.6f)
                else
                    MaterialTheme.colorScheme.outline,
                shape = MaterialTheme.shapes.medium,
            )
            .then(clickModifier),
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(
            containerColor = if (!isEmpty && atRiskCount!! > 0)
                WarningAmber.copy(alpha = 0.08f)
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
                imageVector = Icons.Default.PersonOff,
                contentDescription = null,
                tint = if (!isEmpty && atRiskCount!! > 0) WarningAmber
                else MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(24.dp),
            )

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "Churn Alert",
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(modifier = Modifier.height(4.dp))
                when {
                    isEmpty -> Text(
                        text = "Data unavailable",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                    )
                    atRiskCount == 0 -> Text(
                        text = "No at-risk customers",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    else -> Row(
                        verticalAlignment = Alignment.Bottom,
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Text(
                            text = atRiskCount.toString(),
                            style = MaterialTheme.typography.headlineMedium.copy(
                                fontWeight = FontWeight.Bold,
                                fontSize = 28.sp,
                            ),
                            color = WarningAmber,
                        )
                        Text(
                            text = "at risk",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(bottom = 4.dp),
                        )
                    }
                }
            }

            // Chevron when tappable
            if (atRiskCount != null && atRiskCount > 0 && onViewAtRisk != null) {
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
