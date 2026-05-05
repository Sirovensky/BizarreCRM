package com.bizarreelectronics.crm.ui.screens.shifts

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.CreateShiftBody
import com.bizarreelectronics.crm.data.remote.api.ShiftDto
import com.bizarreelectronics.crm.data.remote.api.ShiftsApi
import com.bizarreelectronics.crm.data.remote.api.SettingsApi
import com.bizarreelectronics.crm.data.remote.dto.EmployeeListItem
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.theme.SuccessGreen
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.temporal.TemporalAdjusters
import javax.inject.Inject

// ── UI state ─────────────────────────────────────────────────────────────────

data class ShiftsScheduleUiState(
    val weekStart: LocalDate = LocalDate.now()
        .with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY)),
    val shifts: List<ShiftDto> = emptyList(),
    val employees: List<EmployeeListItem> = emptyList(),
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val isManager: Boolean = false,
    val actionMessage: String? = null,
    // Add-shift dialog
    val showAddShift: Boolean = false,
    val addShiftForDay: LocalDate? = null,
    // Delete confirm
    val pendingDeleteId: Long? = null,
)

// ── ViewModel ─────────────────────────────────────────────────────────────────

@HiltViewModel
class ShiftsScheduleViewModel @Inject constructor(
    private val shiftsApi: ShiftsApi,
    private val settingsApi: SettingsApi,
    private val authPreferences: AuthPreferences,
) : ViewModel() {

    private val _state = MutableStateFlow(
        ShiftsScheduleUiState(
            isManager = authPreferences.userRole?.lowercase() in setOf("admin", "manager"),
        ),
    )
    val state = _state.asStateFlow()

    init {
        loadEmployees()
        loadShifts()
    }

    private fun loadEmployees() {
        viewModelScope.launch {
            runCatching { settingsApi.getEmployees() }
                .onSuccess { _state.value = _state.value.copy(employees = it.data ?: emptyList()) }
        }
    }

    fun loadShifts() {
        viewModelScope.launch {
            val ws = _state.value.weekStart
            val we = ws.plusDays(6)
            _state.value = _state.value.copy(
                isLoading = _state.value.shifts.isEmpty(),
                error = null,
            )
            try {
                val response = shiftsApi.getShifts(
                    fromDate = ws.toString(),
                    toDate = we.toString(),
                )
                _state.value = _state.value.copy(
                    isLoading = false,
                    isRefreshing = false,
                    shifts = response.data ?: emptyList(),
                )
            } catch (e: retrofit2.HttpException) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    isRefreshing = false,
                    error = if (e.code() == 404) "Shift schedule not configured on this server" else "Failed to load shifts (${e.code()})",
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    isRefreshing = false,
                    error = e.message ?: "Failed to load shifts",
                )
            }
        }
    }

    fun prevWeek() {
        _state.value = _state.value.copy(
            weekStart = _state.value.weekStart.minusWeeks(1),
            isLoading = true,
        )
        loadShifts()
    }

    fun nextWeek() {
        _state.value = _state.value.copy(
            weekStart = _state.value.weekStart.plusWeeks(1),
            isLoading = true,
        )
        loadShifts()
    }

    fun showAddShiftForDay(day: LocalDate) {
        _state.value = _state.value.copy(showAddShift = true, addShiftForDay = day)
    }

    fun dismissAddShift() {
        _state.value = _state.value.copy(showAddShift = false, addShiftForDay = null)
    }

    /** Create a shift. startTime / endTime are "HH:mm" local times; combined with [day]. */
    fun createShift(employeeId: Long, day: LocalDate, startTime: String, endTime: String, notes: String) {
        viewModelScope.launch {
            val fmt = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss")
            val startAt = "${day}T${startTime}:00"
            val endAt = "${day}T${endTime}:00"
            _state.value = _state.value.copy(showAddShift = false)
            runCatching {
                shiftsApi.createShift(
                    CreateShiftBody(
                        userId = employeeId,
                        startAt = startAt,
                        endAt = endAt,
                        notes = notes.ifBlank { null },
                    ),
                )
            }
                .onSuccess {
                    _state.value = _state.value.copy(actionMessage = "Shift added")
                    loadShifts()
                }
                .onFailure {
                    _state.value = _state.value.copy(
                        actionMessage = it.message ?: "Failed to add shift",
                    )
                }
        }
    }

    fun confirmDeleteShift(shiftId: Long) {
        _state.value = _state.value.copy(pendingDeleteId = shiftId)
    }

    fun dismissDeleteShift() {
        _state.value = _state.value.copy(pendingDeleteId = null)
    }

    fun deleteShift() {
        val id = _state.value.pendingDeleteId ?: return
        viewModelScope.launch {
            _state.value = _state.value.copy(pendingDeleteId = null)
            runCatching { shiftsApi.deleteShift(id) }
                .onSuccess {
                    _state.value = _state.value.copy(actionMessage = "Shift deleted")
                    loadShifts()
                }
                .onFailure {
                    _state.value = _state.value.copy(actionMessage = it.message ?: "Failed to delete shift")
                }
        }
    }

    fun clearActionMessage() {
        _state.value = _state.value.copy(actionMessage = null)
    }
}

// ── Screen ────────────────────────────────────────────────────────────────────

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun ShiftsScheduleScreen(
    onBack: () -> Unit,
    viewModel: ShiftsScheduleViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(state.actionMessage) {
        state.actionMessage?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearActionMessage()
        }
    }

    // Delete confirm dialog
    if (state.pendingDeleteId != null) {
        AlertDialog(
            onDismissRequest = { viewModel.dismissDeleteShift() },
            title = { Text("Delete shift?") },
            text = { Text("This shift will be permanently removed.") },
            confirmButton = {
                TextButton(onClick = { viewModel.deleteShift() }) {
                    Text("Delete", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { viewModel.dismissDeleteShift() }) { Text("Cancel") }
            },
        )
    }

    // Add-shift dialog
    if (state.showAddShift && state.addShiftForDay != null) {
        AddShiftDialog(
            day = state.addShiftForDay!!,
            employees = state.employees,
            onDismiss = { viewModel.dismissAddShift() },
            onConfirm = { empId, start, end, notes ->
                viewModel.createShift(empId, state.addShiftForDay!!, start, end, notes)
            },
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            BrandTopAppBar(
                title = "Team Schedule",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
        floatingActionButton = {
            if (state.isManager) {
                FloatingActionButton(
                    onClick = { viewModel.showAddShiftForDay(state.weekStart) },
                ) {
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
            // Week nav row
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = { viewModel.prevWeek() }) {
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = "Previous week")
                }
                val weekEnd = state.weekStart.plusDays(6)
                val fmt = DateTimeFormatter.ofPattern("MMM d")
                Text(
                    "${state.weekStart.format(fmt)} – ${weekEnd.format(fmt)} ${state.weekStart.year}",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                IconButton(onClick = { viewModel.nextWeek() }) {
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = "Next week")
                }
            }
            HorizontalDivider()

            when {
                state.isLoading -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                }
                state.error != null && state.shifts.isEmpty() -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        ErrorState(message = state.error!!, onRetry = { viewModel.loadShifts() })
                    }
                }
                else -> {
                    // Build 7-day grid — one section per day
                    val days = (0..6).map { state.weekStart.plusDays(it.toLong()) }
                    val dayFmt = DateTimeFormatter.ofPattern("EEE, MMM d")
                    val timeFmt = DateTimeFormatter.ofPattern("h:mm a")

                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(bottom = 80.dp),
                    ) {
                        days.forEach { day ->
                            val dayShifts = state.shifts.filter { shift ->
                                shift.startAt.take(10) == day.toString()
                            }.sortedBy { it.startAt }

                            item(key = "header-$day") {
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .background(MaterialTheme.colorScheme.surfaceVariant)
                                        .clickable(enabled = state.isManager) {
                                            viewModel.showAddShiftForDay(day)
                                        }
                                        .padding(horizontal = 16.dp, vertical = 10.dp),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Text(
                                        day.format(dayFmt),
                                        style = MaterialTheme.typography.labelLarge,
                                        fontWeight = if (day == LocalDate.now()) FontWeight.Bold else FontWeight.Normal,
                                        color = if (day == LocalDate.now()) SuccessGreen
                                        else MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                    if (state.isManager) {
                                        Icon(
                                            Icons.Default.Add,
                                            contentDescription = "Add shift for ${day.format(dayFmt)}",
                                            modifier = Modifier.size(16.dp),
                                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    }
                                }
                            }

                            if (dayShifts.isEmpty()) {
                                item(key = "empty-$day") {
                                    Text(
                                        "No shifts",
                                        modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            } else {
                                items(dayShifts, key = { "shift-${it.id}" }) { shift ->
                                    ShiftRow(
                                        shift = shift,
                                        isManager = state.isManager,
                                        onDelete = { viewModel.confirmDeleteShift(shift.id) },
                                    )
                                    HorizontalDivider(
                                        modifier = Modifier.padding(start = 24.dp),
                                        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
                                    )
                                }
                            }

                            item(key = "divider-$day") {
                                HorizontalDivider()
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ShiftRow(
    shift: ShiftDto,
    isManager: Boolean,
    onDelete: () -> Unit,
) {
    val name = listOfNotNull(shift.firstName, shift.lastName)
        .joinToString(" ").ifBlank { shift.username ?: "Employee #${shift.userId}" }
    val startTime = shift.startAt.let {
        try { it.substring(11, 16) } catch (_: Exception) { it }
    }
    val endTime = shift.endAt.let {
        try { it.substring(11, 16) } catch (_: Exception) { it }
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                name,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                "$startTime – $endTime${if (!shift.roleTag.isNullOrBlank()) " · ${shift.roleTag}" else ""}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (!shift.notes.isNullOrBlank()) {
                Text(
                    shift.notes,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        if (isManager) {
            IconButton(onClick = onDelete, modifier = Modifier.size(32.dp)) {
                Icon(
                    Icons.Default.Delete,
                    contentDescription = "Delete shift",
                    modifier = Modifier.size(18.dp),
                    tint = MaterialTheme.colorScheme.error,
                )
            }
        }
    }
}

// ── Add shift dialog ──────────────────────────────────────────────────────────

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun AddShiftDialog(
    day: LocalDate,
    employees: List<EmployeeListItem>,
    onDismiss: () -> Unit,
    onConfirm: (employeeId: Long, startTime: String, endTime: String, notes: String) -> Unit,
) {
    val dayLabel = day.format(DateTimeFormatter.ofPattern("EEE, MMM d"))

    var selectedEmployee by remember {
        mutableStateOf(employees.firstOrNull())
    }
    var empDropdownExpanded by remember { mutableStateOf(false) }
    var startTime by remember { mutableStateOf("09:00") }
    var endTime by remember { mutableStateOf("17:00") }
    var notes by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Add Shift — $dayLabel") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                // Employee picker
                ExposedDropdownMenuBox(
                    expanded = empDropdownExpanded,
                    onExpandedChange = { empDropdownExpanded = it },
                ) {
                    OutlinedTextField(
                        value = selectedEmployee?.let {
                            listOfNotNull(it.firstName, it.lastName).joinToString(" ").ifBlank { it.username ?: "?" }
                        } ?: "Select employee",
                        onValueChange = {},
                        readOnly = true,
                        label = { Text("Employee") },
                        trailingIcon = {
                            ExposedDropdownMenuDefaults.TrailingIcon(expanded = empDropdownExpanded)
                        },
                        colors = ExposedDropdownMenuDefaults.outlinedTextFieldColors(),
                        modifier = Modifier
                            .fillMaxWidth()
                            .menuAnchor(),
                    )
                    ExposedDropdownMenu(
                        expanded = empDropdownExpanded,
                        onDismissRequest = { empDropdownExpanded = false },
                    ) {
                        employees.forEach { emp ->
                            val n = listOfNotNull(emp.firstName, emp.lastName)
                                .joinToString(" ").ifBlank { emp.username ?: "#${emp.id}" }
                            DropdownMenuItem(
                                text = { Text(n) },
                                onClick = {
                                    selectedEmployee = emp
                                    empDropdownExpanded = false
                                },
                            )
                        }
                    }
                }

                OutlinedTextField(
                    value = startTime,
                    onValueChange = { startTime = it },
                    label = { Text("Start time (HH:mm)") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = endTime,
                    onValueChange = { endTime = it },
                    label = { Text("End time (HH:mm)") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = notes,
                    onValueChange = { notes = it },
                    label = { Text("Notes (optional)") },
                    maxLines = 2,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    val emp = selectedEmployee ?: return@TextButton
                    onConfirm(emp.id, startTime, endTime, notes)
                },
                enabled = selectedEmployee != null && startTime.isNotBlank() && endTime.isNotBlank(),
            ) { Text("Add") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}
