package com.bizarreelectronics.crm.ui.screens.setup.steps

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp

/**
 * §2.10 Step 5 — SMS / email settings (stub).
 *
 * Allows the user to enter a Twilio Account SID and Auth Token for SMS
 * notifications, or skip. Email settings are configured server-side.
 *
 * Server contract (step_index=5):
 *   { twilio_sid: String, twilio_token: String }
 *   { skipped: "true" }
 *
 * TODO: Replace with full Twilio + SMTP settings form. Current stub collects
 * the minimum needed for BizarreSMS integration (ref: docs/business-context.md).
 *
 * [data] — current saved values.
 * [onDataChange] — called with the field map on any change.
 */
@Composable
fun SmsEmailStep(
    data: Map<String, Any>,
    onDataChange: (Map<String, Any>) -> Unit,
    modifier: Modifier = Modifier,
) {
    var twilioSid   by remember { mutableStateOf(data["twilio_sid"]?.toString() ?: "") }
    var twilioToken by remember { mutableStateOf(data["twilio_token"]?.toString() ?: "") }
    var skipped     by remember { mutableStateOf(data["skipped"] == "true") }

    fun emit() {
        if (skipped) { onDataChange(mapOf("skipped" to "true")); return }
        onDataChange(mapOf("twilio_sid" to twilioSid, "twilio_token" to twilioToken))
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 24.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("SMS / Email Settings", style = MaterialTheme.typography.titleLarge)
        Text(
            "Optionally enter your Twilio credentials to enable SMS notifications. You can add these later in Settings.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        OutlinedTextField(
            value = twilioSid,
            onValueChange = { twilioSid = it; skipped = false; emit() },
            label = { Text("Twilio Account SID") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Text),
        )
        OutlinedTextField(
            value = twilioToken,
            onValueChange = { twilioToken = it; skipped = false; emit() },
            label = { Text("Twilio Auth Token") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
        )

        OutlinedButton(onClick = { skipped = true; emit() }) {
            Text("Skip for now")
        }
    }
}
