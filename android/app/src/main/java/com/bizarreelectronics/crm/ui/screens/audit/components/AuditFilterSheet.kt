package com.bizarreelectronics.crm.ui.screens.audit.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Button
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

// ─── Filter state ─────────────────────────────────────────────────────────────

data class AuditFilter(
    val actor: String = "",
    val entityType: String = "",
    val action: String = "",
    val from: String = "",
    val to: String = "",
)

private val ENTITY_TYPES = listOf("ticket", "customer", "invoice", "inventory", "user", "settings")
private val ACTIONS = listOf("create", "update", "delete", "login", "logout", "view")

// ─── Bottom sheet ─────────────────────────────────────────────────────────────

/**
 * §52 — Bottom-sheet filter panel for the audit log.
 *
 * Exposes: actor text field, entity-type chip group, action chip group, and
 * from/to date-range text fields (ISO-8601). Apply/Clear buttons.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun AuditFilterSheet(
    current: AuditFilter,
    onApply: (AuditFilter) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    var draft by remember(current) { mutableStateOf(current) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("Filter audit log", style = androidx.compose.material3.MaterialTheme.typography.titleMedium)

            OutlinedTextField(
                value = draft.actor,
                onValueChange = { draft = draft.copy(actor = it) },
                label = { Text("Actor (username)") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )

            Text("Entity type", style = androidx.compose.material3.MaterialTheme.typography.labelMedium)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ENTITY_TYPES.forEach { type ->
                    FilterChip(
                        selected = draft.entityType == type,
                        onClick = {
                            draft = draft.copy(entityType = if (draft.entityType == type) "" else type)
                        },
                        label = { Text(type) },
                    )
                }
            }

            Text("Action", style = androidx.compose.material3.MaterialTheme.typography.labelMedium)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ACTIONS.forEach { action ->
                    FilterChip(
                        selected = draft.action == action,
                        onClick = {
                            draft = draft.copy(action = if (draft.action == action) "" else action)
                        },
                        label = { Text(action) },
                    )
                }
            }

            // BUGHUNT-2026-05-18: free-text dates replaced with DatePickers —
            // typed dates were silently rejected by the audit filter when
            // formatted slightly differently.
            DateField(
                value = draft.from,
                onChange = { draft = draft.copy(from = it) },
                label = "From",
            )
            DateField(
                value = draft.to,
                onChange = { draft = draft.copy(to = it) },
                label = "To",
            )

            Spacer(Modifier.height(4.dp))

            Button(
                onClick = { onApply(draft) },
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Apply filters") }

            TextButton(
                onClick = { onApply(AuditFilter()) },
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Clear all filters") }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DateField(value: String, onChange: (String) -> Unit, label: String) {
    var showPicker by remember { mutableStateOf(false) }
    if (showPicker) {
        val initialMillis = value.takeIf { it.isNotBlank() }?.let {
            runCatching {
                java.time.LocalDate.parse(it)
                    .atStartOfDay(java.time.ZoneId.systemDefault())
                    .toInstant().toEpochMilli()
            }.getOrNull()
        } ?: System.currentTimeMillis()
        val pickerState = rememberDatePickerState(initialSelectedDateMillis = initialMillis)
        DatePickerDialog(
            onDismissRequest = { showPicker = false },
            confirmButton = {
                TextButton(onClick = {
                    pickerState.selectedDateMillis?.let { ms ->
                        val iso = java.time.Instant.ofEpochMilli(ms)
                            .atZone(java.time.ZoneId.systemDefault())
                            .toLocalDate().toString()
                        onChange(iso)
                    }
                    showPicker = false
                }) { Text("OK") }
            },
            dismissButton = {
                TextButton(onClick = { showPicker = false }) { Text("Cancel") }
            },
        ) { DatePicker(state = pickerState) }
    }
    OutlinedTextField(
        value = value,
        onValueChange = {},
        readOnly = true,
        label = { Text(label) },
        placeholder = { Text("Any") },
        singleLine = true,
        modifier = Modifier
            .fillMaxWidth()
            .clickable { showPicker = true },
        trailingIcon = {
            if (value.isNotBlank()) {
                IconButton(onClick = { onChange("") }) {
                    Icon(Icons.Default.Close, contentDescription = "Clear $label")
                }
            }
        },
    )
}
