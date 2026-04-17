package com.bizarreelectronics.crm.ui.screens.leads

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.AccessTime
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.LeadApi
import com.bizarreelectronics.crm.data.remote.dto.CreateAppointmentRequest
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import javax.inject.Inject

// ─── Constants & helpers ─────────────────────────────────────────────────────

private const val ONE_HOUR_MILLIS = 60L * 60L * 1000L

/** Server format: 'YYYY-MM-DD HH:MM:SS' (matches what leads.routes.ts INSERT expects). */
private val SERVER_DATETIME_FORMAT: SimpleDateFormat
    get() = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).apply {
        timeZone = TimeZone.getDefault()
    }

// CROSS46: display date routes through the canonical DateFormatter
// ("April 16, 2026"). Time-of-day stays local (tiny SimpleDateFormat) — the
// shared util exposes `formatTimeOfDay(Long)` too, but the existing local
// helper matches this screen's pattern of Calendar-based date math.
private val DISPLAY_TIME_FORMAT: SimpleDateFormat
    get() = SimpleDateFormat("h:mm a", Locale.US)

private fun formatServerDateTime(millis: Long): String =
    SERVER_DATETIME_FORMAT.format(Date(millis))

private fun formatDisplayDate(millis: Long): String =
    com.bizarreelectronics.crm.util.DateFormatter.formatAbsolute(millis)

private fun formatDisplayTime(millis: Long): String =
    DISPLAY_TIME_FORMAT.format(Date(millis))

/** Default start: today at the next half hour, plus 1 hour for end. */
private fun defaultStartMillis(): Long {
    val cal = Calendar.getInstance().apply {
        add(Calendar.MINUTE, 30)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
        // Round to nearest half hour
        val minute = get(Calendar.MINUTE)
        val rounded = if (minute < 30) 30 else 0
        if (rounded == 0) add(Calendar.HOUR_OF_DAY, 1)
        set(Calendar.MINUTE, rounded)
    }
    return cal.timeInMillis
}

/** Compose a millis from a date base + a (hour, minute) time-of-day. */
private fun composeMillis(dateMillis: Long, hour: Int, minute: Int): Long {
    val cal = Calendar.getInstance().apply {
        timeInMillis = dateMillis
        set(Calendar.HOUR_OF_DAY, hour)
        set(Calendar.MINUTE, minute)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }
    return cal.timeInMillis
}

private fun hourOf(millis: Long): Int =
    Calendar.getInstance().apply { timeInMillis = millis }.get(Calendar.HOUR_OF_DAY)

private fun minuteOf(millis: Long): Int =
    Calendar.getInstance().apply { timeInMillis = millis }.get(Calendar.MINUTE)

// ─── UI state ────────────────────────────────────────────────────────────────

data class AppointmentCreateUiState(
    val title: String = "",
    val startDateTimeMillis: Long = 0L,
    val endDateTimeMillis: Long = 0L,
    val assignedTo: Long? = null,
    val leadId: Long? = null,
    val customerId: Long? = null,
    val notes: String = "",
    val isOffline: Boolean = false,
    val isSubmitting: Boolean = false,
    val error: String? = null,
    val createdId: Long? = null,
)

private fun initialState(userId: Long?): AppointmentCreateUiState {
    val start = defaultStartMillis()
    return AppointmentCreateUiState(
        startDateTimeMillis = start,
        endDateTimeMillis = start + ONE_HOUR_MILLIS,
        assignedTo = userId?.takeIf { it > 0 },
    )
}

// ─── ViewModel ───────────────────────────────────────────────────────────────

@HiltViewModel
class AppointmentCreateViewModel @Inject constructor(
    private val leadApi: LeadApi,
    private val authPreferences: AuthPreferences,
    private val serverMonitor: ServerReachabilityMonitor,
) : ViewModel() {

    private val _state = MutableStateFlow(initialState(authPreferences.userId))
    val state = _state.asStateFlow()

    init {
        viewModelScope.launch {
            serverMonitor.isEffectivelyOnline.collect { online ->
                _state.value = _state.value.copy(isOffline = !online)
            }
        }
    }

    fun updateTitle(value: String) {
        _state.value = _state.value.copy(title = value)
    }

    fun updateNotes(value: String) {
        _state.value = _state.value.copy(notes = value)
    }

    fun updateStartDate(dateMillis: Long) {
        val current = _state.value
        val newStart = composeMillis(
            dateMillis,
            hourOf(current.startDateTimeMillis),
            minuteOf(current.startDateTimeMillis),
        )
        // If end is before new start, push end to start + 1 hour
        val newEnd = if (current.endDateTimeMillis <= newStart) {
            newStart + ONE_HOUR_MILLIS
        } else {
            current.endDateTimeMillis
        }
        _state.value = current.copy(
            startDateTimeMillis = newStart,
            endDateTimeMillis = newEnd,
        )
    }

    fun updateStartTime(hour: Int, minute: Int) {
        val current = _state.value
        val newStart = composeMillis(current.startDateTimeMillis, hour, minute)
        val newEnd = if (current.endDateTimeMillis <= newStart) {
            newStart + ONE_HOUR_MILLIS
        } else {
            current.endDateTimeMillis
        }
        _state.value = current.copy(
            startDateTimeMillis = newStart,
            endDateTimeMillis = newEnd,
        )
    }

    fun updateEndDate(dateMillis: Long) {
        val current = _state.value
        val newEnd = composeMillis(
            dateMillis,
            hourOf(current.endDateTimeMillis),
            minuteOf(current.endDateTimeMillis),
        )
        _state.value = current.copy(endDateTimeMillis = newEnd)
    }

    fun updateEndTime(hour: Int, minute: Int) {
        val current = _state.value
        val newEnd = composeMillis(current.endDateTimeMillis, hour, minute)
        _state.value = current.copy(endDateTimeMillis = newEnd)
    }

    fun clearError() {
        _state.value = _state.value.copy(error = null)
    }

    fun save() {
        val current = _state.value
        if (current.title.isBlank()) {
            _state.value = current.copy(error = "Title is required")
            return
        }
        if (current.endDateTimeMillis <= current.startDateTimeMillis) {
            _state.value = current.copy(error = "End time must be after start time")
            return
        }
        if (!serverMonitor.isEffectivelyOnline.value) {
            _state.value = current.copy(error = "Cannot create appointment while offline")
            return
        }

        viewModelScope.launch {
            _state.value = _state.value.copy(isSubmitting = true, error = null)
            try {
                val request = CreateAppointmentRequest(
                    leadId = current.leadId,
                    customerId = current.customerId,
                    title = current.title.trim(),
                    startTime = formatServerDateTime(current.startDateTimeMillis),
                    endTime = formatServerDateTime(current.endDateTimeMillis),
                    assignedTo = current.assignedTo,
                    notes = current.notes.trim().ifBlank { null },
                )
                val response = leadApi.createAppointment(request)
                val detail = response.data
                    ?: throw Exception(response.message ?: "Create failed")
                _state.value = _state.value.copy(
                    isSubmitting = false,
                    createdId = detail.id,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isSubmitting = false,
                    error = e.message ?: "Failed to create appointment",
                )
            }
        }
    }
}

// ─── Screen ──────────────────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppointmentCreateScreen(
    onBack: () -> Unit,
    onCreated: (Long) -> Unit,
    viewModel: AppointmentCreateViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    // @audit-fixed: dialog visibility was lost on rotation. rememberSaveable
    // ensures an open picker stays open after a config change so the user does
    // not have to re-tap the field they were editing.
    var showStartDatePicker by rememberSaveable { mutableStateOf(false) }
    var showStartTimePicker by rememberSaveable { mutableStateOf(false) }
    var showEndDatePicker by rememberSaveable { mutableStateOf(false) }
    var showEndTimePicker by rememberSaveable { mutableStateOf(false) }

    LaunchedEffect(state.createdId) {
        val id = state.createdId
        if (id != null) onCreated(id)
    }

    LaunchedEffect(state.error) {
        val error = state.error
        if (error != null) {
            snackbarHostState.showSnackbar(error)
            viewModel.clearError()
        }
    }

    if (showStartDatePicker) {
        AppointmentDatePicker(
            initialMillis = state.startDateTimeMillis,
            onDismiss = { showStartDatePicker = false },
            onConfirm = {
                viewModel.updateStartDate(it)
                showStartDatePicker = false
            },
        )
    }

    if (showStartTimePicker) {
        AppointmentTimePicker(
            initialHour = hourOf(state.startDateTimeMillis),
            initialMinute = minuteOf(state.startDateTimeMillis),
            onDismiss = { showStartTimePicker = false },
            onConfirm = { hour, minute ->
                viewModel.updateStartTime(hour, minute)
                showStartTimePicker = false
            },
        )
    }

    if (showEndDatePicker) {
        AppointmentDatePicker(
            initialMillis = state.endDateTimeMillis,
            onDismiss = { showEndDatePicker = false },
            onConfirm = {
                viewModel.updateEndDate(it)
                showEndDatePicker = false
            },
        )
    }

    if (showEndTimePicker) {
        AppointmentTimePicker(
            initialHour = hourOf(state.endDateTimeMillis),
            initialMinute = minuteOf(state.endDateTimeMillis),
            onDismiss = { showEndTimePicker = false },
            onConfirm = { hour, minute ->
                viewModel.updateEndTime(hour, minute)
                showEndTimePicker = false
            },
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = { Text("New Appointment") },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                ),
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                },
                actions = {
                    if (state.isSubmitting) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(24.dp),
                            strokeWidth = 2.dp,
                        )
                        Spacer(modifier = Modifier.width(16.dp))
                    } else {
                        TextButton(
                            onClick = { viewModel.save() },
                            enabled = state.title.isNotBlank() && !state.isOffline,
                        ) {
                            Text("Save")
                        }
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .imePadding()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            if (state.isOffline) {
                OfflineNotice()
            }

            // D5-6: IME Next moves focus so the keyboard's "Next" glyph advances
            // past the title toward the notes / date pickers below.
            val focusManager = LocalFocusManager.current
            OutlinedTextField(
                value = state.title,
                onValueChange = viewModel::updateTitle,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Title *") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                keyboardActions = KeyboardActions(
                    onNext = { focusManager.moveFocus(FocusDirection.Down) },
                ),
            )

            // Start date/time
            Text(
                "Start",
                style = MaterialTheme.typography.labelLarge,
                modifier = Modifier.padding(top = 4.dp),
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                DateTimeButton(
                    icon = Icons.Default.CalendarMonth,
                    label = formatDisplayDate(state.startDateTimeMillis),
                    onClick = { showStartDatePicker = true },
                    modifier = Modifier.weight(1f),
                )
                DateTimeButton(
                    icon = Icons.Default.AccessTime,
                    label = formatDisplayTime(state.startDateTimeMillis),
                    onClick = { showStartTimePicker = true },
                    modifier = Modifier.weight(1f),
                )
            }

            // End date/time
            Text(
                "End",
                style = MaterialTheme.typography.labelLarge,
                modifier = Modifier.padding(top = 4.dp),
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                DateTimeButton(
                    icon = Icons.Default.CalendarMonth,
                    label = formatDisplayDate(state.endDateTimeMillis),
                    onClick = { showEndDatePicker = true },
                    modifier = Modifier.weight(1f),
                )
                DateTimeButton(
                    icon = Icons.Default.AccessTime,
                    label = formatDisplayTime(state.endDateTimeMillis),
                    onClick = { showEndTimePicker = true },
                    modifier = Modifier.weight(1f),
                )
            }

            OutlinedTextField(
                value = state.notes,
                onValueChange = viewModel::updateNotes,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Notes") },
                minLines = 3,
                maxLines = 6,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Default),
            )
        }
    }
}

@Composable
private fun OfflineNotice() {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.errorContainer,
        ),
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(
                Icons.Default.CloudOff,
                // decorative — non-clickable banner; sibling offline message Text carries the announcement
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onErrorContainer,
            )
            Text(
                "You're offline. Appointments can only be created online.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onErrorContainer,
            )
        }
    }
}

@Composable
private fun DateTimeButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    OutlinedButton(
        onClick = onClick,
        modifier = modifier,
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 12.dp),
    ) {
        // decorative — OutlinedButton's label Text supplies the accessible name
        Icon(icon, contentDescription = null, modifier = Modifier.size(18.dp))
        Spacer(modifier = Modifier.width(8.dp))
        Text(label, style = MaterialTheme.typography.bodyMedium)
    }
}

// ─── Date/time picker dialogs ────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AppointmentDatePicker(
    initialMillis: Long,
    onDismiss: () -> Unit,
    onConfirm: (Long) -> Unit,
) {
    val pickerState = rememberDatePickerState(
        initialSelectedDateMillis = initialMillis,
    )
    DatePickerDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(
                onClick = {
                    val millis = pickerState.selectedDateMillis
                    if (millis != null) onConfirm(millis) else onDismiss()
                },
                enabled = pickerState.selectedDateMillis != null,
            ) { Text("OK") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    ) {
        DatePicker(state = pickerState)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AppointmentTimePicker(
    initialHour: Int,
    initialMinute: Int,
    onDismiss: () -> Unit,
    onConfirm: (Int, Int) -> Unit,
) {
    val pickerState = rememberTimePickerState(
        initialHour = initialHour,
        initialMinute = initialMinute,
        is24Hour = false,
    )
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = { onConfirm(pickerState.hour, pickerState.minute) }) {
                Text("OK")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
        text = {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                TimePicker(state = pickerState)
            }
        },
    )
}
