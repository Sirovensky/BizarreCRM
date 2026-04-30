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
import java.time.Instant
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
    /**
     * Whether the recurring-edit scope dialog is showing (item 5).
     * Set to true when the user taps Save on a recurring appointment (rrule != null).
     */
    val showRecurringEditDialog: Boolean = false,
    /**
     * Selected scope in the recurring-edit dialog.
     * One of "single" | "future" | "all". Defaults to "single".
     */
    val pendingRecurringScope: String = "single",
    /**
     * The PATCH body buffered while waiting for the user to choose an edit scope.
     * Dispatched once [confirmRecurringEdit] is called.
     */
    val pendingPatchBody: Map<String, Any?>? = null,
    // §10.6 Check-in / check-out
    /**
     * Epoch-millis timestamp when the customer was checked in during this session.
     * Null = not yet checked in. Persisted in ViewModel only (no server column yet);
     * the server receives a status change to "in_progress" / "completed".
     */
    val localCheckedInAt: Long? = null,
    /**
     * Epoch-millis timestamp when the customer was checked out during this session.
     * Null = not yet checked out.
     */
    val localCheckedOutAt: Long? = null,
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
    // §10.6 Check-in / check-out
    // ---------------------------------------------------------------------------

    /**
     * Stamps the customer as arrived. Updates appointment status to "in_progress"
     * on the server and records a local timestamp for the elapsed-time display.
     * If the appointment has a linked ticket, the server is expected to start
     * a bench timer for that ticket (server-side; client emits status only).
     */
    fun checkIn() {
        val now = Instant.now().toEpochMilli()
        _state.update { it.copy(localCheckedInAt = now, localCheckedOutAt = null) }
        patch(
            body = mapOf("status" to "in_progress"),
            optimisticUpdate = { appt -> appt.copy(status = "in_progress") },
        ) {
            _state.update { it.copy(toastMessage = "Customer checked in") }
        }
    }

    /**
     * Stamps the customer as departed. Updates appointment status to "completed"
     * on the server and records a local check-out timestamp.
     */
    fun checkOut() {
        val now = Instant.now().toEpochMilli()
        _state.update { it.copy(localCheckedOutAt = now) }
        patch(
            body = mapOf("status" to "completed"),
            optimisticUpdate = { appt -> appt.copy(status = "completed") },
        ) {
            _state.update { it.copy(toastMessage = "Customer checked out") }
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
    // Recurring-edit scope dialog (item 5)
    // ---------------------------------------------------------------------------

    /**
     * Call instead of [patch] when the appointment has an rrule. Shows the scope
     * dialog and buffers [body] until the user confirms their choice.
     */
    fun requestRecurringEdit(body: Map<String, Any?>) {
        val isRecurring = _state.value.appointment?.rrule?.isNotBlank() == true ||
            _state.value.appointment?.recurrenceParentId != null
        if (isRecurring) {
            _state.update { it.copy(showRecurringEditDialog = true, pendingPatchBody = body) }
        } else {
            patch(body, optimisticUpdate = { it })
        }
    }

    fun updateRecurringScope(scope: String) {
        _state.update { it.copy(pendingRecurringScope = scope) }
    }

    fun confirmRecurringEdit() {
        val body = _state.value.pendingPatchBody ?: return
        val scope = _state.value.pendingRecurringScope
        _state.update { it.copy(showRecurringEditDialog = false, pendingPatchBody = null) }
        patch(
            body = body + mapOf("edit_scope" to scope),
            optimisticUpdate = { it },
        )
    }

    fun dismissRecurringEditDialog() {
        _state.update { it.copy(showRecurringEditDialog = false, pendingPatchBody = null) }
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
