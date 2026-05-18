package com.bizarreelectronics.crm.ui.screens.appointments

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.dto.AppointmentItem
import com.bizarreelectronics.crm.ui.screens.appointments.components.QuickAppointmentDraft
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.util.Date
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import javax.inject.Inject

// ---------------------------------------------------------------------------
// View mode enum (L1419)
// ---------------------------------------------------------------------------

enum class AppointmentViewMode(val label: String) {
    Agenda("Agenda"),
    Day("Day"),
    Week("Week"),
    Month("Month"),
    /** §10.1 Tablet time-block Kanban (columns = employees, rows = time slots). */
    Kanban("Kanban"),
}

// ---------------------------------------------------------------------------
// Filter state (L1425)
// ---------------------------------------------------------------------------

data class AppointmentFilter(
    val employeeId: Long? = null,
    val employeeName: String? = null,
    val location: String? = null,
    val type: String? = null,
)

// ---------------------------------------------------------------------------
// UI state
// ---------------------------------------------------------------------------

data class AppointmentListUiState(
    val appointments: List<AppointmentItem> = emptyList(),
    val isLoading: Boolean = true,
    val error: String? = null,
    val viewMode: AppointmentViewMode = AppointmentViewMode.Agenda,
    val selectedDate: LocalDate = LocalDate.now(),
    val filter: AppointmentFilter = AppointmentFilter(),
    val toastMessage: String? = null,
) {
    /** Appointments filtered by current [AppointmentFilter]. */
    val filtered: List<AppointmentItem>
        get() = appointments.filter { appt ->
            (filter.employeeId == null || appt.employeeId == filter.employeeId) &&
                (filter.location == null || appt.location?.equals(filter.location, ignoreCase = true) == true) &&
                (filter.type == null || appt.type?.equals(filter.type, ignoreCase = true) == true)
        }
}

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

@HiltViewModel
class AppointmentListViewModel @Inject constructor(
    private val appointmentRepository: AppointmentRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(AppointmentListUiState())
    val state = _state.asStateFlow()

    private var loadJob: Job? = null

    init {
        load()
    }

    fun load() {
        loadJob?.cancel()
        loadJob = viewModelScope.launch {
            _state.update { it.copy(isLoading = true, error = null) }
            // BUGHUNT-2026-05-17: runCatching silently catches
            // CancellationException, so the previous-load cancellation
            // briefly flashed "cancelled" into the error field before the
            // new load finished. try/catch with explicit re-throw keeps
            // structured concurrency intact.
            try {
                val list = appointmentRepository.getAppointments()
                _state.update { it.copy(appointments = list, isLoading = false) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { it.copy(isLoading = false, error = e.message ?: "Failed to load appointments") }
            }
        }
    }

    fun setViewMode(mode: AppointmentViewMode) {
        _state.update { it.copy(viewMode = mode) }
    }

    fun setSelectedDate(date: LocalDate) {
        _state.update { it.copy(selectedDate = date) }
    }

    fun jumpToToday() {
        _state.update { it.copy(selectedDate = LocalDate.now()) }
    }

    fun setFilter(filter: AppointmentFilter) {
        _state.update { it.copy(filter = filter) }
    }

    fun clearToast() {
        _state.update { it.copy(toastMessage = null) }
    }

    // ---------------------------------------------------------------------------
    // §10.3 Quick-create (minimal form) — title + start/end only
    // ---------------------------------------------------------------------------

    fun quickCreate(draft: QuickAppointmentDraft) {
        viewModelScope.launch {
            val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).apply {
                timeZone = TimeZone.getDefault()
            }
            val body = mapOf(
                "title" to draft.title,
                "start_time" to fmt.format(Date(draft.startMillis)),
                "end_time" to fmt.format(Date(draft.endMillis)),
            )
            // BUGHUNT-2026-05-17: runCatching swallowed CancellationException;
            // nav cancel mid-POST + retap could DUPLICATE the appointment row.
            try {
                val created = appointmentRepository.quickCreate(body)
                _state.update { s ->
                    s.copy(
                        appointments = s.appointments + created,
                        toastMessage = "Appointment saved",
                    )
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { it.copy(toastMessage = "Save failed: ${e.message}") }
            }
        }
    }

    // ---------------------------------------------------------------------------
    // §10.1 Kanban drag-to-reschedule
    // ---------------------------------------------------------------------------

    fun kanbanReschedule(appointmentId: Long, newEmployeeName: String, newHour: Int) {
        viewModelScope.launch {
            val body = mapOf(
                "employee_name" to newEmployeeName,
                "start_hour" to newHour,
            )
            // BUGHUNT-2026-05-17: runCatching swallowed CancellationException;
            // drag-cancel mid-PATCH + retap could DOUBLE-PATCH or PATCH to
            // a different slot, leaving inconsistent server state.
            try {
                val updated = appointmentRepository.reschedule(appointmentId, body)
                _state.update { s ->
                    s.copy(
                        appointments = s.appointments.map { a ->
                            if (a.id == appointmentId) updated else a
                        },
                        toastMessage = "Rescheduled",
                    )
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { it.copy(toastMessage = "Reschedule failed: ${e.message}") }
            }
        }
    }
}
