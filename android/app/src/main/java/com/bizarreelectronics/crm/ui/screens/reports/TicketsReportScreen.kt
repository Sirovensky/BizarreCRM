package com.bizarreelectronics.crm.ui.screens.reports

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * §15 Tickets Report — stub. Wave-2 agent referenced VM fields and DTOs
 * that never landed (`ticketsReport`, `loadTicketsReport`, `TicketsReport`,
 * `TechTicketRow`, `byTech`, `totalCreated`, `avgTurnaroundHours`). Stubbed
 * for build-green; restore when the report surface is implemented end-to-end.
 */
@Composable
fun TicketsReportScreen(
    @Suppress("UNUSED_PARAMETER") viewModel: ReportsViewModel? = null,
) {
    Box(
        modifier = Modifier.fillMaxSize().padding(24.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = "Tickets report — coming soon",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
