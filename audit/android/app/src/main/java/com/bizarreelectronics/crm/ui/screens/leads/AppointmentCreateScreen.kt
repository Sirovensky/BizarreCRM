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
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.local.db.entities.SyncQueueEntity
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.local.prefs.OfflineIdGenerator
import com.bizarreelectronics.crm.data.remote.api.LeadApi
import com.bizarreelectronics.crm.data.remote.dto.CreateAppointmentRequest
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import com.google.gson.Gson
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
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

/** Appointment type values (10.2 / 10.3). */
val APPOINTMENT_TYPES = listOf("Drop-off", "Pickup", "Consult", "On-site", "Delivery")

/** Recurrence presets shown in the dropdown (10.3). */
val RECURRENCE_PRESETS = listOf("None", "Daily", "Weekly", "Monthly", "Custom")

/** Reminder offset chips in minutes (10.3). */
val REMINDER_OFFSET_OPTIONS = listOf(5, 15, 30, 60, 1440) // 1440 = 1 day

data class AppointmentCreateUiState(
    val title: String = "",
    val startDateTimeMillis: Long = 0L,
    val endDateTimeMillis: Long = 0L,
    /** Duration in minutes; derived from start/end but also editable via chips. */
    val durationMinutes: Int = 60,
    val assignedTo: Long? = null,
    val leadId: Long? = null,
    val customerId: Long? = null,
    val location: String = "",
    val type: String = "",
    // TODO(10.3): replace with search-picker once CustomerPicker component exists
    val linkedTicketId: Long? = null,
    val linkedEstimateId: Long? = null,
    val linkedLeadId: Long? = null,
    /** Set of selected reminder offsets (minutes) — e.g. setOf(15, 60). */
    val selectedReminderOffsets: Set<Int> = emptySet(),
    /** RRULE string; empty = no recurrence. */
    val rrule: String = "",
    /** Dropdown selection ("None" | "Daily" | "Weekly" | "Monthly" | "Custom"). */
    val recurrencePreset: String = "None",
    val notes: String = "",
    val isOffline: Boolean = false,
    val isSubmitting: Boolean = false,
    val error: String? = null,
    val createdId: Long? = null,
    /** True when the create was queued offline rather than posted immediately. */
    val savedOffline: Boolean = false,
)

private fun initialState(userId: Long?): AppointmentCreateUiState {
    val start = defaultStartMillis()
    return AppointmentCreateUiState(
        startDateTimeMillis = start,
        endDateTimeMillis = start + ONE_HOUR_MILLIS,
        durationMinutes = 60,
        assignedTo = userId?.takeIf { it > 0 },
    )
}

/** Recompute durationMinutes from start/end milliseconds. */
private fun durationFromMillis(startMillis: Long, endMillis: Long): Int {
    val diff = (endMillis - startMillis) / (60L * 1000L)
    return diff.toInt().coerceAtLeast(0)
}

// ─── ViewModel ───────────────────────────────────────────────────────────────

@HiltViewModel
class AppointmentCreateViewModel @Inject constructor(
    private val leadApi: LeadApi,
    private val authPreferences: AuthPreferences,
    private val serverMonitor: ServerReachabilityMonitor,
    private val syncQueueDao: SyncQueueDao,
    private val offlineIdGenerator: OfflineIdGenerator,
    private val gson: Gson,
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

    fun updateLocation(value: String) {
        _state.value = _state.value.copy(location = value)
    }

    fun updateType(value: String) {
        _state.value = _state.value.copy(type = value)
    }

    // TODO(10.3): replace numeric stubs with search-picker once CustomerPicker pattern is ported
    fun updateLinkedTicketId(value: Long?) { _state.value = _state.value.copy(linkedTicketId = value) }
    fun updateLinkedEstimateId(value: Long?) { _state.value = _state.value.copy(linkedEstimateId = value) }
    fun updateLinkedLeadId(value: Long?) { _state.value = _state.value.copy(linkedLeadId = value) }

    /** Toggle a reminder offset chip on/off. */
    fun toggleReminderOffset(minutes: Int) {
        val current = _state.value.selectedReminderOffsets
        _state.value = _state.value.copy(
            selectedReminderOffsets = if (minutes in current) current - minutes else current + minutes,
        )
    }

    fun updateRecurrencePreset(preset: String) {
        val rrule = when (preset) {
            "Daily" -> "FREQ=DAILY"
            "Weekly" -> "FREQ=WEEKLY"
            "Monthly" -> "FREQ=MONTHLY"
            else -> "" // None or Custom; Custom leaves the raw text field editable
        }
        _state.value = _state.value.copy(recurrencePreset = preset, rrule = rrule)
    }

    fun updateRrule(value: String) {
        _state.value = _state.value.copy(rrule = value)
    }

    /** Add [extraMinutes] to the current duration and shift end time accordingly. */
    fun addDuration(extraMinutes: Int) {
        val current = _state.value
        val newDuration = (current.durationMinutes + extraMinutes).coerceAtLeast(5)
        val newEnd = current.startDateTimeMillis + newDuration * 60L * 1000L
        _state.value = current.copy(durationMinutes = newDuration, endDateTimeMillis = newEnd)
    }

    fun updateStartDate(dateMillis: Long) {
        val current = _state.value
        val newStart = composeMillis(
            dateMillis,
            hourOf(current.startDateTimeMillis),
            minuteOf(current.startDateTimeMillis),
        )
        // Keep duration, slide end
        val newEnd = newStart + current.durationMinutes * 60L * 1000L
        _state.value = current.copy(startDateTimeMillis = newStart, endDateTimeMillis = newEnd)
    }

    fun updateStartTime(hour: Int, minute: Int) {
        val current = _state.value
        val newStart = composeMillis(current.startDateTimeMillis, hour, minute)
        val newEnd = newStart + current.durationMinutes * 60L * 1000L
        _state.value = current.copy(startDateTimeMillis = newStart, endDateTimeMillis = newEnd)
    }

    fun updateEndDate(dateMillis: Long) {
        val current = _state.value
        val newEnd = composeMillis(
            dateMillis,
            hourOf(current.endDateTimeMillis),
            minuteOf(current.endDateTimeMillis),
        )
        _state.value = current.copy(
            endDateTimeMillis = newEnd,
            durationMinutes = durationFromMillis(current.startDateTimeMillis, newEnd),
        )
    }

    fun updateEndTime(hour: Int, minute: Int) {
        val current = _state.value
        val newEnd = composeMillis(current.endDateTimeMillis, hour, minute)
        _state.value = current.copy(
            endDateTimeMillis = newEnd,
            durationMinutes = durationFromMillis(current.startDateTimeMillis, newEnd),
        )
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

        // Build the request; generate a per-attempt idempotency key (AP5 / item 4)
        val idempotencyKey = UUID.randomUUID().toString()
        val request = CreateAppointmentRequest(
            leadId = current.leadId,
            customerId = current.customerId,
            title = current.title.trim(),
            startTime = formatServerDateTime(current.startDateTimeMillis),
            endTime = formatServerDateTime(current.endDateTimeMillis),
            durationMinutes = current.durationMinutes,
            assignedTo = current.assignedTo,
            location = current.location.trim().ifBlank { null },
            type = current.type.ifBlank { null },
            linkedTicketId = current.linkedTicketId,
            linkedEstimateId = current.linkedEstimateId,
            linkedLeadId = current.linkedLeadId,
            reminderOffsets = current.selectedReminderOffsets
                .sorted().joinToString(",").ifBlank { null },
            rrule = current.rrule.trim().ifBlank { null },
            notes = current.notes.trim().ifBlank { null },
            idempotencyKey = idempotencyKey,
        )

        if (!serverMonitor.isEffectivelyOnline.value) {
            // Offline path: write to sync queue (item 4)
            viewModelScope.launch {
                val tempId = offlineIdGenerator.nextTempId()
                val entity = SyncQueueEntity(
                    entityType = "appointment",
                    entityId = tempId,
                    operation = "create",
                    payload = gson.toJson(request),
                    idempotencyKey = idempotencyKey,
                )
                syncQueueDao.insert(entity)
                _state.value = _state.value.copy(
                    isSubmitting = false,
                    savedOffline = true,
                    createdId = tempId,
                )
            }
            return
        }

        viewModelScope.launch {
            _state.value = _state.value.copy(isSubmitting = true, error = null)
            try {
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

    LaunchedEffect(state.savedOffline) {
        if (state.savedOffline) {
            snackbarHostState.showSnackbar("Saved offline — will sync when online")
        }
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
                            enabled = state.title.isNotBlank(),
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

            // Duration quick chips + display (10.3)
            Text(
                "Duration",
                style = MaterialTheme.typography.labelLarge,
                modifier = Modifier.padding(top = 4.dp),
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    "${state.durationMinutes} min",
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.weight(1f),
                )
                listOf(15, 30, 60).forEach { delta ->
                    AssistChip(
                        onClick = { viewModel.addDuration(delta) },
                        label = { Text("+${delta}m") },
                    )
                }
            }

            // Type dropdown (10.3)
            var typeExpanded by rememberSaveable { mutableStateOf(false) }
            ExposedDropdownMenuBox(
                expanded = typeExpanded,
                onExpandedChange = { typeExpanded = !typeExpanded },
            ) {
                OutlinedTextField(
                    value = state.type.ifBlank { "Select type" },
                    onValueChange = {},
                    readOnly = true,
                    label = { Text("Type") },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = typeExpanded) },
                    modifier = Modifier
                        .fillMaxWidth()
                        .menuAnchor(),
                )
                ExposedDropdownMenu(
                    expanded = typeExpanded,
                    onDismissRequest = { typeExpanded = false },
                ) {
                    APPOINTMENT_TYPES.forEach { t ->
                        DropdownMenuItem(
                            text = { Text(t) },
                            onClick = {
                                viewModel.updateType(t)
                                typeExpanded = false
                            },
                        )
                    }
                }
            }

            // Location (10.3)
            OutlinedTextField(
                value = state.location,
                onValueChange = viewModel::updateLocation,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Location") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                keyboardActions = KeyboardActions(onNext = { focusManager.moveFocus(FocusDirection.Down) }),
            )

            // TODO(10.3): customerPicker — replace with search-picker once ported
            // Currently customer_id must be passed in via the leadId/customerId pre-fill.

            // Linked entities — numeric stub fields (10.3)
            // TODO(10.3): replace with searchable pickers once ticket/estimate/lead search APIs are wired
            val linkedTicketText = rememberSaveable { mutableStateOf(state.linkedTicketId?.toString() ?: "") }
            OutlinedTextField(
                value = linkedTicketText.value,
                onValueChange = { v ->
                    linkedTicketText.value = v.filter { it.isDigit() }
                    viewModel.updateLinkedTicketId(linkedTicketText.value.toLongOrNull())
                },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Linked Ticket ID (optional)") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    keyboardType = androidx.compose.ui.text.input.KeyboardType.Number,
                    imeAction = ImeAction.Next,
                ),
            )
            val linkedEstimateText = rememberSaveable { mutableStateOf(state.linkedEstimateId?.toString() ?: "") }
            OutlinedTextField(
                value = linkedEstimateText.value,
                onValueChange = { v ->
                    linkedEstimateText.value = v.filter { it.isDigit() }
                    viewModel.updateLinkedEstimateId(linkedEstimateText.value.toLongOrNull())
                },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Linked Estimate ID (optional)") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    keyboardType = androidx.compose.ui.text.input.KeyboardType.Number,
                    imeAction = ImeAction.Next,
                ),
            )
            val linkedLeadText = rememberSaveable { mutableStateOf(state.linkedLeadId?.toString() ?: "") }
            OutlinedTextField(
                value = linkedLeadText.value,
                onValueChange = { v ->
                    linkedLeadText.value = v.filter { it.isDigit() }
                    viewModel.updateLinkedLeadId(linkedLeadText.value.toLongOrNull())
                },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Linked Lead ID (optional)") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    keyboardType = androidx.compose.ui.text.input.KeyboardType.Number,
                    imeAction = ImeAction.Next,
                ),
            )

            // Reminder offset multi-select chips (10.3)
            Text(
                "Reminders",
                style = MaterialTheme.typography.labelLarge,
                modifier = Modifier.padding(top = 4.dp),
            )
            val reminderLabels = mapOf(5 to "5 min", 15 to "15 min", 30 to "30 min", 60 to "1h", 1440 to "1 day")
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                REMINDER_OFFSET_OPTIONS.forEach { minutes ->
                    FilterChip(
                        selected = minutes in state.selectedReminderOffsets,
                        onClick = { viewModel.toggleReminderOffset(minutes) },
                        label = { Text(reminderLabels[minutes] ?: "$minutes min") },
                    )
                }
            }

            // Recurrence (10.3)
            var recurrenceExpanded by rememberSaveable { mutableStateOf(false) }
            Text(
                "Recurrence",
                style = MaterialTheme.typography.labelLarge,
                modifier = Modifier.padding(top = 4.dp),
            )
            ExposedDropdownMenuBox(
                expanded = recurrenceExpanded,
                onExpandedChange = { recurrenceExpanded = !recurrenceExpanded },
            ) {
                OutlinedTextField(
                    value = state.recurrencePreset,
                    onValueChange = {},
                    readOnly = true,
                    label = { Text("Repeat") },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = recurrenceExpanded) },
                    modifier = Modifier
                        .fillMaxWidth()
                        .menuAnchor(),
                )
                ExposedDropdownMenu(
                    expanded = recurrenceExpanded,
                    onDismissRequest = { recurrenceExpanded = false },
                ) {
                    RECURRENCE_PRESETS.forEach { p ->
                        DropdownMenuItem(
                            text = { Text(p) },
                            onClick = {
                                viewModel.updateRecurrencePreset(p)
                                recurrenceExpanded = false
                            },
                        )
                    }
                }
            }
            if (state.recurrencePreset == "Custom") {
                OutlinedTextField(
                    value = state.rrule,
                    onValueChange = viewModel::updateRrule,
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("RRULE") },
                    placeholder = { Text("e.g. FREQ=WEEKLY;BYDAY=MO,WE") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
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
                "You're offline. Appointment will be queued and synced when connectivity returns.",
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
