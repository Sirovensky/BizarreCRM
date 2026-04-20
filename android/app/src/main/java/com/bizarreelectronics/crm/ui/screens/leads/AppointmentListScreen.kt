package com.bizarreelectronics.crm.ui.screens.leads

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.LeadApi
import com.bizarreelectronics.crm.data.remote.dto.AppointmentDetail
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandStatusBadge
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.util.DateFormatter
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

private val SERVER_DATE_FORMAT: SimpleDateFormat
    get() = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }

// CROSS46: day-header rendering now routes through the canonical
// DateFormatter.formatAbsolute ("April 16, 2026") instead of the previous
// "EEEE, MMM d, yyyy" pattern. DAY_KEY_FORMAT (ISO bucket key) stays.

private val DAY_KEY_FORMAT: SimpleDateFormat
    get() = SimpleDateFormat("yyyy-MM-dd", Locale.US)

private fun startOfDay(millis: Long): Long {
    val cal = Calendar.getInstance().apply {
        timeInMillis = millis
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }
    return cal.timeInMillis
}

private fun endOfDay(millis: Long): Long = startOfDay(millis) + 86_400_000L - 1L

private fun formatServerDate(millis: Long): String =
    SERVER_DATE_FORMAT.format(Date(millis))

private fun formatDayHeader(millis: Long): String =
    com.bizarreelectronics.crm.util.DateFormatter.formatAbsolute(millis)

/** Returns the YYYY-MM-DD bucket key for an appointment based on its start_time. */
private fun appointmentDayKey(startTime: String?): String {
    if (startTime.isNullOrBlank()) return "unknown"
    return startTime.take(10)
}

/**
 * Status label lookup — no hardcoded color. The 5-hue brand discipline is
 * provided by [BrandStatusBadge] via [statusToneFor] in SharedComponents.
 *
 * Mapping:
 *   scheduled → Magenta (highlight)
 *   completed → Success (green)
 *   cancelled → Muted (gray)
 *   no_show   → Error (red)
 */
data class AppointmentStatusMeta(
    val key: String,
    val label: String,
)

internal val APPOINTMENT_STATUSES = listOf(
    AppointmentStatusMeta("scheduled", "Scheduled"),
    AppointmentStatusMeta("completed", "Completed"),
    AppointmentStatusMeta("cancelled", "Cancelled"),
    AppointmentStatusMeta("no_show", "No Show"),
)

internal fun appointmentStatusMeta(status: String?): AppointmentStatusMeta {
    val normalized = status?.lowercase()?.trim().orEmpty()
    return APPOINTMENT_STATUSES.firstOrNull { it.key == normalized }
        ?: AppointmentStatusMeta(normalized, status ?: "Unknown")
}

// ─── UI state ────────────────────────────────────────────────────────────────

data class AppointmentListUiState(
    val appointments: List<AppointmentDetail> = emptyList(),
    val selectedDateMillis: Long = startOfDay(System.currentTimeMillis()),
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val isOffline: Boolean = false,
)

// ─── ViewModel ───────────────────────────────────────────────────────────────

@HiltViewModel
class AppointmentListViewModel @Inject constructor(
    private val leadApi: LeadApi,
    private val serverMonitor: ServerReachabilityMonitor,
) : ViewModel() {

    private val _state = MutableStateFlow(AppointmentListUiState())
    val state = _state.asStateFlow()

    init {
        observeOnlineState()
        loadAppointments()
    }

    private fun observeOnlineState() {
        viewModelScope.launch {
            serverMonitor.isEffectivelyOnline.collect { online ->
                _state.value = _state.value.copy(isOffline = !online)
            }
        }
    }

    fun selectDate(millis: Long) {
        _state.value = _state.value.copy(
            selectedDateMillis = startOfDay(millis),
        )
        loadAppointments()
    }

    fun refresh() {
        _state.value = _state.value.copy(isRefreshing = true)
        loadAppointments()
    }

    fun loadAppointments() {
        viewModelScope.launch {
            if (!_state.value.isRefreshing) {
                _state.value = _state.value.copy(isLoading = true, error = null)
            }
            if (!serverMonitor.isEffectivelyOnline.value) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    isRefreshing = false,
                    appointments = emptyList(),
                    error = "Appointments require online connection",
                )
                return@launch
            }
            try {
                val day = _state.value.selectedDateMillis
                val from = formatServerDate(day)
                val to = formatServerDate(endOfDay(day))
                val response = leadApi.getAppointments(
                    mapOf(
                        "from_date" to from,
                        "to_date" to to,
                        "pagesize" to "200",
                    )
                )
                val appointments = response.data?.appointments ?: emptyList()
                _state.value = _state.value.copy(
                    isLoading = false,
                    isRefreshing = false,
                    appointments = appointments,
                    error = null,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    isRefreshing = false,
                    error = e.message ?: "Failed to load appointments",
                )
            }
        }
    }
}

// ─── Screen ──────────────────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppointmentListScreen(
    onCreateClick: () -> Unit,
    viewModel: AppointmentListViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    // @audit-fixed: was remember { mutableStateOf(false) } — picker silently
    // dismissed on rotation, surprising users mid-edit. rememberSaveable
    // persists the open/closed state across configuration changes.
    var showDatePicker by androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf(false) }

    if (showDatePicker) {
        DatePickerModal(
            initialMillis = state.selectedDateMillis,
            onDismiss = { showDatePicker = false },
            onConfirm = { millis ->
                viewModel.selectDate(millis)
                showDatePicker = false
            },
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Appointments") },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                ),
                actions = {
                    IconButton(onClick = { showDatePicker = true }) {
                        Icon(
                            Icons.Default.CalendarMonth,
                            contentDescription = "Pick date",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    IconButton(onClick = { viewModel.loadAppointments() }) {
                        Icon(
                            Icons.Default.Refresh,
                            contentDescription = "Refresh",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                },
            )
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = onCreateClick,
                containerColor = MaterialTheme.colorScheme.primary,
            ) {
                Icon(Icons.Default.Add, contentDescription = "Create appointment")
            }
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            // Selected date header
            Surface(
                modifier = Modifier.fillMaxWidth(),
                color = MaterialTheme.colorScheme.surfaceVariant,
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column {
                        Text(
                            "Selected date",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            formatDayHeader(state.selectedDateMillis),
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                    if (!state.isLoading) {
                        Text(
                            "${state.appointments.size}",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                }
            }

            when {
                state.isOffline -> {
                    EmptyState(
                        icon = Icons.Default.CloudOff,
                        title = "Offline",
                        subtitle = "Appointments require an online connection",
                    )
                }
                state.isLoading -> {
                    BrandSkeleton(
                        rows = 5,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                }
                state.error != null -> {
                    ErrorState(
                        message = state.error ?: "Error",
                        onRetry = { viewModel.loadAppointments() },
                    )
                }
                state.appointments.isEmpty() -> {
                    EmptyState(
                        icon = Icons.Default.EventBusy,
                        title = "No appointments",
                        subtitle = "Nothing scheduled for this day",
                    )
                }
                else -> {
                    @OptIn(ExperimentalMaterial3Api::class)
                    PullToRefreshBox(
                        isRefreshing = state.isRefreshing,
                        onRefresh = { viewModel.refresh() },
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        AppointmentList(appointments = state.appointments)
                    }
                }
            }
        }
    }
}

@Composable
private fun AppointmentList(appointments: List<AppointmentDetail>) {
    // Group by day key extracted from start_time
    val grouped: Map<String, List<AppointmentDetail>> = appointments
        .sortedBy { it.startTime ?: "" }
        .groupBy { appointmentDayKey(it.startTime) }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        // CROSS16-ext: bottom inset so the last row can scroll above the
        // bottom-nav / gesture area.
        contentPadding = PaddingValues(
            start = 16.dp,
            end = 16.dp,
            top = 12.dp,
            bottom = 80.dp,
        ),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        grouped.forEach { (dayKey, dayAppointments) ->
            item(key = "header-$dayKey") {
                DayHeader(dayKey = dayKey)
            }
            items(dayAppointments, key = { it.id }) { appointment ->
                AppointmentCard(appointment = appointment)
            }
        }
    }
}

@Composable
private fun DayHeader(dayKey: String) {
    val label = try {
        val date = DAY_KEY_FORMAT.parse(dayKey)
        if (date != null) {
            com.bizarreelectronics.crm.util.DateFormatter.formatAbsolute(date.time)
        } else {
            dayKey
        }
    } catch (_: Exception) {
        dayKey
    }
    Text(
        label,
        modifier = Modifier.padding(top = 8.dp, bottom = 4.dp),
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.primary,
    )
}

@Composable
private fun AppointmentCard(appointment: AppointmentDetail) {
    val meta = appointmentStatusMeta(appointment.status)
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        DateFormatter.formatDateTime(appointment.startTime),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        appointment.title?.takeIf { it.isNotBlank() } ?: "(Untitled)",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                    )
                    val customerName = appointment.customerName
                    if (!customerName.isNullOrBlank()) {
                        Text(
                            customerName,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                // 5-hue brand badge replaces the old hardcoded-color StatusBadge
                BrandStatusBadge(
                    label = meta.label,
                    status = meta.key,
                )
            }
            if (!appointment.notes.isNullOrBlank()) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    appointment.notes,
                    style = MaterialTheme.typography.bodySmall,
                    maxLines = 3,
                )
            }
        }
    }
}

// ─── Date picker dialog ──────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DatePickerModal(
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
