package com.bizarreelectronics.crm.ui.screens.appointments.components

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccessTime
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.R
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

// ─── Callback data class ──────────────────────────────────────────────────────

/** Minimal appointment data collected by the quick-create sheet. */
data class QuickAppointmentDraft(
    val title: String,
    val startMillis: Long,
    val endMillis: Long,
)

// ─── Sheet ────────────────────────────────────────────────────────────────────

/**
 * §10.3 Minimal appointment create — a ModalBottomSheet that collects only
 * title + start/end date-time, then calls [onSave].
 *
 * This is the "quick" path. For the full form (customer, assignee, recurrence,
 * reminders, linked entities) the caller should navigate to [AppointmentCreateScreen].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppointmentQuickCreateSheet(
    onDismiss: () -> Unit,
    onSave: (QuickAppointmentDraft) -> Unit,
    onOpenFullForm: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    var title by rememberSaveable { mutableStateOf("") }

    // Default start = next half-hour; default end = start + 1 hour
    val defaultStart = remember {
        val cal = Calendar.getInstance().apply {
            add(Calendar.MINUTE, 30)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            val min = get(Calendar.MINUTE)
            val rounded = if (min < 30) 30 else 0
            if (rounded == 0) add(Calendar.HOUR_OF_DAY, 1)
            set(Calendar.MINUTE, rounded)
        }
        cal.timeInMillis
    }
    var startMillis by rememberSaveable { mutableLongStateOf(defaultStart) }
    var endMillis   by rememberSaveable { mutableLongStateOf(defaultStart + 60L * 60L * 1000L) }

    var showStartDatePicker by rememberSaveable { mutableStateOf(false) }
    var showStartTimePicker by rememberSaveable { mutableStateOf(false) }
    var showEndTimePicker   by rememberSaveable { mutableStateOf(false) }

    val isValid = title.isNotBlank() && endMillis > startMillis

    // Date/time picker dialogs
    if (showStartDatePicker) {
        QuickDatePicker(
            initialMillis = startMillis,
            onDismiss = { showStartDatePicker = false },
            onConfirm = { millis ->
                // Keep time portion, just shift the date
                val cal = Calendar.getInstance()
                cal.timeInMillis = startMillis
                val h = cal.get(Calendar.HOUR_OF_DAY)
                val m = cal.get(Calendar.MINUTE)
                val newCal = Calendar.getInstance()
                newCal.timeInMillis = millis
                newCal.set(Calendar.HOUR_OF_DAY, h)
                newCal.set(Calendar.MINUTE, m)
                newCal.set(Calendar.SECOND, 0)
                val newStart = newCal.timeInMillis
                // Preserve duration
                val dur = endMillis - startMillis
                startMillis = newStart
                endMillis = newStart + dur
                showStartDatePicker = false
            },
        )
    }
    if (showStartTimePicker) {
        val cal = Calendar.getInstance().apply { timeInMillis = startMillis }
        QuickTimePicker(
            initialHour = cal.get(Calendar.HOUR_OF_DAY),
            initialMinute = cal.get(Calendar.MINUTE),
            onDismiss = { showStartTimePicker = false },
            onConfirm = { h, m ->
                val newCal = Calendar.getInstance().apply {
                    timeInMillis = startMillis
                    set(Calendar.HOUR_OF_DAY, h)
                    set(Calendar.MINUTE, m)
                    set(Calendar.SECOND, 0)
                }
                val dur = endMillis - startMillis
                startMillis = newCal.timeInMillis
                endMillis = startMillis + dur
                showStartTimePicker = false
            },
        )
    }
    if (showEndTimePicker) {
        val cal = Calendar.getInstance().apply { timeInMillis = endMillis }
        QuickTimePicker(
            initialHour = cal.get(Calendar.HOUR_OF_DAY),
            initialMinute = cal.get(Calendar.MINUTE),
            onDismiss = { showEndTimePicker = false },
            onConfirm = { h, m ->
                val newCal = Calendar.getInstance().apply {
                    timeInMillis = endMillis
                    set(Calendar.HOUR_OF_DAY, h)
                    set(Calendar.MINUTE, m)
                    set(Calendar.SECOND, 0)
                }
                endMillis = newCal.timeInMillis
                showEndTimePicker = false
            },
        )
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(
                text = stringResource(R.string.appt_quick_create_title),
                style = MaterialTheme.typography.titleMedium,
            )

            OutlinedTextField(
                value = title,
                onValueChange = { title = it },
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics { contentDescription = "Appointment title" },
                label = { Text(stringResource(R.string.appt_quick_create_title_label)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = {
                    if (isValid) onSave(QuickAppointmentDraft(title.trim(), startMillis, endMillis))
                }),
            )

            // Start date + time row
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                OutlinedButton(
                    onClick = { showStartDatePicker = true },
                    modifier = Modifier
                        .weight(1f)
                        .semantics { contentDescription = "Start date: ${formatDisplayDate(startMillis)}" },
                ) {
                    Icon(
                        Icons.Default.CalendarMonth,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp),
                    )
                    Spacer(Modifier.width(6.dp))
                    Text(formatDisplayDate(startMillis), style = MaterialTheme.typography.bodySmall)
                }
                OutlinedButton(
                    onClick = { showStartTimePicker = true },
                    modifier = Modifier
                        .weight(1f)
                        .semantics { contentDescription = "Start time: ${formatDisplayTime(startMillis)}" },
                ) {
                    Icon(
                        Icons.Default.AccessTime,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp),
                    )
                    Spacer(Modifier.width(6.dp))
                    Text(formatDisplayTime(startMillis), style = MaterialTheme.typography.bodySmall)
                }
            }

            // End time row (same-day assumption for quick form)
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = stringResource(R.string.appt_quick_create_end_label),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.width(52.dp),
                )
                OutlinedButton(
                    onClick = { showEndTimePicker = true },
                    modifier = Modifier
                        .weight(1f)
                        .semantics { contentDescription = "End time: ${formatDisplayTime(endMillis)}" },
                ) {
                    Icon(
                        Icons.Default.AccessTime,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp),
                    )
                    Spacer(Modifier.width(6.dp))
                    Text(formatDisplayTime(endMillis), style = MaterialTheme.typography.bodySmall)
                }
                val durationMins = ((endMillis - startMillis) / 60_000L).toInt()
                    .coerceAtLeast(0)
                Text(
                    text = "${durationMins}min",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            if (!isValid && title.isNotBlank()) {
                Text(
                    text = stringResource(R.string.appt_quick_create_end_after_start),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                // "More details" opens the full create form
                OutlinedButton(
                    onClick = onOpenFullForm,
                    modifier = Modifier.weight(1f),
                ) {
                    Text(stringResource(R.string.appt_quick_create_more_details))
                }
                FilledTonalButton(
                    onClick = {
                        if (isValid) onSave(QuickAppointmentDraft(title.trim(), startMillis, endMillis))
                    },
                    enabled = isValid,
                    modifier = Modifier.weight(1f),
                ) {
                    Text(stringResource(R.string.appt_quick_create_save))
                }
            }
        }
    }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

private val DISPLAY_DATE_FMT = SimpleDateFormat("MMM d, yyyy", Locale.US)
private val DISPLAY_TIME_FMT = SimpleDateFormat("h:mm a", Locale.US)

private fun formatDisplayDate(millis: Long): String = DISPLAY_DATE_FMT.format(Date(millis))
private fun formatDisplayTime(millis: Long): String = DISPLAY_TIME_FMT.format(Date(millis))

// ─── Date picker dialog ───────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun QuickDatePicker(
    initialMillis: Long,
    onDismiss: () -> Unit,
    onConfirm: (Long) -> Unit,
) {
    val state = rememberDatePickerState(initialSelectedDateMillis = initialMillis)
    DatePickerDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(
                onClick = { state.selectedDateMillis?.let(onConfirm) ?: onDismiss() },
                enabled = state.selectedDateMillis != null,
            ) { Text("OK") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    ) { DatePicker(state = state) }
}

// ─── Time picker dialog ───────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun QuickTimePicker(
    initialHour: Int,
    initialMinute: Int,
    onDismiss: () -> Unit,
    onConfirm: (Int, Int) -> Unit,
) {
    val state = rememberTimePickerState(
        initialHour = initialHour,
        initialMinute = initialMinute,
        is24Hour = false,
    )
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = { onConfirm(state.hour, state.minute) }) { Text("OK") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
        text = {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                TimePicker(state = state)
            }
        },
    )
}
