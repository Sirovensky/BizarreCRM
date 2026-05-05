package com.bizarreelectronics.crm.ui.screens.setup.steps

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

/**
 * §2.10 Step 10 — Barcode scanner (stub).
 *
 * Bluetooth/USB barcode scanner configuration is not yet implemented.
 * This stub informs the user and marks the step as skipped automatically.
 *
 * Server contract (step_index=10):
 *   { skipped: "true" }              — skipped (stub default)
 *   { scanner_type: "bluetooth"|"usb"|"camera" } — future
 *
 * TODO: Add scanner type selector and test scan flow using the existing
 * BarcodeScanScreen (ui/screens/inventory/BarcodeScanScreen.kt) as a
 * reference implementation.
 *
 * [data] — current saved values.
 * [onDataChange] — called with the field map on any change.
 */
@Composable
fun BarcodeScannerStep(
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
            imageVector = Icons.Default.QrCodeScanner,
            contentDescription = null,
            modifier = Modifier.size(56.dp),
            tint = MaterialTheme.colorScheme.primary,
        )
        Spacer(Modifier.height(16.dp))
        Text("Barcode Scanner", style = MaterialTheme.typography.titleLarge, textAlign = TextAlign.Center)
        Spacer(Modifier.height(8.dp))
        Text(
            "Barcode scanner configuration is not yet available in the setup wizard. " +
            "The camera scanner is available immediately via the Scan button in the Inventory screen.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(24.dp))
        // TODO: Add scanner type selector + test scan (future wave).
        OutlinedButton(onClick = { onDataChange(mapOf("skipped" to "true")) }) {
            Text("Skip for now")
        }
    }
}
