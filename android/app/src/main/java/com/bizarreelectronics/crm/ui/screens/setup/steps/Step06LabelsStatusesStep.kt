package com.bizarreelectronics.crm.ui.screens.setup.steps

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * §2.10 Step 6 — Labels & statuses.
 *
 * Shows the default ticket status set (New, In Progress, Waiting on Part,
 * Ready for Pickup, Closed). User accepts defaults or skips.
 *
 * Server contract (step_index=6):
 *   { statuses: "default" } — accept defaults
 *   { skipped: "true" }     — skip; server uses its seed statuses
 *
 * TODO: Add per-status name/color editing and add/remove rows (future wave).
 *
 * [data] — current saved values.
 * [onDataChange] — called with the field map on any change.
 */
@Composable
fun LabelsStatusesStep(
    data: Map<String, Any>,
    onDataChange: (Map<String, Any>) -> Unit,
    modifier: Modifier = Modifier,
) {
    var skipped by remember { mutableStateOf(data["skipped"] == "true") }

    val defaultStatuses = listOf(
        "New",
        "In Progress",
        "Waiting on Part",
        "Ready for Pickup",
        "Closed",
    )

    fun emit() {
        onDataChange(
            if (skipped) mapOf("skipped" to "true")
            else mapOf("statuses" to "default")
        )
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 24.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("Labels & Statuses", style = MaterialTheme.typography.titleLarge)
        Text(
            "These default ticket statuses will be created. Customise them later in Settings.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Card(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(8.dp)) {
                defaultStatuses.forEachIndexed { idx, status ->
                    Text(
                        text = status,
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.padding(vertical = 6.dp, horizontal = 8.dp),
                    )
                    if (idx < defaultStatuses.lastIndex) HorizontalDivider()
                }
            }
        }

        // TODO: Per-status color picker and add/remove (future wave).

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = { skipped = true; emit() }, modifier = Modifier.weight(1f)) {
                Text("Skip for now")
            }
            Button(onClick = { skipped = false; emit() }, modifier = Modifier.weight(1f)) {
                Text("Use defaults")
            }
        }
    }
}
