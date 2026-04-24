package com.bizarreelectronics.crm.ui.screens.appointments

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.dto.AppointmentItem
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.LocalDate
import javax.inject.Inject

// ---------------------------------------------------------------------------
// View mode enum (L1419)
// ---------------------------------------------------------------------------

enum class AppointmentViewMode(val label: String) {
    Agenda("Agenda"),
    Day("Day"),
    Week("Week"),
    Month("Month"),
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
            runCatching { appointmentRepository.getAppointments() }
                .onSuccess { list ->
                    _state.update { it.copy(appointments = list, isLoading = false) }
                }
                .onFailure { e ->
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
}
