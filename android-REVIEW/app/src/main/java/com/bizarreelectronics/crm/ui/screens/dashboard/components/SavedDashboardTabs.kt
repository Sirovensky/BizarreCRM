package com.bizarreelectronics.crm.ui.screens.dashboard.components

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.local.prefs.SavedDashboard

/**
 * §3.17 L607-L608 — Segmented-button row for switching between saved dashboard layouts.
 *
 * Always shows a "Default" chip. Each entry in [savedDashboards] is rendered as an
 * additional [FilterChip]. An "+ Add" chip at the end opens a name-entry dialog which
 * triggers [onAdd] with the chosen name.
 *
 * The chips scroll horizontally so long lists don't overflow on phone-width screens.
 *
 * @param savedDashboards  Named layout presets previously saved by the user.
 * @param activeName       Name of the currently active preset, or null for Default.
 * @param onSelect         Called when the user taps a named preset chip (null = Default).
 * @param onAdd            Called with the new name when the user confirms the "+ Add" dialog.
 * @param modifier         Optional modifier applied to the outer row.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SavedDashboardTabs(
    savedDashboards: List<SavedDashboard>,
    activeName: String?,
    onSelect: (name: String?) -> Unit,
    onAdd: (name: String) -> Unit,
    modifier: Modifier = Modifier,
) {
    var showAddDialog by remember { mutableStateOf(false) }

    Row(
        modifier = modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Default chip (always present)
        FilterChip(
            selected = activeName == null,
            onClick = { onSelect(null) },
            label = { Text("Default") },
            modifier = Modifier.semantics { contentDescription = "Switch to Default dashboard layout" },
            colors = FilterChipDefaults.filterChipColors(
                selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
                selectedLabelColor = MaterialTheme.colorScheme.onPrimaryContainer,
            ),
        )

        // User-saved preset chips
        savedDashboards.forEach { preset ->
            FilterChip(
                selected = activeName == preset.name,
                onClick = { onSelect(preset.name) },
                label = { Text(preset.name) },
                modifier = Modifier
                    .widthIn(max = 160.dp)
                    .semantics { contentDescription = "Switch to ${preset.name} dashboard layout" },
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
                    selectedLabelColor = MaterialTheme.colorScheme.onPrimaryContainer,
                ),
            )
        }

        // "+ Add" chip — opens the name dialog
        if (savedDashboards.size < 5) {
            FilterChip(
                selected = false,
                onClick = { showAddDialog = true },
                label = { Text("Add") },
                leadingIcon = {
                    Icon(
                        Icons.Default.Add,
                        contentDescription = null,
                    )
                },
                modifier = Modifier.semantics { contentDescription = "Save current layout as a new preset" },
            )
        }
    }

    // Name-entry dialog shown when the user taps "+ Add"
    if (showAddDialog) {
        SavedDashboardNameDialog(
            onConfirm = { name ->
                showAddDialog = false
                onAdd(name)
            },
            onDismiss = { showAddDialog = false },
        )
    }
}

/**
 * Dialog that lets the user name a new saved dashboard layout.
 *
 * Validates that the name is non-blank before enabling the Save button.
 *
 * @param onConfirm  Called with the trimmed name when the user confirms.
 * @param onDismiss  Called when the dialog is cancelled.
 */
@Composable
private fun SavedDashboardNameDialog(
    onConfirm: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    var name by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Save layout as…") },
        text = {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text("Layout name") },
                placeholder = { Text("e.g. Morning, End of day") },
                singleLine = true,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 8.dp),
            )
        },
        confirmButton = {
            TextButton(
                onClick = { onConfirm(name.trim()) },
                enabled = name.isNotBlank(),
            ) { Text("Save") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}
