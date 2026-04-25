package com.bizarreelectronics.crm.ui.screens.pos

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/**
 * TASK-6: Split cart screen — [~] stub.
 *
 * Planned behaviour:
 *  - Show current cart lines with checkboxes
 *  - "New cart name" text field at the top
 *  - "Move to new cart" button creates a new [ParkedCartEntity] from selected
 *    lines and removes them from the active session via [PosCoordinator]
 *
 * Full implementation deferred pending UX confirmation on:
 *   1. Whether the new cart auto-activates or stays parked
 *   2. Discount / tip proration across split carts
 *
 * TODO: POS-SPLIT-001 — implement split cart
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PosSplitCartScreen(
    onBack: () -> Unit,
) {
    Scaffold(
        topBar = {
            TopAppBar(
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Text(
                            "‹",
                            style = MaterialTheme.typography.headlineMedium,
                            color = MaterialTheme.colorScheme.onSurface,
                        )
                    }
                },
                title = { Text("Split cart") },
            )
        },
    ) { padding ->
        Box(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentAlignment = Alignment.Center,
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(16.dp),
                modifier = Modifier.padding(24.dp),
            ) {
                Text(
                    "Split cart",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold,
                )
                Text(
                    "TODO: POS-SPLIT-001\n\n" +
                        "Select lines to move into a new parked cart, then tap " +
                        "\"Move to new cart\".\n\n" +
                        "Full implementation pending UX sign-off on discount / tip proration.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                )
                OutlinedButton(onClick = onBack) {
                    Text("Back")
                }
            }
        }
    }
}
