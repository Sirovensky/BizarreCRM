package com.bizarreelectronics.crm.ui.screens.communications.components

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.DatePicker
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import com.bizarreelectronics.crm.data.sync.ScheduledSmsWorker
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.concurrent.TimeUnit

/**
 * Bottom sheet for scheduling an SMS send at a future date/time.
 *
 * Flow:
 *  1. User picks a date via [DatePickerDialog].
 *  2. User picks a time via [TimePicker].
 *  3. "Schedule" calls [onSchedule] with the ISO-8601 string for the server.
 *     If server returns 404 the caller should fall back to [scheduleSendLocally].
 *
 * [scheduleSendLocally] is a static helper that enqueues a WorkManager job
 * as a 404 fallback — call it from the ViewModel after catching the 404.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScheduleSendSheet(
    onDismiss: () -> Unit,
    onSchedule: (sendAtIso: String) -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var showDatePicker by remember { mutableStateOf(true) }
    var selectedDateMs by remember { mutableStateOf<Long?>(null) }

    val datePickerState = rememberDatePickerState(
        initialSelectedDateMillis = System.currentTimeMillis(),
    )
    val timePickerState = rememberTimePickerState(
        initialHour = 9,
        initialMinute = 0,
        is24Hour = false,
    )

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp, vertical = 8.dp),
        ) {
            Text(
                text = "Schedule send",
                style = MaterialTheme.typography.titleMedium,
            )
            Spacer(Modifier.height(16.dp))

            if (showDatePicker) {
                DatePicker(
                    state = datePickerState,
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(Modifier.height(8.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End,
                ) {
                    TextButton(onClick = onDismiss) { Text("Cancel") }
                    Button(
                        onClick = {
                            selectedDateMs = datePickerState.selectedDateMillis
                            showDatePicker = false
                        },
                        enabled = datePickerState.selectedDateMillis != null,
                    ) { Text("Next: Pick time") }
                }
            } else {
                TimePicker(state = timePickerState)
                Spacer(Modifier.height(8.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp, androidx.compose.ui.Alignment.End),
                ) {
                    OutlinedButton(onClick = { showDatePicker = true }) { Text("Back") }
                    TextButton(onClick = onDismiss) { Text("Cancel") }
                    Button(onClick = {
                        val dateMs = selectedDateMs ?: System.currentTimeMillis()
                        val zone = ZoneId.systemDefault()
                        val scheduledAt = ZonedDateTime.ofInstant(
                            Instant.ofEpochMilli(dateMs), zone,
                        ).withHour(timePickerState.hour)
                            .withMinute(timePickerState.minute)
                            .withSecond(0)
                            .withNano(0)
                        onSchedule(scheduledAt.format(DateTimeFormatter.ISO_OFFSET_DATE_TIME))
                    }) { Text("Schedule") }
                }
            }

            Spacer(Modifier.height(16.dp))
        }
    }
}

/** WorkManager tag for scheduled SMS jobs — used for cancellation and listing. */
const val SCHEDULED_SMS_TAG = "scheduled_sms"

/**
 * Enqueues a WorkManager one-shot job as a 404 fallback for server-side schedule-send.
 *
 * @param context        Application context.
 * @param to             Recipient phone number.
 * @param message        SMS body.
 * @param triggerTimeMs  Epoch-ms when the message should fire.
 */
fun scheduleSendLocally(context: Context, to: String, message: String, triggerTimeMs: Long) {
    val delayMs = (triggerTimeMs - System.currentTimeMillis()).coerceAtLeast(0L)
    val inputData = workDataOf(
        "to" to to,
        "message" to message,
        "trigger_time_ms" to triggerTimeMs,
    )
    val request = OneTimeWorkRequestBuilder<ScheduledSmsWorker>()
        .setInputData(inputData)
        .setInitialDelay(delayMs, TimeUnit.MILLISECONDS)
        .addTag(SCHEDULED_SMS_TAG)
        .build()
    WorkManager.getInstance(context).enqueue(request)
}
