package com.bizarreelectronics.crm.ui.screens.employees

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.EmployeeApi
import com.bizarreelectronics.crm.data.remote.api.SettingsApi
import com.bizarreelectronics.crm.data.remote.dto.EmployeeListItem
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.theme.SuccessGreen
import com.bizarreelectronics.crm.ui.theme.WarningAmber
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

// region — data types

/** §14.2 L1617/L1618 — performance + commission stubs */
data class EmployeePerformanceData(
    val ticketsClosedThisWeek: Int = 0,
    val avgTimeToCloseMinutes: Int = 0,
    val revenueCents: Long = 0L,
    val commissionCents: Long = 0L,
)

/** §14.3 L1629 — one day in the weekly timesheet grid */
data class TimesheetDay(val label: String, val hoursWorked: Double)

/** §14.3 L1628 — a single time-clock entry for the admin edit list */
data class TimeEntry(
    val id: Long,
    val clockIn: String,
    val clockOut: String?,
)

data class EmployeeDetailUiState(
    val employee: EmployeeListItem? = null,
    val isLoading: Boolean = true,
    val error: String? = null,
    val isAdmin: Boolean = false,
    // §14.2 performance + commission stubs
    val performance: EmployeePerformanceData = EmployeePerformanceData(),
    val performanceLoading: Boolean = false,
    // §14.3 timesheet
    val weeklyTimesheet: List<TimesheetDay> = emptyList(),
    val timesheetLoading: Boolean = false,
    // §14.3 time entries for admin edit
    val timeEntries: List<TimeEntry> = emptyList(),
    // admin action feedback
    val actionMessage: String? = null,
    val showDeactivateDialog: Boolean = false,
    val showResetPinDialog: Boolean = false,
)

// endregion

@HiltViewModel
class EmployeeDetailViewModel @Inject constructor(
    private val settingsApi: SettingsApi,
    private val employeeApi: EmployeeApi,
    private val authPreferences: AuthPreferences,
    savedStateHandle: SavedStateHandle,
) : ViewModel() {

    private val employeeId: Long = checkNotNull(savedStateHandle["id"]) {
        "EmployeeDetailViewModel requires an `id` nav arg"
    }

    private val _state = MutableStateFlow(
        EmployeeDetailUiState(isAdmin = authPreferences.userRole == "admin"),
    )
    val state = _state.asStateFlow()

    init {
        load()
    }

    fun load() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                val response = settingsApi.getEmployees()
                val match = response.data?.firstOrNull { it.id == employeeId }
                if (match == null) {
                    _state.value = _state.value.copy(isLoading = false, error = "Employee not found")
                } else {
                    _state.value = _state.value.copy(isLoading = false, employee = match, error = null)
                    loadPerformance()
                    loadTimesheet()
                }
            } catch (t: Throwable) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = t.message ?: "Failed to load employee",
                )
            }
        }
    }

    /** §14.2 L1617/L1618 — load performance + commission; stub on 404. */
    private fun loadPerformance() {
        viewModelScope.launch {
            _state.value = _state.value.copy(performanceLoading = true)
            val perf = runCatching { employeeApi.getPerformance(employeeId) }
                .getOrNull()
            val commission = runCatching { employeeApi.getCommissions(employeeId) }
                .getOrNull()

            // Parse best-effort — both endpoints may return 404
            val tickets = (perf?.data as? Map<*, *>)?.get("ticketsClosed")
                .let { (it as? Number)?.toInt() ?: 0 }
            val avgTime = (perf?.data as? Map<*, *>)?.get("avgTimeToCloseMinutes")
                .let { (it as? Number)?.toInt() ?: 0 }
            val revenue = (perf?.data as? Map<*, *>)?.get("revenueCents")
                .let { (it as? Number)?.toLong() ?: 0L }
            val commCents = (commission?.data as? Map<*, *>)?.get("commissionCents")
                .let { (it as? Number)?.toLong() ?: 0L }

            _state.value = _state.value.copy(
                performanceLoading = false,
                performance = EmployeePerformanceData(
                    ticketsClosedThisWeek = tickets,
                    avgTimeToCloseMinutes = avgTime,
                    revenueCents = revenue,
                    commissionCents = commCents,
                ),
            )
        }
    }

    /** §14.3 L1629 — load weekly timesheet; stub Mon-Sun with 0 h on 404. */
    private fun loadTimesheet() {
        viewModelScope.launch {
            _state.value = _state.value.copy(timesheetLoading = true)
            val response = runCatching { employeeApi.getWeeklyTimesheet(employeeId) }.getOrNull()
            val dayLabels = listOf("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
            val dayKeys = listOf("mon", "tue", "wed", "thu", "fri", "sat", "sun")
            val raw = response?.data as? Map<*, *>
            val days = dayLabels.mapIndexed { i, label ->
                val hours = raw?.get(dayKeys[i]).let { (it as? Number)?.toDouble() ?: 0.0 }
                TimesheetDay(label = label, hoursWorked = hours)
            }
            _state.value = _state.value.copy(timesheetLoading = false, weeklyTimesheet = days)
        }
    }

    // region — admin actions

    fun showDeactivateDialog() {
        _state.value = _state.value.copy(showDeactivateDialog = true)
    }

    fun hideDeactivateDialog() {
        _state.value = _state.value.copy(showDeactivateDialog = false)
    }

    fun confirmDeactivate() {
        viewModelScope.launch {
            _state.value = _state.value.copy(showDeactivateDialog = false)
            runCatching { employeeApi.deactivate(employeeId) }
                .onSuccess {
                    _state.value = _state.value.copy(actionMessage = "Employee deactivated")
                    load()
                }
                .onFailure { t ->
                    _state.value = _state.value.copy(
                        actionMessage = t.message ?: "Deactivate failed",
                    )
                }
        }
    }

    fun showResetPinDialog() {
        _state.value = _state.value.copy(showResetPinDialog = true)
    }

    fun hideResetPinDialog() {
        _state.value = _state.value.copy(showResetPinDialog = false)
    }

    fun confirmResetPin() {
        viewModelScope.launch {
            _state.value = _state.value.copy(showResetPinDialog = false)
            runCatching { employeeApi.resetPin(employeeId) }
                .onSuccess { _state.value = _state.value.copy(actionMessage = "PIN reset sent") }
                .onFailure { t ->
                    _state.value = _state.value.copy(
                        actionMessage = t.message ?: "PIN reset failed",
                    )
                }
        }
    }

    fun clearActionMessage() {
        _state.value = _state.value.copy(actionMessage = null)
    }

    // endregion
}

// region — Screen

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EmployeeDetailScreen(
    onBack: () -> Unit,
    viewModel: EmployeeDetailViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(state.actionMessage) {
        val msg = state.actionMessage ?: return@LaunchedEffect
        snackbarHostState.showSnackbar(msg)
        viewModel.clearActionMessage()
    }

    // Deactivate confirm dialog
    if (state.showDeactivateDialog) {
        AlertDialog(
            onDismissRequest = { viewModel.hideDeactivateDialog() },
            title = { Text("Deactivate employee?") },
            text = { Text("This will prevent the employee from logging in. Confirm?") },
            confirmButton = {
                TextButton(onClick = { viewModel.confirmDeactivate() }) {
                    Text("Deactivate", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { viewModel.hideDeactivateDialog() }) { Text("Cancel") }
            },
        )
    }

    // Reset PIN confirm dialog
    if (state.showResetPinDialog) {
        AlertDialog(
            onDismissRequest = { viewModel.hideResetPinDialog() },
            title = { Text("Reset PIN?") },
            text = { Text("The employee's PIN will be cleared. They will need to set a new one on next clock-in.") },
            confirmButton = {
                TextButton(onClick = { viewModel.confirmResetPin() }) { Text("Reset") }
            },
            dismissButton = {
                TextButton(onClick = { viewModel.hideResetPinDialog() }) { Text("Cancel") }
            },
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text("Employee") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        when {
            state.isLoading -> {
                Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            }
            state.employee == null -> {
                Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                    EmptyState(
                        icon = Icons.Default.Person,
                        title = "Not found",
                        subtitle = state.error ?: "We couldn't find that employee.",
                    )
                }
            }
            else -> {
                EmployeeDetailBody(
                    state = state,
                    onShowDeactivate = { viewModel.showDeactivateDialog() },
                    onShowResetPin = { viewModel.showResetPinDialog() },
                    padding = padding,
                )
            }
        }
    }
}

// endregion

// region — Detail body

@Composable
private fun EmployeeDetailBody(
    state: EmployeeDetailUiState,
    onShowDeactivate: () -> Unit,
    onShowResetPin: () -> Unit,
    padding: PaddingValues,
) {
    val employee = state.employee ?: return
    val isActive = employee.isActive == 1
    val isClockedIn = employee.isClockedIn == true
    val hasPin = employee.hasPin == 1
    val displayName = listOfNotNull(employee.firstName, employee.lastName)
        .joinToString(" ")
        .ifBlank { employee.username ?: "Unknown" }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // ── Header ──────────────────────────────────────────────────────────
        item {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.fillMaxWidth().padding(20.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    val initial = (employee.firstName?.firstOrNull()
                        ?: employee.username?.firstOrNull())
                        ?.uppercase().orEmpty()
                    Box(
                        modifier = Modifier
                            .size(72.dp)
                            .background(MaterialTheme.colorScheme.primaryContainer, CircleShape),
                        contentAlignment = Alignment.Center,
                    ) {
                        if (initial.isNotBlank()) {
                            Text(
                                text = initial,
                                style = MaterialTheme.typography.headlineMedium,
                                fontWeight = FontWeight.SemiBold,
                                color = MaterialTheme.colorScheme.onPrimaryContainer,
                            )
                        } else {
                            Icon(
                                Icons.Default.Person, contentDescription = null,
                                modifier = Modifier.size(36.dp),
                                tint = MaterialTheme.colorScheme.onPrimaryContainer,
                            )
                        }
                    }
                    Text(
                        text = displayName,
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.SemiBold,
                    )
                    employee.role?.let {
                        Text(
                            text = it.replaceFirstChar { c -> c.uppercase() },
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        StatusChip(label = if (isActive) "Active" else "Inactive", colored = isActive)
                        if (isClockedIn) {
                            StatusChip(label = "Clocked in", colored = true, color = SuccessGreen)
                        }
                        if (hasPin) StatusChip(label = "PIN set", colored = true)
                    }
                }
            }
        }

        // ── Contact ─────────────────────────────────────────────────────────
        item {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("Contact", style = MaterialTheme.typography.titleSmall)
                    DetailRow(Icons.Default.Person, "Username", employee.username ?: "—")
                    DetailRow(Icons.Default.Email, "Email", employee.email ?: "—")
                    DetailRow(Icons.Default.Badge, "Role", employee.role ?: "—")
                }
            }
        }

        // ── Account ─────────────────────────────────────────────────────────
        item {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("Account", style = MaterialTheme.typography.titleSmall)
                    DetailRow(Icons.Default.Lock, "PIN",
                        if (hasPin) "Configured" else "Not set")
                    DetailRow(Icons.Default.Schedule, "Created", employee.createdAt ?: "—")
                    DetailRow(Icons.Default.Schedule, "Updated", employee.updatedAt ?: "—")
                }
            }
        }

        // ── §14.2 L1617/L1618 — Performance + Commission ────────────────────
        item {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("Performance (this week)", style = MaterialTheme.typography.titleSmall)
                    if (state.performanceLoading) {
                        CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                    } else {
                        val p = state.performance
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            PerformanceTile(
                                modifier = Modifier.weight(1f),
                                label = "Tickets\nclosed",
                                value = "${p.ticketsClosedThisWeek}",
                            )
                            PerformanceTile(
                                modifier = Modifier.weight(1f),
                                label = "Avg close\n(min)",
                                value = "${p.avgTimeToCloseMinutes}",
                            )
                            PerformanceTile(
                                modifier = Modifier.weight(1f),
                                label = "Revenue",
                                value = "$%.2f".format(p.revenueCents / 100.0),
                            )
                            PerformanceTile(
                                modifier = Modifier.weight(1f),
                                label = "Commission\n(MTD)",
                                value = "$%.2f".format(p.commissionCents / 100.0),
                            )
                        }
                    }
                }
            }
        }

        // ── §14.3 L1629 — Weekly timesheet ──────────────────────────────────
        item {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("Timesheet (this week)", style = MaterialTheme.typography.titleSmall)
                    if (state.timesheetLoading) {
                        CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                    } else if (state.weeklyTimesheet.isEmpty()) {
                        Text(
                            "No timesheet data",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    } else {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceEvenly,
                        ) {
                            state.weeklyTimesheet.forEach { day ->
                                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                    Text(
                                        text = day.label,
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                    Text(
                                        text = if (day.hoursWorked > 0) "%.1f".format(day.hoursWorked) else "—",
                                        style = MaterialTheme.typography.bodySmall,
                                        fontWeight = if (day.hoursWorked > 0) FontWeight.SemiBold else FontWeight.Normal,
                                        color = if (day.hoursWorked > 0) MaterialTheme.colorScheme.onSurface
                                        else MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── §14.2 L1621/L1622 — Admin actions ───────────────────────────────
        if (state.isAdmin) {
            item {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("Admin actions", style = MaterialTheme.typography.titleSmall)
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            OutlinedButton(
                                onClick = onShowResetPin,
                                modifier = Modifier.weight(1f),
                            ) {
                                Icon(
                                    Icons.Default.Lock,
                                    contentDescription = null,
                                    modifier = Modifier.size(16.dp),
                                )
                                Spacer(Modifier.width(4.dp))
                                Text("Reset PIN")
                            }
                            Button(
                                onClick = onShowDeactivate,
                                modifier = Modifier.weight(1f),
                                colors = ButtonDefaults.buttonColors(
                                    containerColor = MaterialTheme.colorScheme.errorContainer,
                                    contentColor = MaterialTheme.colorScheme.onErrorContainer,
                                ),
                            ) {
                                Icon(
                                    Icons.Default.PersonOff,
                                    contentDescription = null,
                                    modifier = Modifier.size(16.dp),
                                )
                                Spacer(Modifier.width(4.dp))
                                Text("Deactivate")
                            }
                        }
                    }
                }
            }
        }

        item { Spacer(Modifier.height(16.dp)) }
    }
}

// endregion

// region — sub-components

@Composable
private fun PerformanceTile(label: String, value: String, modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier,
        color = MaterialTheme.colorScheme.surfaceVariant,
        shape = MaterialTheme.shapes.small,
    ) {
        Column(
            modifier = Modifier.padding(8.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(
                text = value,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                text = label,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun DetailRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    value: String,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Icon(
            icon, contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(20.dp),
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = label,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                text = value,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}

@Composable
private fun StatusChip(
    label: String,
    colored: Boolean,
    color: androidx.compose.ui.graphics.Color = MaterialTheme.colorScheme.primary,
) {
    AssistChip(
        onClick = {},
        label = { Text(label, style = MaterialTheme.typography.labelMedium) },
        colors = if (colored) {
            AssistChipDefaults.assistChipColors(
                containerColor = color.copy(alpha = 0.18f),
                labelColor = color,
            )
        } else {
            AssistChipDefaults.assistChipColors()
        },
    )
}

// endregion
