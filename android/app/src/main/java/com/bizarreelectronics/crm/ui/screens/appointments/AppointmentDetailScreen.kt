package com.bizarreelectronics.crm.ui.screens.appointments

import android.widget.Toast
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
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

                    // Detail info card
                    item {
                        Card(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp, vertical = 8.dp),
                        ) {
                            Column(modifier = Modifier.padding(16.dp)) {
                                DetailRow(label = "Customer", value = appt.customerName ?: "—")
                                DetailRow(label = "Technician", value = appt.employeeName ?: "—")
                                DetailRow(label = "Type", value = appt.type ?: "—")
                                DetailRow(label = "Start", value = appt.startTime ?: "—")
                                DetailRow(label = "Duration", value = appt.durationMinutes?.let { "${it}min" } ?: "—")
                                DetailRow(label = "Location", value = appt.location ?: "—")
                                DetailRow(label = "Status", value = appt.status ?: "scheduled")
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
