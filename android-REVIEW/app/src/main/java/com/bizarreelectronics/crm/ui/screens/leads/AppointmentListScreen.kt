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
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
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
import java.time.DayOfWeek
import java.time.LocalDate
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import javax.inject.Inject

// ─── View-mode toggle ─────────────────────────────────────────────────────────

/**
 * View mode for the Appointments screen (ActionPlan §10).
 *
 * [DAY] shows the existing single-day picker + list.
 * [WEEK] shows [AppointmentWeekView] — a 7-column week grid.
 */
enum class AppointmentViewMode { DAY, WEEK }

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
    onAppointmentClick: (Long) -> Unit = {},
    viewModel: AppointmentListViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    // @audit-fixed: was remember { mutableStateOf(false) } — picker silently
    // dismissed on rotation, surprising users mid-edit. rememberSaveable
    // persists the open/closed state across configuration changes.
    var showDatePicker by androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf(false) }

    // §10: view-mode toggle — Day (default) or Week.
    var viewMode by remember { mutableStateOf(AppointmentViewMode.DAY) }

    // Week-start anchored to Monday (ISO 8601). Immutable: LocalDate.with() returns
    // a new instance. rememberSaveable not needed — week navigates via buttons.
    var weekStart by remember {
        mutableStateOf(LocalDate.now().with(DayOfWeek.MONDAY))
    }

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
                    // §10: Day / Week view-mode toggle pair (mirrors §9 List/Kanban pattern).
                    IconButton(
                        onClick = { viewMode = AppointmentViewMode.DAY },
                        modifier = Modifier.semantics {
                            contentDescription = if (viewMode == AppointmentViewMode.DAY)
                                "Day view, selected"
                            else
                                "Switch to day view"
                        },
                    ) {
                        Icon(
                            Icons.Default.ViewDay,
                            contentDescription = null,
                            tint = if (viewMode == AppointmentViewMode.DAY)
                                MaterialTheme.colorScheme.primary
                            else
                                MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    IconButton(
                        onClick = { viewMode = AppointmentViewMode.WEEK },
                        modifier = Modifier.semantics {
                            contentDescription = if (viewMode == AppointmentViewMode.WEEK)
                                "Week view, selected"
                            else
                                "Switch to week view"
                        },
                    ) {
                        Icon(
                            Icons.Default.ViewWeek,
                            contentDescription = null,
                            tint = if (viewMode == AppointmentViewMode.WEEK)
                                MaterialTheme.colorScheme.primary
                            else
                                MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    IconButton(onClick = { showDatePicker = true }) {
                        // a11y: descriptive label mirrors "Pick date" intent
                        Icon(
                            Icons.Default.CalendarMonth,
                            contentDescription = "Pick date",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    IconButton(onClick = { viewModel.loadAppointments() }) {
                        // a11y: screen-specific label — mirrors "Refresh tickets" / "Refresh expenses" pattern
                        Icon(
                            Icons.Default.Refresh,
                            contentDescription = "Refresh appointments",
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
                // a11y: spec §26 — "Create new appointment" (imperative, mirrors "Create new ticket")
                Icon(Icons.Default.Add, contentDescription = "Create new appointment")
            }
        },
    ) { padding ->
        // §10: when Week mode is active, bypass the day-picker flow entirely and
        // render the week composable using the full appointments list from the VM.
        // Client-side filter to the current week avoids a new network call this wave.
        if (viewMode == AppointmentViewMode.WEEK) {
            val weekEnd = weekStart.plusDays(6)
            // Filter to appointments whose start_time falls within [weekStart, weekEnd].
            // Immutable: filter + sortedBy return new lists.
            val weekAppointments = state.appointments
                .filter { appt ->
                    val d = appt.startTime?.take(10)?.let {
                        try { LocalDate.parse(it) } catch (_: Exception) { null }
                    } ?: return@filter false
                    !d.isBefore(weekStart) && !d.isAfter(weekEnd)
                }
                .sortedBy { it.startTime ?: "" }

            AppointmentWeekView(
                appointments = weekAppointments,
                weekStart = weekStart,
                onWeekPrev = { weekStart = weekStart.minusWeeks(1) },
                onWeekNext = { weekStart = weekStart.plusWeeks(1) },
                onAppointmentClick = onAppointmentClick,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
            )
            return@Scaffold
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            // Selected date header
            // a11y: liveRegion=Polite so TalkBack re-announces when the date or count changes
            // after the user picks a new day. mergeDescendants collapses "Selected date",
            // the formatted date, and the count into one coherent sentence.
            val selectedDateLabel = formatDayHeader(state.selectedDateMillis)
            val countLabel = if (!state.isLoading) {
                val n = state.appointments.size
                if (n == 1) "1 appointment" else "$n appointments"
            } else {
                "loading"
            }
            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics(mergeDescendants = true) {
                        // a11y: live region so date/count changes are announced automatically
                        liveRegion = LiveRegionMode.Polite
                        contentDescription = "Selected date: $selectedDateLabel, $countLabel"
                    },
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
                            selectedDateLabel,
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
                    // a11y: mergeDescendants collapses the decorative icon + title + subtitle
                    // into one TalkBack node so the offline state reads as a single announcement.
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .semantics(mergeDescendants = true) {},
                        contentAlignment = Alignment.TopCenter,
                    ) {
                        EmptyState(
                            icon = Icons.Default.CloudOff,
                            title = "Offline",
                            subtitle = "Appointments require an online connection",
                        )
                    }
                }
                state.isLoading -> {
                    // a11y: mergeDescendants + contentDescription so TalkBack announces
                    // "Loading appointments" on a single focus stop rather than each shimmer
                    // box individually.
                    Box(
                        modifier = Modifier.semantics(mergeDescendants = true) {
                            contentDescription = "Loading appointments"
                        },
                    ) {
                        BrandSkeleton(
                            rows = 5,
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                        )
                    }
                }
                state.error != null -> {
                    // a11y: liveRegion=Assertive so TalkBack interrupts immediately and
                    // tells the user about the error rather than leaving them in silence.
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .semantics { liveRegion = LiveRegionMode.Assertive },
                        contentAlignment = Alignment.Center,
                    ) {
                        ErrorState(
                            message = state.error ?: "Error",
                            onRetry = { viewModel.loadAppointments() },
                        )
                    }
                }
                state.appointments.isEmpty() -> {
                    // a11y: mergeDescendants collapses the decorative icon + title + subtitle
                    // into one TalkBack node so the empty state reads as a single announcement.
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .semantics(mergeDescendants = true) {},
                        contentAlignment = Alignment.TopCenter,
                    ) {
                        EmptyState(
                            icon = Icons.Default.EventBusy,
                            title = "No appointments",
                            subtitle = "Nothing scheduled for this day",
                        )
                    }
                }
                else -> {
                    @OptIn(ExperimentalMaterial3Api::class)
                    PullToRefreshBox(
                        isRefreshing = state.isRefreshing,
                        onRefresh = { viewModel.refresh() },
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        AppointmentList(
                            appointments = state.appointments,
                            onAppointmentClick = onAppointmentClick,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun AppointmentList(
    appointments: List<AppointmentDetail>,
    onAppointmentClick: (Long) -> Unit = {},
) {
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
                AppointmentCard(appointment = appointment, onClick = { onAppointmentClick(appointment.id) })
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
    // a11y: heading() lets TalkBack users swipe by headings to jump between day groups
    Text(
        label,
        modifier = Modifier
            .padding(top = 8.dp, bottom = 4.dp)
            .semantics { heading() },
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.primary,
    )
}

@Composable
private fun AppointmentCard(appointment: AppointmentDetail, onClick: () -> Unit = {}) {
    val meta = appointmentStatusMeta(appointment.status)

    // a11y: build the announcement string once. The card is visually tappable (Row with
    // clickable), so Role.Button is appropriate. mergeDescendants collapses time label +
    // title + customer name + status badge into one TalkBack focus stop.
    val timeLabel = DateFormatter.formatDateTime(appointment.startTime)
    val titleLabel = appointment.title?.takeIf { it.isNotBlank() } ?: "Untitled"
    val customerLabel = appointment.customerName?.takeIf { it.isNotBlank() }
    val cardA11yDesc = buildString {
        append("Appointment at $timeLabel")
        if (customerLabel != null) append(" with $customerLabel")
        append(" for $titleLabel")
        append(". ${meta.label}.")
        append(" Tap to open.")
    }

    Card(
        onClick = onClick,
        modifier = Modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {
                // a11y: single focus stop with full context; Role.Button signals it is activatable
                contentDescription = cardA11yDesc
                role = Role.Button
            },
    ) {
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
