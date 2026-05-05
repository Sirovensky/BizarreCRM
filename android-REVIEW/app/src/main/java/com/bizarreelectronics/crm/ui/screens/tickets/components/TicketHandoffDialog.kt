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
 * §4.9 L770 — Structured handoff reason category.
 *
 * The [OTHER] variant requires a non-blank free-text [customText] to be provided
 * by the user before the dialog can be confirmed.
 */
enum class HandoffReason(val label: String) {
    SHIFT_CHANGE("Shift change"),
    ESCALATION("Escalation"),
    OUT_OF_EXPERTISE("Out of expertise"),
    OTHER("Other…"),
    ;

    /**
     * True when this variant requires a supplementary free-text field.
     */
    val requiresFreeText: Boolean get() = this == OTHER
}

/**
 * L722 — Transfer/Handoff dialog.
 *
 * Requires:
 * - A structured [HandoffReason] selection (mandatory, §4.9 L770).
 * - When [HandoffReason.OTHER] is selected, a non-blank free-text supplement.
 * - An employee selection from [employees].
 *
 * On confirm, calls [onConfirm] with (employeeId, reason). The reason string is
 * the enum label, or the free-text value when [HandoffReason.OTHER] is chosen.
 * The caller wires this to PUT /tickets/:id with `assigned_to` + posts the
 * reason as an internal note. The server also sends an FCM push to the receiving
 * technician.
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

    // §4.9 L770 — reason dropdown
    var selectedReason by remember { mutableStateOf<HandoffReason?>(null) }
    var reasonDropdownExpanded by remember { mutableStateOf(false) }
    var freeTextReason by remember { mutableStateOf("") }

    var selectedLocation by remember { mutableStateOf<String?>(null) }
    var locationDropdownExpanded by remember { mutableStateOf(false) }

    // Reason is valid when a category is selected AND (not OTHER, or free-text is filled)
    val reasonIsValid = selectedReason != null &&
            (selectedReason != HandoffReason.OTHER || freeTextReason.isNotBlank())

    val canConfirm = selectedEmployee != null && reasonIsValid

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

                // §4.9 L770 — structured reason dropdown
                ExposedDropdownMenuBox(
                    expanded = reasonDropdownExpanded,
                    onExpandedChange = { reasonDropdownExpanded = it },
                ) {
                    OutlinedTextField(
                        value = selectedReason?.label ?: "",
                        onValueChange = {},
                        readOnly = true,
                        label = { Text("Reason *") },
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = reasonDropdownExpanded) },
                        isError = selectedReason == null && selectedEmployee != null,
                        supportingText = if (selectedReason == null && selectedEmployee != null) {
                            { Text("Reason is required") }
                        } else null,
                        modifier = Modifier
                            .menuAnchor()
                            .fillMaxWidth(),
                    )
                    ExposedDropdownMenu(
                        expanded = reasonDropdownExpanded,
                        onDismissRequest = { reasonDropdownExpanded = false },
                    ) {
                        HandoffReason.entries.forEach { reason ->
                            DropdownMenuItem(
                                text = { Text(reason.label, style = MaterialTheme.typography.bodyMedium) },
                                onClick = {
                                    selectedReason = reason
                                    reasonDropdownExpanded = false
                                    if (!reason.requiresFreeText) freeTextReason = ""
                                },
                            )
                        }
                    }
                }

                // §4.9 L770 — free-text supplement shown only for OTHER
                if (selectedReason == HandoffReason.OTHER) {
                    Spacer(modifier = Modifier.height(8.dp))
                    OutlinedTextField(
                        value = freeTextReason,
                        onValueChange = { freeTextReason = it },
                        label = { Text("Please specify *") },
                        placeholder = { Text("Describe the reason…") },
                        modifier = Modifier.fillMaxWidth(),
                        minLines = 2,
                        maxLines = 4,
                        isError = freeTextReason.isBlank(),
                        supportingText = if (freeTextReason.isBlank()) {
                            { Text("Please describe the reason") }
                        } else null,
                    )
                }

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
                    val reasonStr = if (selectedReason == HandoffReason.OTHER) {
                        freeTextReason.trim()
                    } else {
                        selectedReason?.label ?: return@TextButton
                    }
                    onConfirm(emp.id, reasonStr)
                    // Also trigger location transfer if selected (L723)
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
