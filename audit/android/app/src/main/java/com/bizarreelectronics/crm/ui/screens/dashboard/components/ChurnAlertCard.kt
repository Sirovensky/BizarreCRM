package com.bizarreelectronics.crm.ui.screens.dashboard.components

/**
 * §3.2 L504 / §45.3 — Churn Alert card.
 *
 * Shows the count of "at risk" customers (customers with no ticket in the last
 * 90 days who previously had recurring tickets). Tapping the card routes to a
 * filtered customer list; tapping "Send win-back SMS" pre-fills the SMS compose
 * screen with a win-back template.
 *
 * Data contract:
 * - [atRiskCount]: number of customers flagged at risk. Null = no data.
 * - [onViewAtRisk]: navigation callback for the "view list" tap. Null = card is
 *   informational-only.
 * - [onSendWinBackSms]: navigation callback that pre-fills a win-back SMS template.
 *   Null = button hidden.
 *
 * Colour convention: risk state uses errorContainer / onErrorContainer tonal pair
 * from MaterialTheme so the card respects dynamic colour and avoids hardcoded hex.
 *
 * The endpoint (GET /reports/churn-risk) is 404-tolerant — [atRiskCount] will be
 * null and the card shows a "Data unavailable" notice when the server hasn't
 * implemented it yet.
 */

import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.PersonOff
import androidx.compose.material.icons.filled.Sms
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.R

@Composable
fun ChurnAlertCard(
    /** Count of at-risk customers. Null = server data unavailable. */
    atRiskCount: Int?,
    /** Opens filtered at-risk customer list. Null = no tap-through yet. */
    onViewAtRisk: (() -> Unit)? = null,
    /** Pre-fills win-back SMS compose. Null = button hidden. */
    onSendWinBackSms: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val isEmpty = atRiskCount == null
    val hasRisk = !isEmpty && atRiskCount!! > 0

    val a11yDesc = when {
        isEmpty -> "Churn Alert: data unavailable."
        atRiskCount == 0 -> "Churn Alert: no at-risk customers. Good shape."
        else -> "Churn Alert: $atRiskCount customers at risk. Tap to view list."
    }

    val clickModifier = if (hasRisk && onViewAtRisk != null) {
        Modifier
            .semantics {
                contentDescription = a11yDesc
                role = Role.Button
            }
            .clickable(onClick = onViewAtRisk)
    } else {
        Modifier.semantics { contentDescription = a11yDesc }
    }

    // Use M3 tonal pair: errorContainer / onErrorContainer for at-risk state.
    val containerColor = if (hasRisk)
        MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.24f)
    else
        MaterialTheme.colorScheme.surface

    val borderColor = if (hasRisk)
        MaterialTheme.colorScheme.error.copy(alpha = 0.5f)
    else
        MaterialTheme.colorScheme.outline

    val iconTint = if (hasRisk)
        MaterialTheme.colorScheme.error
    else
        MaterialTheme.colorScheme.onSurfaceVariant

    Card(
        modifier = modifier
            .fillMaxWidth()
            .border(
                width = 1.dp,
                color = borderColor,
                shape = MaterialTheme.shapes.medium,
            )
            .then(clickModifier),
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(containerColor = containerColor),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(modifier = Modifier.fillMaxWidth()) {
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
                    tint = iconTint,
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
                                ),
                                color = MaterialTheme.colorScheme.error,
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
                if (hasRisk && onViewAtRisk != null) {
                    Icon(
                        imageVector = Icons.Default.ChevronRight,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(20.dp),
                    )
                }
            }

            // §45.3 — "Send win-back SMS" action — shown when there are at-risk customers
            // and the callback is wired.
            if (hasRisk && onSendWinBackSms != null) {
                HorizontalDivider(
                    modifier = Modifier.padding(horizontal = 16.dp),
                    color = MaterialTheme.colorScheme.outlineVariant,
                )
                val winBackCd = stringResource(R.string.cd_send_win_back_sms)
                TextButton(
                    onClick = onSendWinBackSms,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 8.dp, vertical = 4.dp)
                        .semantics { contentDescription = winBackCd },
                    contentPadding = PaddingValues(horizontal = 8.dp, vertical = 8.dp),
                ) {
                    Icon(
                        imageVector = Icons.Default.Sms,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp),
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(
                        text = stringResource(R.string.churn_win_back_sms_action),
                        style = MaterialTheme.typography.labelMedium,
                    )
                }
            }
        }
    }
}
