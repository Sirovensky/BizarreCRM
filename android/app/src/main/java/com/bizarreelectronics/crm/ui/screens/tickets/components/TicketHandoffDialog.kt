package com.bizarreelectronics.crm.ui.screens.tickets.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * Represents an employee that a ticket can be transferred to.
 */
data class HandoffEmployee(
    val id: Long,
    val displayName: String,
    val role: String?,
)

/**
 * L722 — Transfer/Handoff dialog.
 *
 * Requires:
 * - A non-blank reason (auto-logged as an internal note by the server).
 * - An employee selection from [employees].
 *
 * On confirm, calls [onConfirm] with (employeeId, reason). The caller wires
 * this to PUT /tickets/:id with [assigned_to] + the reason posted as a note.
 *
 * L723 (location transfer) is exposed via the optional [locations] + [onConfirmLocation]
 * parameters. If [locations] is empty the location section is hidden.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TicketHandoffDialog(
    currentAssigneeName: String?,
    employees: List<HandoffEmployee>,
    locations: List<String> = emptyList(),
    onConfirm: (employeeId: Long, reason: String) -> Unit,
    onConfirmLocation: ((location: String) -> Unit)? = null,
    onDismiss: () -> Unit,
) {
    var selectedEmployee by remember { mutableStateOf<HandoffEmployee?>(null) }
    var employeeDropdownExpanded by remember { mutableStateOf(false) }
    var reason by remember { mutableStateOf("") }

    var selectedLocation by remember { mutableStateOf<String?>(null) }
    var locationDropdownExpanded by remember { mutableStateOf(false) }

    val canConfirm = selectedEmployee != null && reason.isNotBlank()

    AlertDialog(
        onDismissRequest = onDismiss,
        icon = {
            Icon(Icons.Default.SwapHoriz, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
        },
        title = { Text("Transfer Ticket") },
        text = {
            Column(modifier = Modifier.fillMaxWidth()) {
                if (currentAssigneeName != null) {
                    Text(
                        "Currently assigned to: $currentAssigneeName",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(modifier = Modifier.height(12.dp))
                }

                // Employee picker
                ExposedDropdownMenuBox(
                    expanded = employeeDropdownExpanded,
                    onExpandedChange = { employeeDropdownExpanded = it },
                ) {
                    OutlinedTextField(
                        value = selectedEmployee?.displayName ?: "",
                        onValueChange = {},
                        readOnly = true,
                        label = { Text("Assign to *") },
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = employeeDropdownExpanded) },
                        modifier = Modifier
                            .menuAnchor()
                            .fillMaxWidth(),
                    )
                    ExposedDropdownMenu(
                        expanded = employeeDropdownExpanded,
                        onDismissRequest = { employeeDropdownExpanded = false },
                    ) {
                        employees.forEach { emp ->
                            DropdownMenuItem(
                                text = {
                                    Column {
                                        Text(emp.displayName, style = MaterialTheme.typography.bodyMedium)
                                        if (emp.role != null) {
                                            Text(
                                                emp.role,
                                                style = MaterialTheme.typography.bodySmall,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                            )
                                        }
                                    }
                                },
                                onClick = {
                                    selectedEmployee = emp
                                    employeeDropdownExpanded = false
                                },
                            )
                        }
                    }
                }

                Spacer(modifier = Modifier.height(12.dp))

                // Required reason
                OutlinedTextField(
                    value = reason,
                    onValueChange = { reason = it },
                    label = { Text("Reason for transfer *") },
                    placeholder = { Text("e.g. Specialist needed, shift change…") },
                    modifier = Modifier.fillMaxWidth(),
                    minLines = 2,
                    maxLines = 4,
                    isError = reason.isBlank() && selectedEmployee != null,
                    supportingText = if (reason.isBlank() && selectedEmployee != null) {
                        { Text("Reason is required") }
                    } else null,
                )

                // Location picker (L723 — multi-location tenant only)
                if (locations.isNotEmpty() && onConfirmLocation != null) {
                    Spacer(modifier = Modifier.height(12.dp))
                    ExposedDropdownMenuBox(
                        expanded = locationDropdownExpanded,
                        onExpandedChange = { locationDropdownExpanded = it },
                    ) {
                        OutlinedTextField(
                            value = selectedLocation ?: "",
                            onValueChange = {},
                            readOnly = true,
                            label = { Text("Transfer to location (optional)") },
                            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = locationDropdownExpanded) },
                            modifier = Modifier
                                .menuAnchor()
                                .fillMaxWidth(),
                        )
                        ExposedDropdownMenu(
                            expanded = locationDropdownExpanded,
                            onDismissRequest = { locationDropdownExpanded = false },
                        ) {
                            locations.forEach { loc ->
                                DropdownMenuItem(
                                    text = { Text(loc) },
                                    onClick = {
                                        selectedLocation = loc
                                        locationDropdownExpanded = false
                                    },
                                )
                            }
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    val emp = selectedEmployee ?: return@TextButton
                    onConfirm(emp.id, reason.trim())
                    // Also trigger location transfer if selected
                    selectedLocation?.let { loc -> onConfirmLocation?.invoke(loc) }
                },
                enabled = canConfirm,
            ) {
                Text("Transfer")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        },
    )
}
