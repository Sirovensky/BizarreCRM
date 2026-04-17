package com.bizarreelectronics.crm.ui.screens.pos

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.bizarreelectronics.crm.ui.components.WaveDivider
import com.bizarreelectronics.crm.ui.theme.BrandMono
import com.bizarreelectronics.crm.ui.theme.SuccessGreen
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

@Composable
fun TicketSuccessScreen(
    ticketId: Long,
    ticketOrderId: String? = null,
    onViewTicket: (Long) -> Unit,
    onNewTicket: () -> Unit,
) {
    Scaffold { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            // ── Brand wave divider — sanctioned placement above checkmark ──
            WaveDivider(modifier = Modifier.padding(bottom = 24.dp))

            // ── Green checkmark ──────────────────────────────────────
            Surface(
                shape = MaterialTheme.shapes.extraLarge,
                color = SuccessGreen.copy(alpha = 0.12f),
                modifier = Modifier.size(96.dp),
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(
                        Icons.Default.CheckCircle,
                        contentDescription = "Success",
                        modifier = Modifier.size(64.dp),
                        tint = SuccessGreen,
                    )
                }
            }

            Spacer(modifier = Modifier.height(24.dp))

            // ── Heading ──────────────────────────────────────────────
            Text(
                "Ticket Created!",
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
            )

            Spacer(modifier = Modifier.height(12.dp))

            // ── Ticket ID — BrandMono (JetBrains Mono, fixed-width data) ──
            val displayId = ticketOrderId ?: "T-$ticketId"
            Surface(
                shape = MaterialTheme.shapes.medium,
                color = MaterialTheme.colorScheme.primaryContainer,
            ) {
                Text(
                    displayId,
                    modifier = Modifier.padding(horizontal = 24.dp, vertical = 12.dp),
                    style = BrandMono.copy(
                        fontSize = MaterialTheme.typography.titleLarge.fontSize,
                        lineHeight = MaterialTheme.typography.titleLarge.lineHeight,
                    ),
                    color = MaterialTheme.colorScheme.onPrimaryContainer,
                )
            }

            Spacer(modifier = Modifier.height(8.dp))

            Text(
                "The repair ticket has been created successfully.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )

            Spacer(modifier = Modifier.height(48.dp))

            // ── Action buttons ───────────────────────────────────────
            Button(
                onClick = { onViewTicket(ticketId) },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(52.dp),
            ) {
                // decorative — Button's "View Ticket" Text supplies the accessible name
                Icon(Icons.Default.Visibility, contentDescription = null, modifier = Modifier.size(20.dp))
                Spacer(modifier = Modifier.width(8.dp))
                Text("View Ticket", style = MaterialTheme.typography.titleMedium)
            }

            Spacer(modifier = Modifier.height(12.dp))

            OutlinedButton(
                onClick = onNewTicket,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(52.dp),
            ) {
                // decorative — Button's "New Ticket" Text supplies the accessible name
                Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.size(20.dp))
                Spacer(modifier = Modifier.width(8.dp))
                Text("New Ticket", style = MaterialTheme.typography.titleMedium)
            }
        }
    }
}
