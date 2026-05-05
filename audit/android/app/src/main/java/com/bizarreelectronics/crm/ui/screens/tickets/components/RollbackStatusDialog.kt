package com.bizarreelectronics.crm.ui.screens.tickets.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
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
import com.bizarreelectronics.crm.data.remote.dto.TicketStatusItem

/**
 * plan:L793 — RollbackStatusDialog (admin-only)
 *
 * Shown from the ticket-detail overflow menu "Rollback status" action.
 * Requires:
 *   - A mandatory reason (non-empty text field).
 *   - A target status selected from [availableStatuses] (previous states dropdown).
 *
 * On confirm, calls [onConfirm] with the selected status id and the reason string.
 * The ViewModel then POSTs to `POST /tickets/:id/status-rollback` with `{statusId, reason}`.
 * A 404 on that endpoint is tolerated (the caller handles it gracefully).
 *
 * @param currentStatusName   Display name of the current status (shown as subtitle).
 * @param availableStatuses   Candidate rollback targets. Typically the previous states
 *                            in the default transition graph (from [TicketStateMachine.rollbackCandidates]).
 * @param onConfirm           Invoked with (targetStatusId, reason) when user confirms.
 * @param onDismiss           Invoked when user cancels.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RollbackStatusDialog(
    currentStatusName: String?,
    availableStatuses: List<TicketStatusItem>,
    onConfirm: (targetStatusId: Long, reason: String) -> Unit,
    onDismiss: () -> Unit,
) {
    var selectedStatus by remember { mutableStateOf<TicketStatusItem?>(null) }
    var reason by remember { mutableStateOf("") }
    var dropdownExpanded by remember { mutableStateOf(false) }

    val canConfirm = selectedStatus != null && reason.isNotBlank()

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Rollback status") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                if (!currentStatusName.isNullOrBlank()) {
                    Text(
                        "Current status: $currentStatusName",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }

                // Target status dropdown
                ExposedDropdownMenuBox(
                    expanded = dropdownExpanded,
                    onExpandedChange = { dropdownExpanded = it },
                ) {
                    OutlinedTextField(
                        value = selectedStatus?.name ?: "",
                        onValueChange = {},
                        readOnly = true,
                        label = { Text("Roll back to") },
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = dropdownExpanded) },
                        modifier = Modifier
                            .fillMaxWidth()
                            .menuAnchor(),
                    )
                    ExposedDropdownMenu(
                        expanded = dropdownExpanded,
                        onDismissRequest = { dropdownExpanded = false },
                    ) {
                        if (availableStatuses.isEmpty()) {
                            DropdownMenuItem(
                                text = { Text("No previous states available") },
                                onClick = { dropdownExpanded = false },
                                enabled = false,
                            )
                        } else {
                            availableStatuses.forEach { status ->
                                DropdownMenuItem(
                                    text = { Text(status.name) },
                                    onClick = {
                                        selectedStatus = status
                                        dropdownExpanded = false
                                    },
                                )
                            }
                        }
                    }
                }

                Spacer(modifier = Modifier.height(4.dp))

                // Mandatory reason field
                OutlinedTextField(
                    value = reason,
                    onValueChange = { reason = it },
                    label = { Text("Reason (required)") },
                    placeholder = { Text("Explain why this rollback is needed") },
                    singleLine = false,
                    minLines = 2,
                    maxLines = 4,
                    modifier = Modifier.fillMaxWidth(),
                    isError = reason.isBlank(),
                    supportingText = if (reason.isBlank()) {
                        { Text("Reason is required for audit trail") }
                    } else {
                        null
                    },
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    val target = selectedStatus ?: return@TextButton
                    onConfirm(target.id, reason.trim())
                },
                enabled = canConfirm,
            ) {
                Text("Rollback")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}
