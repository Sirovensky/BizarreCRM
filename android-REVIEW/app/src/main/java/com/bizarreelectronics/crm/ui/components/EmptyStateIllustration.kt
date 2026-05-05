package com.bizarreelectronics.crm.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * §3.14 L575-L580 — Unified per-feature empty-state illustration wrapper.
 *
 * Renders an emoji icon (no SVG asset required at this stage), a headline,
 * optional subtitle, a primary CTA, and an optional secondary CTA. Designed
 * as the shared wrapper for Tickets / Inventory / Customers / SMS / POS /
 * Reports empty-state shells — follow-up work required per screen:
 *
 *   - TicketListScreen: "📋 No tickets yet" + "Create Ticket" CTA
 *   - InventoryListScreen: "📦 No inventory items" + "Add Item" CTA
 *   - CustomerListScreen: "👥 No customers yet" + "Add Customer" CTA
 *   - SmsListScreen: "💬 No messages yet" + "Send SMS" CTA
 *   - PosScreen: "🏪 Nothing to sell yet" + "Add Item" CTA
 *   - ReportsScreen: "📊 No report data" + "Import Data" CTA
 *
 * See plan §3.14 L575-L580 for the follow-up tasks.
 *
 * @param emoji        Unicode emoji string used as the illustration (e.g. "📋").
 * @param title        Primary headline, displayed in headlineMedium.
 * @param subtitle     Optional supporting text below the headline.
 * @param primaryCta   Label for the primary action button.
 * @param onPrimaryCta Called when the primary CTA is tapped.
 * @param secondaryCta Optional label for a secondary outlined button.
 * @param onSecondaryCta Called when the secondary CTA is tapped (required if [secondaryCta] is non-null).
 * @param modifier     Applied to the root [Column].
 */
@Composable
fun EmptyStateIllustration(
    emoji: String,
    title: String,
    subtitle: String? = null,
    primaryCta: String,
    onPrimaryCta: () -> Unit,
    secondaryCta: String? = null,
    onSecondaryCta: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 32.dp, vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            text = emoji,
            fontSize = 48.sp,
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = title,
            style = MaterialTheme.typography.headlineMedium,
            color = MaterialTheme.colorScheme.onSurface,
            textAlign = TextAlign.Center,
        )
        if (subtitle != null) {
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
        Spacer(modifier = Modifier.height(8.dp))
        if (secondaryCta != null && onSecondaryCta != null) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                OutlinedButton(onClick = onSecondaryCta) {
                    Text(secondaryCta)
                }
                Button(onClick = onPrimaryCta) {
                    Text(primaryCta)
                }
            }
        } else {
            Button(onClick = onPrimaryCta) {
                Text(primaryCta)
            }
        }
    }
}
