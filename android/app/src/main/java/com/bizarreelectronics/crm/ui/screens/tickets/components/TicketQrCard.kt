package com.bizarreelectronics.crm.ui.screens.tickets.components

import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import com.bizarreelectronics.crm.R
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.util.QrCodeGenerator

/**
 * TicketQrCard — §4.2 L673
 *
 * Displays a 200×200dp inline QR code card encoding the ticket's [orderId].
 * Tap → full-screen dialog with 400dp QR + selectable plaintext order-ID
 * below, designed so a counter printer can photograph the code.
 *
 * Backed by [QrCodeGenerator.generateQrBitmap] (ZXing, on-device, no
 * network). The full-screen QR is generated at 512 px for print clarity.
 *
 * @param orderId Ticket order ID to encode (e.g. "T-00042").
 */
@Composable
fun TicketQrCard(orderId: String) {
    val density = LocalDensity.current
    val context = LocalContext.current

    // Inline card QR (200dp → px)
    val smallQrPx = with(density) { 200.dp.roundToPx() }.coerceAtLeast(200)
    val smallBitmap = remember(orderId, smallQrPx) {
        runCatching { QrCodeGenerator.generateQrBitmap(orderId, smallQrPx) }.getOrNull()
    }

    var showFullScreen by remember { mutableStateOf(false) }

    BrandCard(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { showFullScreen = true }
            // §26 — custom QR image: use a11y_* string resource with formatted order ID
        .semantics { contentDescription = context.getString(R.string.a11y_qr_code_for_ticket, orderId) },
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                "Ticket QR",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (smallBitmap != null) {
                Image(
                    bitmap = smallBitmap.asImageBitmap(),
                    contentDescription = null, // container handles a11y
                    modifier = Modifier.size(200.dp),
                )
            } else {
                Box(modifier = Modifier.size(200.dp), contentAlignment = Alignment.Center) {
                    Text(
                        orderId,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                    )
                }
            }
            Text(
                orderId,
                style = MaterialTheme.typography.labelSmall.copy(fontFamily = FontFamily.Monospace),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                "Tap to enlarge",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }

    // Full-screen enlarge dialog
    if (showFullScreen) {
        val largePx = with(density) { 512.dp.roundToPx() }.coerceAtLeast(512)
        val largeBitmap = remember(orderId, largePx) {
            runCatching { QrCodeGenerator.generateQrBitmap(orderId, largePx) }.getOrNull()
        }

        AlertDialog(
            onDismissRequest = { showFullScreen = false },
            title = { Text("Ticket QR — $orderId") },
            text = {
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    if (largeBitmap != null) {
                        Image(
                            bitmap = largeBitmap.asImageBitmap(),
                            // §26 — a11y_* string resource
                            contentDescription = context.getString(R.string.a11y_qr_code_large, orderId),
                            modifier = Modifier.size(400.dp),
                        )
                    }
                    SelectionContainer {
                        Text(
                            orderId,
                            style = MaterialTheme.typography.headlineSmall.copy(
                                fontFamily = FontFamily.Monospace,
                                fontWeight = FontWeight.Bold,
                            ),
                            textAlign = TextAlign.Center,
                        )
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { showFullScreen = false }) {
                    Text("Close")
                }
            },
        )
    }
}
