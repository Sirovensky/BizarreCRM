package com.bizarreelectronics.crm.ui.screens.appointments

import android.widget.Toast
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Login
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.screens.appointments.components.ReminderOffsetPicker
import com.bizarreelectronics.crm.util.CalendarMirror

/**
 * Appointment detail screen (L1430–1444).
 *
 * Features:
 *  - Quick action chips: Confirm / Reschedule / Cancel / No-show (L1430)
 *  - Send reminder button (L1431)
 *  - Reminder offset picker (L1429)
 *  - Add to Calendar via intent (L1437)
 *  - Cancel dialog with "Notify customer?" prompt (L1443)
 *  - No-show single tap (L1444)
 *  - Conflict warning banner (L1438)
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppointmentDetailScreen(
    onBack: () -> Unit,
    onNavigateToCustomer: ((Long) -> Unit)? = null,
    onNavigateToTicket: ((Long) -> Unit)? = null,
    onNavigateToEstimate: ((Long) -> Unit)? = null,
    onNavigateToLead: ((Long) -> Unit)? = null,
    viewModel: AppointmentDetailViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current

    // Toast
    LaunchedEffect(state.toastMessage) {
        val msg = state.toastMessage
        if (!msg.isNullOrBlank()) {
            Toast.makeText(context, msg, Toast.LENGTH_SHORT).show()
            viewModel.clearToast()
        }
    }

    // Navigate back after cancel success
    LaunchedEffect(state.navigateBack) {
        if (state.navigateBack) {
            viewModel.consumeNavigateBack()
            onBack()
        }
    }

    // Cancel dialog
    if (state.showCancelDialog) {
        CancelDialog(
            onNotify = { viewModel.confirmCancel(notifyCustomer = true) },
            onSkip = { viewModel.confirmCancel(notifyCustomer = false) },
            onDismiss = viewModel::dismissCancelDialog,
        )
    }

    // Recurring-edit scope dialog (10.3 / item 5)
    if (state.showRecurringEditDialog) {
        RecurringEditScopeDialog(
            selectedScope = state.pendingRecurringScope,
            onScopeChange = viewModel::updateRecurringScope,
            onConfirm = viewModel::confirmRecurringEdit,
            onDismiss = viewModel::dismissRecurringEditDialog,
        )
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = state.appointment?.customerName ?: "Appointment",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        when {
            state.isLoading -> BrandSkeleton(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .padding(16.dp),
            )
            state.error != null -> ErrorState(message = state.error!!)
            state.appointment != null -> {
                val appt = state.appointment!!
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentPadding = PaddingValues(bottom = 80.dp),
                ) {
                    // Conflict warning banner (L1438)
                    state.conflictWarning?.let { warning ->
                        item {
                            ConflictWarningBanner(
                                message = warning,
                                onDismiss = viewModel::clearConflict,
                            )
                        }
                    }

                    // Quick action chips header row (L1430)
                    item {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .horizontalScroll(rememberScrollState())
                                .padding(horizontal = 16.dp, vertical = 12.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            if (appt.status != "confirmed") {
                                SuggestionChip(
                                    onClick = viewModel::markConfirmed,
                                    label = { Text("Mark Confirmed") },
                                    icon = { Icon(Icons.Default.CheckCircle, null, Modifier.size(18.dp)) },
                                )
                            }
                            SuggestionChip(
                                onClick = { /* navigate to reschedule */ },
                                label = { Text("Reschedule") },
                                icon = { Icon(Icons.Default.Schedule, null, Modifier.size(18.dp)) },
                            )
                            SuggestionChip(
                                onClick = viewModel::requestCancel,
                                label = { Text("Cancel") },
                                icon = { Icon(Icons.Default.Cancel, null, Modifier.size(18.dp)) },
                                colors = SuggestionChipDefaults.suggestionChipColors(
                                    containerColor = MaterialTheme.colorScheme.errorContainer,
                                    labelColor = MaterialTheme.colorScheme.onErrorContainer,
                                ),
                            )
                            if (appt.status != "no_show") {
                                SuggestionChip(
                                    onClick = viewModel::markNoShow,
                                    label = { Text("No-show") },
                                    icon = { Icon(Icons.Default.PersonOff, null, Modifier.size(18.dp)) },
                                )
                            }
                        }
                    }

                    // §10.6 Check-in / check-out card
                    item {
                        CheckInCard(
                            status = appt.status,
                            checkedInAt = appt.checkedInAt,
                            checkedOutAt = appt.checkedOutAt,
                            linkedTicketId = appt.linkedTicketId,
                            isSaving = state.isSaving,
                            onCheckIn = viewModel::markCheckedIn,
                            onCheckOut = viewModel::markCheckedOut,
                        )
                    }

                    // Customer card (10.2)
                    item {
                        CustomerCard(
                            name = appt.customerName ?: "Unknown customer",
                            phone = appt.customerPhone,
                            onClick = appt.customerId?.let { cid ->
                                { onNavigateToCustomer?.invoke(cid) }
                            },
                        )
                    }

                    // Linked entity rows (10.2)
                    appt.linkedTicketId?.let { ticketId ->
                        item {
                            LinkedEntityRow(
                                icon = Icons.Default.ConfirmationNumber,
                                label = "Ticket #$ticketId",
                                secondary = appt.linkedTicketStatus ?: "",
                                onClick = { onNavigateToTicket?.invoke(ticketId) },
                            )
                        }
                    }
                    appt.linkedEstimateId?.let { estId ->
                        item {
                            LinkedEntityRow(
                                icon = Icons.Default.Receipt,
                                label = "Estimate #$estId",
                                secondary = appt.linkedEstimateTotal?.let { "\$${"%.2f".format(it)}" } ?: "",
                                onClick = { onNavigateToEstimate?.invoke(estId) },
                            )
                        }
                    }
                    appt.linkedLeadId?.let { leadId ->
                        item {
                            LinkedEntityRow(
                                icon = Icons.Default.PersonSearch,
                                label = "Lead #$leadId",
                                secondary = appt.linkedLeadStage ?: "",
                                onClick = { onNavigateToLead?.invoke(leadId) },
                            )
                        }
                    }

                    // Detail info card
                    item {
                        Card(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp, vertical = 8.dp),
                        ) {
                            Column(modifier = Modifier.padding(16.dp)) {
                                DetailRow(label = "Technician", value = appt.employeeName ?: "—")
                                DetailRow(label = "Type", value = appt.type ?: "—")
                                DetailRow(label = "Start", value = appt.startTime ?: "—")
                                DetailRow(label = "Duration", value = appt.durationMinutes?.let { "${it}min" } ?: "—")
                                DetailRow(label = "Location", value = appt.location ?: "—")
                                DetailRow(label = "Status", value = appt.status ?: "scheduled")
                                appt.rrule?.takeIf { it.isNotBlank() }?.let {
                                    DetailRow(label = "Recurrence", value = it)
                                }
                                appt.notes?.takeIf { it.isNotBlank() }?.let {
                                    Spacer(modifier = Modifier.height(8.dp))
                                    Text(
                                        text = "Notes",
                                        style = MaterialTheme.typography.labelMedium,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                    Text(text = it, style = MaterialTheme.typography.bodyMedium)
                                }
                            }
                        }
                    }

                    // Reminder offset picker (L1429)
                    item {
                        Card(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp, vertical = 8.dp),
                        ) {
                            Column(modifier = Modifier.padding(16.dp)) {
                                ReminderOffsetPicker(
                                    currentOffsetMinutes = appt.reminderOffsetMinutes,
                                    onOffsetChange = viewModel::setReminderOffset,
                                    modifier = Modifier.fillMaxWidth(),
                                )
                            }
                        }
                    }

                    // Actions row: Send Reminder + Add to Calendar (L1431, L1437)
                    item {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp, vertical = 8.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            OutlinedButton(
                                onClick = viewModel::sendReminder,
                                modifier = Modifier.weight(1f),
                            ) {
                                Icon(Icons.Default.Notifications, null, Modifier.size(18.dp))
                                Spacer(Modifier.width(4.dp))
                                Text("Send Reminder")
                            }
                            Button(
                                onClick = { CalendarMirror.addToCalendar(context, appt) },
                                modifier = Modifier.weight(1f),
                            ) {
                                Icon(Icons.Default.CalendarToday, null, Modifier.size(18.dp))
                                Spacer(Modifier.width(4.dp))
                                Text("Add to Calendar")
                            }
                        }
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// §10.6 Check-in / check-out card
// ---------------------------------------------------------------------------

/**
 * Displays a contextual card allowing staff to stamp "Customer arrived" (check-in)
 * and "Customer departed" (check-out) during the appointment lifecycle.
 *
 * State transitions:
 *   scheduled | confirmed → show "Customer Arrived" button
 *   checked_in            → show timestamp + "Customer Departed" button
 *   completed             → show both timestamps as read-only confirmation
 *   cancelled / no_show   → card hidden (nothing actionable)
 *
 * If the appointment is linked to a ticket, check-in also triggers a bench
 * timer start on that ticket (see [AppointmentDetailViewModel.markCheckedIn]).
 */
@Composable
private fun CheckInCard(
    status: String?,
    checkedInAt: String?,
    checkedOutAt: String?,
    linkedTicketId: Long?,
    isSaving: Boolean,
    onCheckIn: () -> Unit,
    onCheckOut: () -> Unit,
) {
    // Hide card for terminal non-actionable statuses.
    if (status in listOf("cancelled", "no_show")) return

    val haptic = LocalHapticFeedback.current

    // Derive display state from status and timestamps.
    val isCheckedIn = status == "checked_in" || (!checkedInAt.isNullOrBlank() && checkedOutAt.isNullOrBlank())
    val isCompleted = status == "completed" || !checkedOutAt.isNullOrBlank()
    val canCheckIn  = !isCheckedIn && !isCompleted
    val canCheckOut = isCheckedIn && !isCompleted

    // Container color: green-ish when checked-in, secondary otherwise.
    val containerColor = when {
        isCompleted  -> MaterialTheme.colorScheme.secondaryContainer
        isCheckedIn  -> MaterialTheme.colorScheme.tertiaryContainer
        else         -> MaterialTheme.colorScheme.surfaceVariant
    }
    val onContainerColor = when {
        isCompleted  -> MaterialTheme.colorScheme.onSecondaryContainer
        isCheckedIn  -> MaterialTheme.colorScheme.onTertiaryContainer
        else         -> MaterialTheme.colorScheme.onSurfaceVariant
    }

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .semantics { contentDescription = "Customer check-in status: ${status ?: "scheduled"}" },
        colors = CardDefaults.cardColors(containerColor = containerColor),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // Header row
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                val headerIcon = when {
                    isCompleted -> Icons.Default.CheckCircle
                    isCheckedIn -> Icons.Default.Person
                    else        -> Icons.Default.PersonOutline
                }
                Icon(
                    imageVector = headerIcon,
                    contentDescription = null,
                    tint = onContainerColor,
                    modifier = Modifier.size(20.dp),
                )
                Text(
                    text = when {
                        isCompleted -> "Appointment complete"
                        isCheckedIn -> "Customer is here"
                        else        -> "Waiting for customer"
                    },
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = onContainerColor,
                )
            }

            // Timestamp rows
            if (!checkedInAt.isNullOrBlank()) {
                TimestampRow(
                    label = "Arrived",
                    isoTimestamp = checkedInAt,
                    tint = onContainerColor,
                )
            }
            if (!checkedOutAt.isNullOrBlank()) {
                TimestampRow(
                    label = "Departed",
                    isoTimestamp = checkedOutAt,
                    tint = onContainerColor,
                )
            }

            // Linked-ticket notice
            if (linkedTicketId != null && canCheckIn) {
                Text(
                    text = "Check-in will start the bench timer on ticket #$linkedTicketId",
                    style = MaterialTheme.typography.bodySmall,
                    color = onContainerColor.copy(alpha = 0.75f),
                )
            }

            // Action buttons
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (canCheckIn) {
                    Button(
                        onClick = {
                            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                            onCheckIn()
                        },
                        enabled = !isSaving,
                        modifier = Modifier
                            .weight(1f)
                            .semantics { contentDescription = "Mark customer arrived" },
                    ) {
                        if (isSaving) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(16.dp),
                                strokeWidth = 2.dp,
                                color = MaterialTheme.colorScheme.onPrimary,
                            )
                        } else {
                            Icon(Icons.AutoMirrored.Filled.Login, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.width(6.dp))
                            Text("Customer Arrived")
                        }
                    }
                }
                if (canCheckOut) {
                    Button(
                        onClick = {
                            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                            onCheckOut()
                        },
                        enabled = !isSaving,
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.secondary,
                        ),
                        modifier = Modifier
                            .weight(1f)
                            .semantics { contentDescription = "Mark customer departed" },
                    ) {
                        if (isSaving) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(16.dp),
                                strokeWidth = 2.dp,
                                color = MaterialTheme.colorScheme.onSecondary,
                            )
                        } else {
                            Icon(Icons.AutoMirrored.Filled.Logout, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.width(6.dp))
                            Text("Customer Departed")
                        }
                    }
                }
            }
        }
    }
}

/**
 * Renders a single labelled timestamp row (e.g. "Arrived · 2:34 PM").
 * Formats the ISO-8601 string to a human-readable time; falls back to the raw
 * string when parsing fails.
 */
@Composable
private fun TimestampRow(
    label: String,
    isoTimestamp: String,
    tint: androidx.compose.ui.graphics.Color,
) {
    val displayTime = remember(isoTimestamp) {
        runCatching {
            val dt = java.time.LocalDateTime.parse(
                isoTimestamp,
                java.time.format.DateTimeFormatter.ISO_DATE_TIME,
            )
            dt.format(java.time.format.DateTimeFormatter.ofPattern("h:mm a"))
        }.getOrElse { isoTimestamp }
    }
    Row(
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            Icons.Default.Schedule,
            contentDescription = null,
            tint = tint.copy(alpha = 0.7f),
            modifier = Modifier.size(14.dp),
        )
        Text(
            text = "$label · $displayTime",
            style = MaterialTheme.typography.bodySmall,
            color = tint.copy(alpha = 0.85f),
        )
    }
}

// ---------------------------------------------------------------------------
// Cancel dialog (L1443)
// ---------------------------------------------------------------------------

@Composable
private fun CancelDialog(
    onNotify: () -> Unit,
    onSkip: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Cancel appointment?") },
        text = { Text("Would you like to notify the customer about the cancellation?") },
        confirmButton = {
            Button(
                onClick = onNotify,
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.error,
                ),
            ) {
                Text("Yes, notify")
            }
        },
        dismissButton = {
            TextButton(onClick = onSkip) { Text("Cancel without notifying") }
        },
    )
}

// ---------------------------------------------------------------------------
// Conflict warning banner (L1438)
// ---------------------------------------------------------------------------

@Composable
private fun ConflictWarningBanner(
    message: String,
    onDismiss: () -> Unit,
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.errorContainer,
        ),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.weight(1f),
            ) {
                Icon(
                    Icons.Default.Warning,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onErrorContainer,
                )
                Text(
                    text = message,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onErrorContainer,
                )
            }
            IconButton(onClick = onDismiss) {
                Icon(
                    Icons.Default.Close,
                    contentDescription = "Dismiss conflict warning",
                    tint = MaterialTheme.colorScheme.onErrorContainer,
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Customer card (10.2)
// ---------------------------------------------------------------------------

@Composable
private fun CustomerCard(
    name: String,
    phone: String?,
    onClick: (() -> Unit)?,
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // Avatar — initials circle
            Surface(
                shape = CircleShape,
                color = MaterialTheme.colorScheme.primaryContainer,
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape),
            ) {
                Box(contentAlignment = Alignment.Center) {
                    val initials = name.split(" ")
                        .mapNotNull { it.firstOrNull()?.uppercaseChar() }
                        .take(2)
                        .joinToString("")
                        .ifBlank { "?" }
                    Text(
                        text = initials,
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.onPrimaryContainer,
                    )
                }
            }
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = name,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                if (!phone.isNullOrBlank()) {
                    Text(
                        text = phone,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            if (onClick != null) {
                Icon(
                    Icons.Default.ChevronRight,
                    contentDescription = "View customer",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Linked entity row (10.2)
// ---------------------------------------------------------------------------

@Composable
private fun LinkedEntityRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    secondary: String,
    onClick: () -> Unit,
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp)
            .clickable(onClick = onClick),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(icon, contentDescription = null, modifier = Modifier.size(20.dp))
            Text(
                text = label,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.weight(1f),
            )
            if (secondary.isNotBlank()) {
                Text(
                    text = secondary,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Icon(
                Icons.Default.ChevronRight,
                contentDescription = null,
                modifier = Modifier.size(16.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Recurring-edit scope dialog (10.3 / item 5)
// ---------------------------------------------------------------------------

/**
 * When editing a recurring appointment, presents three radio choices so the
 * user can choose how wide the edit should apply.
 *
 * editScope values sent to PATCH body:
 *   "single"  — exception override for this occurrence only
 *   "future"  — truncate original RRULE + create new series from this date
 *   "all"     — update the recurrence parent
 */
@Composable
private fun RecurringEditScopeDialog(
    selectedScope: String,
    onScopeChange: (String) -> Unit,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    val options = listOf(
        "single" to "This event only",
        "future" to "This and following events",
        "all"    to "All events in the series",
    )
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Edit recurring appointment") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                options.forEach { (value, label) ->
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onScopeChange(value) },
                    ) {
                        RadioButton(
                            selected = selectedScope == value,
                            onClick = { onScopeChange(value) },
                        )
                        Text(label, style = MaterialTheme.typography.bodyMedium)
                    }
                }
            }
        },
        confirmButton = {
            Button(onClick = onConfirm) { Text("Save") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}

// ---------------------------------------------------------------------------
// Shared detail row
// ---------------------------------------------------------------------------

@Composable
private fun DetailRow(label: String, value: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            fontWeight = FontWeight.Medium,
            modifier = Modifier.weight(0.4f),
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodySmall,
            modifier = Modifier.weight(0.6f),
        )
    }
}
