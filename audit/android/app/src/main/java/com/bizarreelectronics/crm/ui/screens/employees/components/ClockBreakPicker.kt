package com.bizarreelectronics.crm.ui.screens.employees.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.theme.WarningAmber

/**
 * §14.3 L1626 — Clock break controls embedded in ClockInOutScreen.
 *
 * Shows when the user is clocked in:
 *   - On-break=false → "Start break" button
 *   - On-break=true  → running break-elapsed timer label + "End break" button
 *
 * API mapping:
 *   Start: POST /employees/:id/break-start
 *   End:   POST /employees/:id/break-end
 *
 * The VM handles the API calls and supplies [onBreak] + [breakElapsedLabel]
 * so this composable stays pure-UI.
 */
@Composable
fun ClockBreakPicker(
    onBreak: Boolean,
    breakElapsedLabel: String,     // e.g. "12:34" — formatted by VM
    isProcessing: Boolean,
    onStartBreak: () -> Unit,
    onEndBreak: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Card(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                text = "Break",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (onBreak) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Column {
                        Text(
                            text = "On break",
                            style = MaterialTheme.typography.bodyMedium,
                            color = WarningAmber,
                        )
                        if (breakElapsedLabel.isNotBlank()) {
                            Text(
                                text = breakElapsedLabel,
                                style = MaterialTheme.typography.headlineSmall,
                                color = WarningAmber,
                            )
                        }
                    }
                    Button(
                        onClick = onEndBreak,
                        enabled = !isProcessing,
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.primary,
                        ),
                    ) {
                        Text("End break")
                    }
                }
            } else {
                OutlinedButton(
                    onClick = onStartBreak,
                    enabled = !isProcessing,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Start break")
                }
            }
        }
    }
}
