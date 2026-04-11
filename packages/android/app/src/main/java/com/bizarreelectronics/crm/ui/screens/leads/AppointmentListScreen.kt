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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.LeadApi
import com.bizarreelectronics.crm.data.remote.dto.AppointmentDetail
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

private val DAY_HEADER_FORMAT: SimpleDateFormat
    get() = SimpleDateFormat("EEEE, MMM d, yyyy", Locale.US)

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
    DAY_HEADER_FORMAT.format(Date(millis))

/** Returns the YYYY-MM-DD bucket key for an appointment based on its start_time. */
private fun appointmentDayKey(startTime: String?): String {
    if (startTime.isNullOrBlank()) return "unknown"
    return startTime.take(10)
}

/** Status display metadata. */
data class AppointmentStatusMeta(
    val key: String,
    val label: String,
    val color: Color,
)

internal val APPOINTMENT_STATUSES = listOf(
    AppointmentStatusMeta("scheduled", "Scheduled", Color(0xFF3B82F6)), // blue
    AppointmentStatusMeta("completed", "Completed", Color(0xFF16A34A)), // green
    AppointmentStatusMeta("cancelled", "Cancelled", Color(0xFF6B7280)), // gray
    AppointmentStatusMeta("no_show", "No Show", Color(0xFFDC2626)),     // red
)

internal fun appointmentStatusMeta(status: String?): AppointmentStatusMeta {
    val normalized = status?.lowercase()?.trim().orEmpty()
    return APPOINTMENT_STATUSES.firstOrNull { it.key == normalized }
        ?: AppointmentStatusMeta(normalized, status ?: "Unknown", Color(0xFF6B7280))
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
                actions = {
                    IconButton(onClick = { showDatePicker = true }) {
                        Icon(Icons.Default.CalendarMonth, contentDescription = "Pick date")
                    }
                    IconButton(onClick = { viewModel.loadAppointments() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
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
                    OfflineEmptyState()
                }
                state.isLoading -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator()
                    }
                }
                state.error != null -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(state.error ?: "Error", color = MaterialTheme.colorScheme.error)
                            Spacer(modifier = Modifier.height(8.dp))
                            TextButton(onClick = { viewModel.loadAppointments() }) { Text("Retry") }
                        }
                    }
                }
                state.appointments.isEmpty() -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Icon(
                                Icons.Default.EventBusy,
                                contentDescription = null,
                                modifier = Modifier.size(48.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                            Text(
                                "No appointments",
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
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
private fun OfflineEmptyState() {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(
                Icons.Default.CloudOff,
                contentDescription = null,
                modifier = Modifier.size(48.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                "Appointments require online connection",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
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
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
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
        if (date != null) DAY_HEADER_FORMAT.format(date) else dayKey
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
                StatusBadge(meta = meta)
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

@Composable
private fun StatusBadge(meta: AppointmentStatusMeta) {
    Surface(
        shape = MaterialTheme.shapes.small,
        color = meta.color,
    ) {
        Text(
            meta.label,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
            style = MaterialTheme.typography.labelSmall,
            color = Color.White,
            fontWeight = FontWeight.Medium,
        )
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
