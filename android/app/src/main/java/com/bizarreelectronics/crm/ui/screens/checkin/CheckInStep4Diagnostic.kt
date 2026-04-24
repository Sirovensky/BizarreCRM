package com.bizarreelectronics.crm.ui.screens.checkin

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

@Composable
fun CheckInStep4Diagnostic(
    diagnostics: Map<String, TriState>,
    batteryHealthPercent: Int?,
    batteryCycles: Int?,
    onSetResult: (String, TriState) -> Unit,
    onAllOk: () -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item(key = "header") {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Function tests", style = MaterialTheme.typography.titleLarge)
                Text(
                    "Record the device state before we touch it.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Button(
                    onClick = onAllOk,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.secondaryContainer,
                        contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
                    ),
                    modifier = Modifier
                        .fillMaxWidth()
                        .semantics { contentDescription = "Set all tests to pass" },
                ) {
                    Text("✓ All OK")
                }
            }
        }

        items(CheckInViewModel.DIAGNOSTIC_TESTS, key = { it }) { test ->
            DiagnosticRow(
                label = test,
                result = diagnostics[test] ?: TriState.UNKNOWN,
                onSetResult = { result -> onSetResult(test, result) },
            )
        }

        item(key = "divider") { HorizontalDivider() }

        item(key = "battery_health") {
            BatteryHealthRow(
                healthPercent = batteryHealthPercent,
                cycles = batteryCycles,
            )
        }
    }
}

@Composable
private fun DiagnosticRow(
    label: String,
    result: TriState,
    onSetResult: (TriState) -> Unit,
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                label,
                style = MaterialTheme.typography.bodyLarge,
                modifier = Modifier.weight(1f),
            )
            TriStateToggle(
                current = result,
                onSelect = onSetResult,
                testLabel = label,
            )
        }
    }
}

@Composable
private fun TriStateToggle(
    current: TriState,
    onSelect: (TriState) -> Unit,
    testLabel: String,
) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        TriState.entries.forEach { state ->
            val isSelected = current == state
            val color = when {
                !isSelected -> MaterialTheme.colorScheme.surfaceVariant
                state == TriState.PASS -> MaterialTheme.colorScheme.secondaryContainer
                state == TriState.FAIL -> MaterialTheme.colorScheme.errorContainer
                else -> MaterialTheme.colorScheme.surfaceVariant
            }
            Card(
                modifier = Modifier
                    .clickable { onSelect(state) }
                    .semantics {
                        contentDescription = "$testLabel: ${state.name.lowercase()}${if (isSelected) " (selected)" else ""}"
                    },
            ) {
                Text(
                    text = state.label,
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                    color = when {
                        !isSelected -> MaterialTheme.colorScheme.onSurfaceVariant
                        state == TriState.PASS -> MaterialTheme.colorScheme.onSecondaryContainer
                        state == TriState.FAIL -> MaterialTheme.colorScheme.onErrorContainer
                        else -> MaterialTheme.colorScheme.onSurfaceVariant
                    },
                )
            }
        }
    }
}

@Composable
private fun BatteryHealthRow(
    healthPercent: Int?,
    cycles: Int?,
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text("Battery health", style = MaterialTheme.typography.titleSmall)
            if (healthPercent != null || cycles != null) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(
                        healthPercent?.let { "$it%" } ?: "—",
                        style = MaterialTheme.typography.bodyLarge,
                    )
                    Text(
                        cycles?.let { "$it cycles" } ?: "—",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            } else {
                Text(
                    "Not available — auto-populated when device is connected",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}
