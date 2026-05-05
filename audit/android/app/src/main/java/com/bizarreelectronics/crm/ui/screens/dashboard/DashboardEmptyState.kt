package com.bizarreelectronics.crm.ui.screens.dashboard

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

/**
 * §3 L497 — new-tenant empty state for the Dashboard KPI grid.
 *
 * Rendered when [DashboardUiState.allKpisZero] is true (all five KPIs
 * are zero, meaning no data exists yet). Hidden as soon as any KPI > 0
 * so returning users never see it again.
 *
 * The illustration uses a Material icon placeholder; swap for a proper
 * vector drawable when the design asset is available.
 *
 * @param onCreateTicket CTA callback — navigates to /tickets/new.
 */
@Composable
fun DashboardEmptyState(
    onCreateTicket: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 32.dp, vertical = 40.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        // Illustration placeholder — replace with a branded vector drawable
        // (e.g. R.drawable.ic_dashboard_welcome) when the asset is delivered.
        Icon(
            imageVector = Icons.Default.Inventory2,
            contentDescription = null, // decorative — heading below carries the announcement
            modifier = Modifier.size(80.dp),
            tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.35f),
        )

        Spacer(modifier = Modifier.height(24.dp))

        Text(
            text = "Welcome to Bizarre!",
            style = MaterialTheme.typography.headlineSmall,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.semantics { heading() },
        )

        Spacer(modifier = Modifier.height(12.dp))

        Text(
            text = "Your first data will appear here as soon as you create a ticket, invoice, or appointment.",
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Spacer(modifier = Modifier.height(28.dp))

        Button(onClick = onCreateTicket) {
            Text("Create first ticket")
        }
    }
}
