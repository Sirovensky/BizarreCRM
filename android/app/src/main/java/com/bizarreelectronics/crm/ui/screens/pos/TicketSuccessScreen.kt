package com.bizarreelectronics.crm.ui.screens.pos

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier

/**
 * Phase 3 stub — ticket creation success screen.
 *
 * Retained so AppNavGraph's `Screen.TicketSuccess` route compiles until
 * Phase 3 lands the full check-in module.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TicketSuccessScreen(
    ticketId: Long,
    ticketOrderId: String?,
    onViewTicket: (Long) -> Unit,
    onNewTicket: () -> Unit,
) {
    Scaffold(
        topBar = { TopAppBar(title = { Text("Ticket created") }) }
    ) { padding ->
        Box(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentAlignment = Alignment.Center,
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("Ticket #$ticketId created")
                Button(onClick = { onViewTicket(ticketId) }) { Text("View ticket") }
                Button(onClick = onNewTicket) { Text("New ticket") }
            }
        }
    }
}
