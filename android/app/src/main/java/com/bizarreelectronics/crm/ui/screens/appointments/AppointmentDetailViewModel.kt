package com.bizarreelectronics.crm.ui.screens.appointments

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.dto.AppointmentItem
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import javax.inject.Inject

data class AppointmentDetailUiState(
    val appointment: AppointmentItem? = null,
    val isLoading: Boolean = true,
    val error: String? = null,
    val isSaving: Boolean = false,
    val toastMessage: String? = null,
    val navigateBack: Boolean = false,
    /** Non-null when a conflict is detected with another appointment for the same employee. */
    val conflictWarning: String? = null,
    /** Whether the cancel+notify dialog is showing. */
    val showCancelDialog: Boolean = false,
)

@HiltViewModel
class AppointmentDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val repository: AppointmentRepository,
) : ViewModel() {

    private val appointmentId: Long = checkNotNull(savedStateHandle["appointmentId"])

    private val _state = MutableStateFlow(AppointmentDetailUiState())
    val state = _state.asStateFlow()

    init {
        load()
    }

    fun load() {
        viewModelScope.launch {
            _state.update { it.copy(isLoading = true, error = null) }
            runCatching { repository.getAppointmentById(appointmentId) }
                .onSuccess { appt ->
                    _state.update { it.copy(appointment = appt, isLoading = false) }
                }
                .onFailure { e ->
                    _state.update { it.copy(isLoading = false, error = e.message ?: "Failed to load") }
                }
        }
    }

    // ---------------------------------------------------------------------------
    // Reminder offset (L1429)
    // ---------------------------------------------------------------------------

    fun setReminderOffset(minutes: Int?) {
        val body = mapOf("reminder_offset_minutes" to minutes)
        patch(body, optimisticUpdate = { appt ->
            appt.copy(reminderOffsetMinutes = minutes)
        })
    }

    // ---------------------------------------------------------------------------
    // Quick action: confirm (L1430)
    // ---------------------------------------------------------------------------

    fun markConfirmed() {
        patch(mapOf("status" to "confirmed"), optimisticUpdate = { it.copy(status = "confirmed") })
    }

    // ---------------------------------------------------------------------------
    // Quick action: no-show (L1444)
    // ---------------------------------------------------------------------------

    fun markNoShow() {
        patch(mapOf("status" to "no_show"), optimisticUpdate = { it.copy(status = "no_show") }) {
            _state.update { it.copy(toastMessage = "Marked as no-show") }
        }
    }

    // ---------------------------------------------------------------------------
    // Quick action: cancel dialog (L1443)
    // ---------------------------------------------------------------------------

    fun requestCancel() {
        _state.update { it.copy(showCancelDialog = true) }
    }

    fun dismissCancelDialog() {
        _state.update { it.copy(showCancelDialog = false) }
    }

    fun confirmCancel(notifyCustomer: Boolean) {
        _state.update { it.copy(showCancelDialog = false, isSaving = true) }
        viewModelScope.launch {
            runCatching { repository.cancelAppointment(appointmentId, notifyCustomer) }
                .onSuccess {
                    _state.update { it.copy(isSaving = false, navigateBack = true) }
                }
                .onFailure { e ->
                    _state.update { it.copy(isSaving = false, toastMessage = "Cancel failed: ${e.message}") }
                }
        }
    }

    // ---------------------------------------------------------------------------
    // Send reminder (L1431)
    // ---------------------------------------------------------------------------

    fun sendReminder() {
        viewModelScope.launch {
            runCatching { repository.sendReminder(appointmentId) }
                .onSuccess { sent ->
                    val msg = if (sent) "Reminder sent" else "Reminder send failed"
                    _state.update { it.copy(toastMessage = msg) }
                }
                .onFailure {
                    // 404 tolerated
                    _state.update { it.copy(toastMessage = "Reminder unavailable") }
                }
        }
    }

    // ---------------------------------------------------------------------------
    // Conflict detection (L1438) — local-only check against loaded appointments
    // ---------------------------------------------------------------------------

    /**
     * Checks if a proposed start/end interval overlaps any existing appointments
     * for the same employee (excluding the current one). Returns a warning message
     * or null if no conflict.
     */
    fun detectConflict(allAppointments: List<AppointmentItem>): String? {
        val current = _state.value.appointment ?: return null
        val employeeId = current.employeeId ?: return null
        val currentStart = current.startTime?.let { parseDateTime(it) } ?: return null
        val currentEnd = current.endTime?.let { parseDateTime(it) }
            ?: currentStart.plusMinutes((current.durationMinutes ?: 60).toLong())

        val conflict = allAppointments.firstOrNull { other ->
            other.id != appointmentId &&
                other.employeeId == employeeId &&
                other.status !in listOf("cancelled", "no_show") &&
                run {
                    val otherStart = other.startTime?.let { parseDateTime(it) } ?: return@run false
                    val otherEnd = other.endTime?.let { parseDateTime(it) }
                        ?: otherStart.plusMinutes((other.durationMinutes ?: 60).toLong())
                    currentStart < otherEnd && otherStart < currentEnd
                }
        }

        return conflict?.let { other ->
            val time = other.startTime?.take(5) ?: "?"
            "Overlaps with ${other.customerName ?: "another appointment"} at $time"
        }
    }

    // ---------------------------------------------------------------------------
    // Housekeeping
    // ---------------------------------------------------------------------------

    fun clearToast() = _state.update { it.copy(toastMessage = null) }
    fun consumeNavigateBack() = _state.update { it.copy(navigateBack = false) }
    fun clearConflict() = _state.update { it.copy(conflictWarning = null) }

    // ---------------------------------------------------------------------------
    // Private helpers
    // ---------------------------------------------------------------------------

    private fun patch(
        body: Map<String, Any?>,
        optimisticUpdate: (AppointmentItem) -> AppointmentItem,
        onSuccess: (() -> Unit)? = null,
    ) {
        val current = _state.value.appointment ?: return
        _state.update { it.copy(appointment = optimisticUpdate(current), isSaving = true) }
        viewModelScope.launch {
            runCatching { repository.patchAppointment(appointmentId, body) }
                .onSuccess { updated ->
                    _state.update { it.copy(appointment = updated, isSaving = false) }
                    onSuccess?.invoke()
                }
                .onFailure { e ->
                    // Revert optimistic update
                    _state.update { it.copy(appointment = current, isSaving = false, toastMessage = e.message) }
                }
        }
    }

    private fun parseDateTime(iso: String): LocalDateTime? = runCatching {
        LocalDateTime.parse(iso, DateTimeFormatter.ISO_DATE_TIME)
    }.getOrElse {
        runCatching { LocalDateTime.parse(iso) }.getOrNull()
    }
}
