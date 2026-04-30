package com.bizarreelectronics.crm.ui.screens.employees

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.NavigateBefore
import androidx.compose.material.icons.automirrored.filled.NavigateNext
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.ShiftScheduleApi
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.temporal.TemporalAdjusters
import javax.inject.Inject

// ─── Data model ──────────────────────────────────────────────────────────────

data class ScheduledShift(
    val id: Long,
    val userId: Long,
    val employeeName: String,
    val startTime: String,
    val endTime: String,
    val role: String?,
    val notes: String?,
    /** Day-of-week label: "Mon" … "Sun" */
    val dayLabel: String,
)

data class ShiftScheduleUiState(
    val shifts: List<ScheduledShift> = emptyList(),
    val isLoading: Boolean = true,
    val error: String? = null,
    val serverUnsupported: Boolean = false,
    val weekStart: LocalDate = LocalDate.now().with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY)),
    val isManager: Boolean = false,
    /** Shift pending deletion — shown in ConfirmDialog. */
    val pendingDeleteShift: ScheduledShift? = null,
    val showAddDialog: Boolean = false,
    val toastMessage: String? = null,
)

// ─── ViewModel ───────────────────────────────────────────────────────────────

@HiltViewModel
class ShiftScheduleViewModel @Inject constructor(
    private val shiftScheduleApi: ShiftScheduleApi,
    authPreferences: AuthPreferences,
) : ViewModel() {

    private val _state = MutableStateFlow(
        ShiftScheduleUiState(
            isManager = authPreferences.userRole?.lowercase() in setOf("admin", "manager", "owner"),
        ),
    )
    val state = _state.asStateFlow()

    private val weekFmt = DateTimeFormatter.ISO_LOCAL_DATE

    init { loadShifts() }

    fun loadShifts() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = _state.value.shifts.isEmpty(), error = null)
            val weekStart = _state.value.weekStart
            runCatching { shiftScheduleApi.getShifts(weekStart = weekFmt.format(weekStart)) }
                .onSuccess { resp ->
                    val parsed = parseShifts(resp.data, weekStart)
                    _state.value = _state.value.copy(
                        isLoading = false,
                        shifts = parsed,
                        serverUnsupported = false,
                        error = null,
                    )
                }
                .onFailure { t ->
                    val is404 = t is retrofit2.HttpException && t.code() == 404
                    _state.value = _state.value.copy(
                        isLoading = false,
                        serverUnsupported = is404,
                        error = if (is404) null else (t.message ?: "Failed to load shifts"),
                    )
                }
        }
    }

    fun previousWeek() {
        _state.value = _state.value.copy(weekStart = _state.value.weekStart.minusWeeks(1))
        loadShifts()
    }

    fun nextWeek() {
        _state.value = _state.value.copy(weekStart = _state.value.weekStart.plusWeeks(1))
        loadShifts()
    }

    fun requestDeleteShift(shift: ScheduledShift) {
        _state.value = _state.value.copy(pendingDeleteShift = shift)
    }

    fun cancelDelete() {
        _state.value = _state.value.copy(pendingDeleteShift = null)
    }

    fun confirmDelete() {
        val shift = _state.value.pendingDeleteShift ?: return
        _state.value = _state.value.copy(pendingDeleteShift = null)
        viewModelScope.launch {
            runCatching { shiftScheduleApi.deleteShift(shift.id) }
                .onSuccess {
                    _state.value = _state.value.copy(toastMessage = "Shift removed")
                    loadShifts()
                }
                .onFailure { _state.value = _state.value.copy(toastMessage = "Failed to remove shift") }
        }
    }

    fun showAddDialog() { _state.value = _state.value.copy(showAddDialog = true) }
    fun dismissAddDialog() { _state.value = _state.value.copy(showAddDialog = false) }

    fun createShift(employeeId: Long, startIso: String, endIso: String, notes: String) {
        viewModelScope.launch {
            val body = buildMap<String, Any> {
                put("user_id", employeeId)
                put("start_time", startIso)
                put("end_time", endIso)
                if (notes.isNotBlank()) put("notes", notes)
            }
            runCatching { shiftScheduleApi.createShift(body) }
                .onSuccess {
                    _state.value = _state.value.copy(showAddDialog = false, toastMessage = "Shift added")
                    loadShifts()
                }
                .onFailure { _state.value = _state.value.copy(toastMessage = "Failed to add shift") }
        }
    }

    fun clearToast() { _state.value = _state.value.copy(toastMessage = null) }

    // ── parser ────────────────────────────────────────────────────────────────

    @Suppress("UNCHECKED_CAST")
    private fun parseShifts(data: Any?, weekStart: LocalDate): List<ScheduledShift> {
        val list = when (data) {
            is List<*> -> data
            is Map<*, *> -> (data["shifts"] as? List<*>) ?: return emptyList()
            else -> return emptyList()
        }
        val dayNames = listOf("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
        return list.mapNotNull { raw ->
            val m = raw as? Map<*, *> ?: return@mapNotNull null
            val id = (m["id"] as? Number)?.toLong() ?: return@mapNotNull null
            val startStr = m["start_time"] as? String ?: ""
            // Determine day label from startStr date portion
            val dayLabel = runCatching {
                val date = LocalDate.parse(startStr.take(10), DateTimeFormatter.ISO_LOCAL_DATE)
                dayNames.getOrElse(date.dayOfWeek.value - 1) { "?" }
            }.getOrDefault("?")
            ScheduledShift(
                id = id,
                userId = (m["user_id"] as? Number)?.toLong() ?: 0L,
                employeeName = listOfNotNull(
                    m["first_name"] as? String,
                    m["last_name"] as? String,
                ).joinToString(" ").ifBlank { m["username"] as? String ?: "Unknown" },
                startTime = startStr,
                endTime = m["end_time"] as? String ?: "",
                role = m["role"] as? String,
                notes = m["notes"] as? String,
                dayLabel = dayLabel,
            )
        }
    }
}

// ─── Screen ──────────────────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ShiftScheduleScreen(
    onBack: () -> Unit,
    viewModel: ShiftScheduleViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHost = remember { SnackbarHostState() }

    LaunchedEffect(state.toastMessage) {
        val msg = state.toastMessage ?: return@LaunchedEffect
        snackbarHost.showSnackbar(msg)
        viewModel.clearToast()
    }

    // ── Delete confirm dialog ────────────────────────────────────────────────
    state.pendingDeleteShift?.let { shift ->
        AlertDialog(
            onDismissRequest = { viewModel.cancelDelete() },
            title = { Text("Remove shift?") },
            text = { Text("Remove ${shift.dayLabel} shift for ${shift.employeeName}?") },
            confirmButton = {
                TextButton(onClick = { viewModel.confirmDelete() }) {
                    Text("Remove", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { viewModel.cancelDelete() }) { Text("Cancel") }
            },
        )
    }

    // ── Add shift dialog ─────────────────────────────────────────────────────
    if (state.showAddDialog) {
        AddShiftDialog(
            onDismiss = { viewModel.dismissAddDialog() },
            onConfirm = { empId, start, end, notes ->
                viewModel.createShift(empId, start, end, notes)
            },
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHost) },
        topBar = {
            BrandTopAppBar(
                title = "Shift Schedule",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
        floatingActionButton = {
            if (state.isManager) {
                FloatingActionButton(onClick = { viewModel.showAddDialog() }) {
                    Icon(Icons.Default.Add, contentDescription = "Add shift")
                }
            }
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            // ── Week navigator ────────────────────────────────────────────────
            WeekNavigatorRow(
                weekStart = state.weekStart,
                onPrev = { viewModel.previousWeek() },
                onNext = { viewModel.nextWeek() },
            )

            when {
                state.isLoading -> Box(
                    Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center,
                ) { CircularProgressIndicator() }

                state.serverUnsupported -> EmptyState(
                    icon = Icons.Default.Schedule,
                    title = "Shift scheduling not available",
                    subtitle = "Shift scheduling is not configured on this server.",
                )

                state.error != null -> ErrorState(
                    message = state.error!!,
                    onRetry = { viewModel.loadShifts() },
                )

                state.shifts.isEmpty() -> EmptyState(
                    icon = Icons.Default.Schedule,
                    title = "No shifts this week",
                    subtitle = if (state.isManager) "Tap + to add a shift." else "No shifts scheduled.",
                )

                else -> ShiftWeekGrid(
                    shifts = state.shifts,
                    isManager = state.isManager,
                    onDeleteShift = { viewModel.requestDeleteShift(it) },
                )
            }
        }
    }
}

// ─── Sub-components ──────────────────────────────────────────────────────────

@Composable
private fun WeekNavigatorRow(
    weekStart: LocalDate,
    onPrev: () -> Unit,
    onNext: () -> Unit,
) {
    val fmt = DateTimeFormatter.ofPattern("MMM d")
    val weekEnd = weekStart.plusDays(6)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        IconButton(onClick = onPrev) {
            Icon(Icons.AutoMirrored.Filled.NavigateBefore, contentDescription = "Previous week")
        }
        Text(
            text = "${fmt.format(weekStart)} – ${fmt.format(weekEnd)}",
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
        )
        IconButton(onClick = onNext) {
            Icon(Icons.AutoMirrored.Filled.NavigateNext, contentDescription = "Next week")
        }
    }
}

@Composable
private fun ShiftWeekGrid(
    shifts: List<ScheduledShift>,
    isManager: Boolean,
    onDeleteShift: (ScheduledShift) -> Unit,
) {
    val dayOrder = listOf("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
    val grouped = shifts.groupBy { it.dayLabel }

    LazyColumn(
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        items(dayOrder) { day ->
            val dayShifts = grouped[day] ?: emptyList()
            Surface(
                modifier = Modifier.fillMaxWidth(),
                color = MaterialTheme.colorScheme.surfaceContainerLow,
                shape = MaterialTheme.shapes.medium,
            ) {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text(
                        text = day,
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.padding(bottom = 4.dp),
                    )
                    if (dayShifts.isEmpty()) {
                        Text(
                            "No shifts",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    } else {
                        dayShifts.forEach { shift ->
                            ShiftRow(shift = shift, isManager = isManager, onDelete = onDeleteShift)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ShiftRow(
    shift: ScheduledShift,
    isManager: Boolean,
    onDelete: (ScheduledShift) -> Unit,
) {
    val timeRange = buildString {
        val start = shift.startTime.drop(11).take(5)
        val end = shift.endTime.drop(11).take(5)
        if (start.isNotBlank()) append("$start – $end")
    }
    ListItem(
        headlineContent = { Text(shift.employeeName, style = MaterialTheme.typography.bodyMedium) },
        supportingContent = {
            if (timeRange.isNotBlank()) {
                Text(timeRange, style = MaterialTheme.typography.bodySmall)
            }
        },
        trailingContent = {
            if (isManager) {
                IconButton(onClick = { onDelete(shift) }) {
                    Icon(
                        Icons.Default.Delete,
                        contentDescription = "Remove shift for ${shift.employeeName}",
                        tint = MaterialTheme.colorScheme.error,
                    )
                }
            }
        },
        colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surface),
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AddShiftDialog(
    onDismiss: () -> Unit,
    onConfirm: (employeeId: Long, startIso: String, endIso: String, notes: String) -> Unit,
) {
    var employeeIdStr by remember { mutableStateOf("") }
    var startTime by remember { mutableStateOf("") }
    var endTime by remember { mutableStateOf("") }
    var notes by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Add Shift") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = employeeIdStr,
                    onValueChange = { employeeIdStr = it },
                    label = { Text("Employee ID") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = startTime,
                    onValueChange = { startTime = it },
                    label = { Text("Start (YYYY-MM-DDTHH:MM)") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = endTime,
                    onValueChange = { endTime = it },
                    label = { Text("End (YYYY-MM-DDTHH:MM)") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = notes,
                    onValueChange = { notes = it },
                    label = { Text("Notes (optional)") },
                    modifier = Modifier.fillMaxWidth(),
                    maxLines = 2,
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    val empId = employeeIdStr.trim().toLongOrNull() ?: return@TextButton
                    onConfirm(empId, startTime.trim(), endTime.trim(), notes.trim())
                },
                enabled = employeeIdStr.trim().toLongOrNull() != null &&
                    startTime.isNotBlank() && endTime.isNotBlank(),
            ) { Text("Add") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}
