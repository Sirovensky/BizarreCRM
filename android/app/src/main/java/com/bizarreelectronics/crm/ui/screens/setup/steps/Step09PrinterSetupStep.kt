package com.bizarreelectronics.crm.ui.screens.setup.steps

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Print
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

/**
 * §2.10 Step 9 — Printer setup (stub).
 *
 * Bluetooth printer pairing is not yet implemented. This stub informs the
 * user and marks the step as skipped automatically so validation passes.
 *
 * Server contract (step_index=9):
 *   { skipped: "true" }           — skipped (stub default)
 *   { printer_mac: String }       — future: Bluetooth MAC address of paired printer
 *
 * TODO: Integrate Android BluetoothAdapter discovery and pair flow when
 * the receipt-printing feature is implemented (future wave).
 *
 * [data] — current saved values.
 * [onDataChange] — called with the field map on any change.
 */
@Composable
fun PrinterSetupStep(
    data: Map<String, Any>,
    onDataChange: (Map<String, Any>) -> Unit,
    modifier: Modifier = Modifier,
) {
    LaunchedEffect(Unit) {
        if (data["skipped"] != "true") {
            onDataChange(mapOf("skipped" to "true"))
        }
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 24.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            imageVector = Icons.Default.Print,
            contentDescription = null,
            modifier = Modifier.size(56.dp),
            tint = MaterialTheme.colorScheme.primary,
        )
        Spacer(Modifier.height(16.dp))
        Text("Printer Setup", style = MaterialTheme.typography.titleLarge, textAlign = TextAlign.Center)
        Spacer(Modifier.height(8.dp))
        Text(
            "Bluetooth printer pairing is not yet available in the setup wizard. " +
            "You can configure a printer later in Settings → Printer.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(24.dp))
        // TODO: Add BluetoothAdapter.startDiscovery() flow (future wave).
        OutlinedButton(onClick = { onDataChange(mapOf("skipped" to "true")) }) {
            Text("Skip for now")
        }
    }
}
