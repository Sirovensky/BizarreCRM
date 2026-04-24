package com.bizarreelectronics.crm.ui.screens.leads.components

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Message
import androidx.compose.material.icons.filled.OpenInNew
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics

/**
 * Context menu shown on long-press of a lead row (ActionPlan §9 L1378).
 *
 * Items: Open, Call, SMS, Email, Convert to customer, Schedule appointment, Delete.
 * Destructive items (Delete, Convert) are shown in error color.
 *
 * The caller is responsible for:
 *  - Wrapping the anchor composable in a `combinedClickable(onLongClick = { expanded = true })`
 *  - Providing the [expanded] / [onDismiss] state
 *  - Implementing each action callback
 *
 * @param expanded              Whether the menu is currently open.
 * @param onDismiss             Called when the menu should close.
 * @param onOpen                Navigate to lead detail.
 * @param onCall                Initiate a phone call.
 * @param onSms                 Open SMS composer.
 * @param onEmail               Open email composer.
 * @param onConvertToCustomer   Convert lead → customer.
 * @param onScheduleAppointment Navigate to appointment create.
 * @param onDelete              Trigger delete confirm dialog.
 * @param hasPhone              Whether the lead has a phone number (gates Call/SMS).
 * @param hasEmail              Whether the lead has an email address (gates Email).
 */
@Composable
fun LeadContextMenu(
    expanded: Boolean,
    onDismiss: () -> Unit,
    onOpen: () -> Unit,
    onCall: () -> Unit,
    onSms: () -> Unit,
    onEmail: () -> Unit,
    onConvertToCustomer: () -> Unit,
    onScheduleAppointment: () -> Unit,
    onDelete: () -> Unit,
    hasPhone: Boolean,
    hasEmail: Boolean,
    modifier: Modifier = Modifier,
) {
    DropdownMenu(
        expanded = expanded,
        onDismissRequest = onDismiss,
        modifier = modifier,
    ) {
        DropdownMenuItem(
            text = { Text("Open") },
            leadingIcon = {
                Icon(Icons.Default.OpenInNew, contentDescription = null)
            },
            onClick = {
                onDismiss()
                onOpen()
            },
            modifier = Modifier.semantics { contentDescription = "Open lead detail" },
        )

        if (hasPhone) {
            DropdownMenuItem(
                text = { Text("Call") },
                leadingIcon = {
                    Icon(Icons.Default.Call, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                },
                onClick = {
                    onDismiss()
                    onCall()
                },
                modifier = Modifier.semantics { contentDescription = "Call lead" },
            )

            DropdownMenuItem(
                text = { Text("SMS") },
                leadingIcon = {
                    Icon(Icons.Default.Message, contentDescription = null, tint = MaterialTheme.colorScheme.secondary)
                },
                onClick = {
                    onDismiss()
                    onSms()
                },
                modifier = Modifier.semantics { contentDescription = "Send SMS to lead" },
            )
        }

        if (hasEmail) {
            DropdownMenuItem(
                text = { Text("Email") },
                leadingIcon = {
                    Icon(Icons.Default.Email, contentDescription = null, tint = MaterialTheme.colorScheme.tertiary)
                },
                onClick = {
                    onDismiss()
                    onEmail()
                },
                modifier = Modifier.semantics { contentDescription = "Email lead" },
            )
        }

        DropdownMenuItem(
            text = {
                Text(
                    "Convert to customer",
                    color = MaterialTheme.colorScheme.primary,
                )
            },
            leadingIcon = {
                Icon(Icons.Default.PersonAdd, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
            },
            onClick = {
                onDismiss()
                onConvertToCustomer()
            },
            modifier = Modifier.semantics { contentDescription = "Convert lead to customer" },
        )

        DropdownMenuItem(
            text = { Text("Schedule appointment") },
            leadingIcon = {
                Icon(Icons.Default.CalendarMonth, contentDescription = null)
            },
            onClick = {
                onDismiss()
                onScheduleAppointment()
            },
            modifier = Modifier.semantics { contentDescription = "Schedule appointment for lead" },
        )

        DropdownMenuItem(
            text = {
                Text(
                    "Delete",
                    color = MaterialTheme.colorScheme.error,
                )
            },
            leadingIcon = {
                Icon(Icons.Default.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error)
            },
            onClick = {
                onDismiss()
                onDelete()
            },
            modifier = Modifier.semantics { contentDescription = "Delete lead" },
        )
    }
}
