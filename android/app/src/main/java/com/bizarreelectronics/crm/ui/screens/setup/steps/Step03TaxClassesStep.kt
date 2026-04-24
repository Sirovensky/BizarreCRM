package com.bizarreelectronics.crm.ui.screens.setup.steps

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * §2.10 Step 3 — Tax classes.
 *
 * Shows the default two tax classes (No Tax 0%, Standard Tax 13%).
 * User can accept defaults or skip. Full customisation is available
 * post-setup in Settings → Tax Classes.
 *
 * Server contract (step_index=3):
 *   { tax_classes: "default" } when accepting defaults
 *   { skipped: "true" }       when skipping
 *
 * TODO: Add per-row rate editing and add/remove rows when the full
 * tax-class editor is built in a future wave.
 *
 * [data] — current saved values (used to restore "skipped" state).
 * [onDataChange] — called with the field map on any change.
 */
@Composable
fun TaxClassesStep(
    data: Map<String, Any>,
    onDataChange: (Map<String, Any>) -> Unit,
    modifier: Modifier = Modifier,
) {
    var skipped by remember { mutableStateOf(data["skipped"] == "true") }

    fun emit() {
        onDataChange(
            if (skipped) mapOf("skipped" to "true")
            else mapOf("tax_classes" to "default")
        )
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 24.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("Tax Classes", style = MaterialTheme.typography.titleLarge)
        Text(
            "The following default tax classes will be created. You can customise them later in Settings.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Card(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("No Tax — 0%", style = MaterialTheme.typography.bodyMedium)
                HorizontalDivider()
                Text("Standard Tax — 13%", style = MaterialTheme.typography.bodyMedium)
            }
        }

        // TODO: Add custom tax-class row editor (future wave).

        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.fillMaxWidth(),
        ) {
            OutlinedButton(
                onClick  = { skipped = true; emit() },
                modifier = Modifier.weight(1f),
            ) { Text("Skip for now") }
            Button(
                onClick  = { skipped = false; emit() },
                modifier = Modifier.weight(1f),
            ) { Text("Use defaults") }
        }
    }
}
