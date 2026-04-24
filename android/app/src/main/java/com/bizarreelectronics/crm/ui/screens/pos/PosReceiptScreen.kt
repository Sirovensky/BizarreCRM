package com.bizarreelectronics.crm.ui.screens.pos

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PosReceiptScreen(
    onOpenTicket: (ticketId: Long) -> Unit,
    onNewSale: () -> Unit,
    viewModel: PosReceiptViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(state.snackbarMessage) {
        state.snackbarMessage?.let { msg ->
            snackbarHostState.showSnackbar(msg)
            viewModel.clearSnackbar()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Sale complete") },
                actions = {
                    Surface(
                        shape = RoundedCornerShape(99.dp),
                        color = MaterialTheme.colorScheme.tertiary,
                    ) {
                        Text(
                            "✓ Paid",
                            modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp),
                            style = MaterialTheme.typography.labelMedium,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onTertiary,
                        )
                    }
                    Spacer(modifier = Modifier.width(8.dp))
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
        bottomBar = {
            ReceiptNextActionsBar(
                linkedTicketId = state.linkedTicketId,
                onOpenTicket = { state.linkedTicketId?.let(onOpenTicket) },
                onNewSale = {
                    viewModel.startNewSale()
                    onNewSale()
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState()),
        ) {
            // ── Success hero ───────────────────────────────────────────────────
            Column(
                modifier = Modifier.fillMaxWidth().padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Box(
                    modifier = Modifier
                        .size(72.dp)
                        .clip(CircleShape)
                        .background(MaterialTheme.colorScheme.tertiary)
                        .semantics { contentDescription = "Payment complete checkmark" },
                    contentAlignment = Alignment.Center,
                ) {
                    Text("✓", style = MaterialTheme.typography.displaySmall, color = MaterialTheme.colorScheme.onTertiary)
                }
                Text(state.totalCents.toDollarString(), style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.ExtraBold)
                Text(
                    "Invoice #${state.invoiceId ?: state.orderId} · ${state.customerName}",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                state.linkedTicketId?.let { ticketId ->
                    Text(
                        "Parts reserved to Ticket #$ticketId",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                // Tracking URL
                state.trackingUrl?.let { url ->
                    val displayUrl = if (url.startsWith("/")) "https://…$url" else url
                    Text(
                        displayUrl,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.tertiary,
                        textDecoration = TextDecoration.Underline,
                    )
                }
            }

            // ── Send receipt section ───────────────────────────────────────────
            Text(
                "SEND RECEIPT",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 14.dp, vertical = 4.dp),
            )

            state.customerPhone?.let { phone ->
                SendRow(
                    emoji = "💬",
                    title = "SMS",
                    subtitle = "$phone · via BizarreSMS",
                    isPrimary = true,
                    sendState = state.smsSentState,
                    onSend = viewModel::sendSms,
                    contentDesc = "Send SMS receipt to $phone",
                )
            }
            state.customerEmail?.let { email ->
                SendRow(
                    emoji = "✉",
                    title = "Email",
                    subtitle = email,
                    isPrimary = false,
                    sendState = state.emailSentState,
                    onSend = viewModel::sendEmail,
                    contentDesc = "Send email receipt to $email",
                )
            }
            SendRow(
                emoji = "🖨",
                title = "Thermal print",
                subtitle = "Epson TM-m30 · counter",
                isPrimary = false,
                sendState = SendState.IDLE,
                onSend = { /* thermal print — Phase 4 hardware */ },
                contentDesc = "Print thermal receipt",
            )

            Spacer(modifier = Modifier.height(24.dp))
        }
    }
}

// ─── Send row ─────────────────────────────────────────────────────────────────

@Composable
private fun SendRow(
    emoji: String,
    title: String,
    subtitle: String,
    isPrimary: Boolean,
    sendState: SendState,
    onSend: () -> Unit,
    contentDesc: String,
) {
    val borderColor = if (isPrimary) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline
    val borderWidth = if (isPrimary) 1.5.dp else 1.dp

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp, vertical = 4.dp)
            .clip(RoundedCornerShape(12.dp))
            .border(borderWidth, borderColor, RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surface)
            .clickable(
                enabled = sendState == SendState.IDLE || sendState == SendState.ERROR,
                onClickLabel = contentDesc,
            ) { onSend() }
            .padding(horizontal = 14.dp, vertical = 12.dp)
            .semantics { contentDescription = contentDesc },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(emoji, style = MaterialTheme.typography.titleLarge)
        Column(modifier = Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyMedium, fontWeight = if (isPrimary) FontWeight.Bold else FontWeight.SemiBold)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        when (sendState) {
            SendState.SENDING -> CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
            SendState.SENT -> Text("✓", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.tertiary, fontWeight = FontWeight.Bold)
            SendState.ERROR -> Text("!", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.error)
            SendState.IDLE -> Text("›", style = MaterialTheme.typography.bodyLarge, color = if (isPrimary) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

// ─── Bottom next-actions bar ──────────────────────────────────────────────────

@Composable
private fun ReceiptNextActionsBar(
    linkedTicketId: Long?,
    onOpenTicket: () -> Unit,
    onNewSale: () -> Unit,
) {
    Surface(shadowElevation = 8.dp, color = MaterialTheme.colorScheme.surface, tonalElevation = 2.dp) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (linkedTicketId != null) {
                OutlinedButton(
                    onClick = onOpenTicket,
                    modifier = Modifier
                        .weight(1f)
                        .semantics { contentDescription = "Open ticket $linkedTicketId" },
                    shape = RoundedCornerShape(12.dp),
                ) {
                    Text("Open ticket #$linkedTicketId", fontWeight = FontWeight.SemiBold)
                }
            }
            Button(
                onClick = onNewSale,
                modifier = Modifier
                    .weight(if (linkedTicketId != null) 1.2f else 1f)
                    .height(48.dp)
                    .semantics { contentDescription = "Start new sale" },
                shape = RoundedCornerShape(12.dp),
            ) {
                Text("New sale ↗", fontWeight = FontWeight.Bold)
            }
        }
    }
}
