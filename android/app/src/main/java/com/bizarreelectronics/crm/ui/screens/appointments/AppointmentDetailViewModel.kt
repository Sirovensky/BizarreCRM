package com.bizarreelectronics.crm.ui.screens.appointments

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.TicketApi
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
)

@HiltViewModel
class AppointmentDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val repository: AppointmentRepository,
    private val ticketApi: TicketApi,
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
    // §10.6 Check-in / check-out
    // ---------------------------------------------------------------------------

    /**
     * Customer arrived: POST /appointments/{id}/check-in.
     *
     * On success the server returns status="checked_in" + checked_in_at timestamp.
     * If the appointment is linked to a ticket, we also fire a bench timer-start
     * on that ticket so the tech's repair clock begins at check-in time.
     *
     * 404 fallback: older server versions that do not expose /check-in yet;
     * we fall back to PATCH status="checked_in" so the UI still updates.
     */
    fun markCheckedIn() {
        val current = _state.value.appointment ?: return
        _state.update {
            it.copy(
                isSaving = true,
                // Optimistic: update status immediately so the card re-renders.
                appointment = current.copy(status = "checked_in"),
            )
        }
        viewModelScope.launch {
            runCatching { repository.checkIn(appointmentId) }
                .onSuccess { updated ->
                    _state.update { it.copy(appointment = updated, isSaving = false, toastMessage = "Customer arrived") }
                    // Start bench timer for the linked ticket (fail-open: 404 tolerated).
                    current.linkedTicketId?.let { ticketId ->
                        runCatching { ticketApi.startBenchTimer(ticketId) }
                    }
                }
                .onFailure { e ->
                    if (e.message?.contains("404") == true || e.message?.contains("Not Found") == true) {
                        // Fallback: older server; use PATCH status instead.
                        patch(
                            body = mapOf("status" to "checked_in"),
                            optimisticUpdate = { it.copy(status = "checked_in") },
                            onSuccess = {
                                _state.update { s -> s.copy(toastMessage = "Customer arrived") }
                                current.linkedTicketId?.let { tid ->
                                    viewModelScope.launch { runCatching { ticketApi.startBenchTimer(tid) } }
                                }
                            },
                        )
                    } else {
                        // Real error — revert optimistic update.
                        _state.update {
                            it.copy(
                                appointment = current,
                                isSaving = false,
                                toastMessage = "Check-in failed: ${e.message}",
                            )
                        }
                    }
                }
        }
    }

    /**
     * Customer departed: POST /appointments/{id}/check-out.
     *
     * On success the server returns status="completed" + checked_out_at timestamp.
     *
     * 404 fallback: PATCH status="completed".
     */
    fun markCheckedOut() {
        val current = _state.value.appointment ?: return
        _state.update {
            it.copy(
                isSaving = true,
                appointment = current.copy(status = "completed"),
            )
        }
        viewModelScope.launch {
            runCatching { repository.checkOut(appointmentId) }
                .onSuccess { updated ->
                    _state.update { it.copy(appointment = updated, isSaving = false, toastMessage = "Customer departed") }
                }
                .onFailure { e ->
                    if (e.message?.contains("404") == true || e.message?.contains("Not Found") == true) {
                        patch(
                            body = mapOf("status" to "completed"),
                            optimisticUpdate = { it.copy(status = "completed") },
                            onSuccess = {
                                _state.update { s -> s.copy(toastMessage = "Customer departed") }
                            },
                        )
                    } else {
                        _state.update {
                            it.copy(
                                appointment = current,
                                isSaving = false,
                                toastMessage = "Check-out failed: ${e.message}",
                            )
                        }
                    }
                }
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
