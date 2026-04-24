package com.bizarreelectronics.crm.ui.screens.setup.steps

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp

/**
 * §2.10 Step 7 — First staff invite (optional).
 *
 * Allows the admin to invite one staff member by email during setup.
 * Entirely optional — "Skip for now" is the primary CTA.
 *
 * Server contract (step_index=7):
 *   { invite_email: String, invite_role: "technician"|"manager" }
 *   { skipped: "true" }
 *
 * TODO: Add bulk-invite (multiple emails) + role picker (future wave).
 *
 * [data] — current saved values.
 * [onDataChange] — called with the field map on any change.
 */
@Composable
fun StaffInviteStep(
    data: Map<String, Any>,
    onDataChange: (Map<String, Any>) -> Unit,
    modifier: Modifier = Modifier,
) {
    var email   by remember { mutableStateOf(data["invite_email"]?.toString() ?: "") }
    var role    by remember { mutableStateOf(data["invite_role"]?.toString() ?: "technician") }
    var skipped by remember { mutableStateOf(data["skipped"] == "true") }

    fun emit() {
        if (skipped) { onDataChange(mapOf("skipped" to "true")); return }
        onDataChange(mapOf("invite_email" to email, "invite_role" to role))
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 24.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("Invite First Staff Member", style = MaterialTheme.typography.titleLarge)
        Text(
            "Optionally invite a technician or manager. They will receive an email invitation. You can invite more staff later.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        OutlinedTextField(
            value = email,
            onValueChange = { email = it; skipped = false; emit() },
            label = { Text("Staff email") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
        )

        Text("Role", style = MaterialTheme.typography.bodyMedium)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("technician" to "Technician", "manager" to "Manager").forEach { (value, label) ->
                FilterChip(
                    selected = role == value,
                    onClick  = { role = value; skipped = false; emit() },
                    label    = { Text(label) },
                )
            }
        }

        OutlinedButton(onClick = { skipped = true; emit() }) {
            Text("Skip for now")
        }
    }
}
