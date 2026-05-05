package com.bizarreelectronics.crm.ui.screens.appointments.components

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * Reminder offset picker (L1429).
 *
 * SegmentedButton: Off / 15 min / 1 h / 1 day / Custom.
 * When Custom is selected, an OutlinedTextField appears for minute entry.
 * Calls [onOffsetChange] with the resolved minute value (null = off).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReminderOffsetPicker(
    currentOffsetMinutes: Int?,
    onOffsetChange: (Int?) -> Unit,
    modifier: Modifier = Modifier,
) {
    data class Preset(val label: String, val minutes: Int?)

    val presets = listOf(
        Preset("Off", null),
        Preset("15 min", 15),
        Preset("1 h", 60),
        Preset("1 day", 1440),
        Preset("Custom", -1),
    )

    // Determine which preset is active
    val activePreset = presets.firstOrNull { p ->
        when {
            p.minutes == null && currentOffsetMinutes == null -> true
            p.minutes == -1 -> false  // custom checked below
            p.minutes == currentOffsetMinutes -> true
            else -> false
        }
    } ?: presets.last() // Custom

    val isCustom = activePreset.minutes == -1 ||
        (currentOffsetMinutes != null && presets.none { it.minutes == currentOffsetMinutes && it.minutes != null && it.minutes != -1 })

    var customText by remember(currentOffsetMinutes) {
        mutableStateOf(
            if (isCustom) (currentOffsetMinutes?.toString() ?: "") else "",
        )
    }

    Column(modifier = modifier) {
        Text(
            text = "Reminder",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(bottom = 6.dp),
        )

        SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
            presets.forEachIndexed { idx, preset ->
                val selected = when {
                    preset.minutes == -1 -> isCustom
                    preset.minutes == null -> currentOffsetMinutes == null
                    else -> currentOffsetMinutes == preset.minutes && !isCustom
                }
                SegmentedButton(
                    selected = selected,
                    onClick = {
                        if (preset.minutes == -1) {
                            // Enter custom mode: keep current value so user can edit
                            customText = currentOffsetMinutes?.toString() ?: ""
                            onOffsetChange(currentOffsetMinutes)
                        } else {
                            onOffsetChange(preset.minutes)
                        }
                    },
                    shape = SegmentedButtonDefaults.itemShape(index = idx, count = presets.size),
                    label = { Text(preset.label, style = MaterialTheme.typography.labelSmall) },
                    icon = {},
                )
            }
        }

        if (isCustom) {
            Spacer(modifier = Modifier.height(8.dp))
            OutlinedTextField(
                value = customText,
                onValueChange = { txt ->
                    customText = txt.filter { it.isDigit() }
                    val minutes = customText.toIntOrNull()
                    onOffsetChange(minutes)
                },
                label = { Text("Minutes before") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
                suffix = { Text("min") },
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                    keyboardType = androidx.compose.ui.text.input.KeyboardType.Number,
                ),
            )
        }
    }
}
