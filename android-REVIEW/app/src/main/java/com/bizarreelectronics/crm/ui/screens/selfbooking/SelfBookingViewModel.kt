package com.bizarreelectronics.crm.ui.screens.selfbooking

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.BookingConfirmation
import com.bizarreelectronics.crm.data.remote.api.BookingReserveRequest
import com.bizarreelectronics.crm.data.remote.api.BookingSlot
import com.bizarreelectronics.crm.data.remote.api.SelfBookingApi
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import timber.log.Timber
import java.io.IOException
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import javax.inject.Inject

// ---------------------------------------------------------------------------
// §58.1 / §58.2 — Self-booking screen state machine
//
// Steps:
//   1. SlotSelection — fetch + display available slots for the location/date
//   2. CustomerInfo  — collect name / phone / email / notes
//   3. Confirming    — POST /public/booking/reserve in-flight
//   4. Confirmed     — success; show confirmation code
//   5. Error         — network/server error with retry
//   6. NotAvailable  — server returned 404 (booking disabled or location not found)
// ---------------------------------------------------------------------------

sealed class SelfBookingUiState {
    /** Loading slots from server. */
    object LoadingSlots : SelfBookingUiState()

    /** Slots loaded; customer selects a time. */
    data class SlotSelection(
        val slots: List<BookingSlot>,
        val selectedDate: LocalDate,
        val selectedSlot: BookingSlot?,
    ) : SelfBookingUiState()

    /** Slot chosen; collecting customer contact info. */
    data class CustomerInfo(
        val slot: BookingSlot,
        val name: String = "",
        val phone: String = "",
        val email: String = "",
        val service: String = "",
        val notes: String = "",
    ) : SelfBookingUiState()

    /** Reservation POST in-flight. */
    object Confirming : SelfBookingUiState()

    /** Reservation succeeded. */
    data class Confirmed(val confirmation: BookingConfirmation) : SelfBookingUiState()

    /** Server returned 404 — location not found or booking disabled. */
    object NotAvailable : SelfBookingUiState()

    /** Network or server error with a retry action. */
    data class Error(val message: String) : SelfBookingUiState()
}

@HiltViewModel
class SelfBookingViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val selfBookingApi: SelfBookingApi,
) : ViewModel() {

    private val locationId: String = savedStateHandle.get<String>("locationId").orEmpty()

    private val _state = MutableStateFlow<SelfBookingUiState>(SelfBookingUiState.LoadingSlots)
    val state: StateFlow<SelfBookingUiState> = _state.asStateFlow()

    init {
        loadSlots(LocalDate.now())
    }

    // -------------------------------------------------------------------------
    // Slot loading
    // -------------------------------------------------------------------------

    fun loadSlots(date: LocalDate = LocalDate.now()) {
        _state.value = SelfBookingUiState.LoadingSlots
        viewModelScope.launch {
            runCatching {
                selfBookingApi.getAvailableSlots(
                    locationId = locationId,
                    date = date.format(DateTimeFormatter.ISO_LOCAL_DATE),
                )
            }.onSuccess { response ->
                val slots = response.data
                if (slots == null) {
                    _state.value = SelfBookingUiState.NotAvailable
                } else {
                    _state.value = SelfBookingUiState.SlotSelection(
                        slots = slots,
                        selectedDate = date,
                        selectedSlot = null,
                    )
                }
            }.onFailure { e ->
                Timber.tag("SelfBooking").e(e, "loadSlots failed locationId=%s", locationId)
                _state.value = when {
                    e is HttpException && e.code() == 404 -> SelfBookingUiState.NotAvailable
                    e is HttpException && e.code() == 429 ->
                        SelfBookingUiState.Error("Too many requests. Please wait and try again.")
                    e is IOException ->
                        SelfBookingUiState.Error("Network error. Check your connection and try again.")
                    else ->
                        SelfBookingUiState.Error("Something went wrong. Please try again.")
                }
            }
        }
    }

    fun onDateChange(date: LocalDate) {
        loadSlots(date)
    }

    fun onSlotSelected(slot: BookingSlot) {
        val current = _state.value
        if (current is SelfBookingUiState.SlotSelection) {
            _state.value = current.copy(selectedSlot = slot)
        }
    }

    fun onProceedToCustomerInfo() {
        val current = _state.value
        if (current is SelfBookingUiState.SlotSelection && current.selectedSlot != null) {
            _state.value = SelfBookingUiState.CustomerInfo(slot = current.selectedSlot)
        }
    }

    // -------------------------------------------------------------------------
    // Customer info form
    // -------------------------------------------------------------------------

    fun onNameChange(value: String) {
        val current = _state.value
        if (current is SelfBookingUiState.CustomerInfo) {
            _state.value = current.copy(name = value)
        }
    }

    fun onPhoneChange(value: String) {
        val current = _state.value
        if (current is SelfBookingUiState.CustomerInfo) {
            _state.value = current.copy(phone = value)
        }
    }

    fun onEmailChange(value: String) {
        val current = _state.value
        if (current is SelfBookingUiState.CustomerInfo) {
            _state.value = current.copy(email = value)
        }
    }

    fun onServiceChange(value: String) {
        val current = _state.value
        if (current is SelfBookingUiState.CustomerInfo) {
            _state.value = current.copy(service = value)
        }
    }

    fun onNotesChange(value: String) {
        val current = _state.value
        if (current is SelfBookingUiState.CustomerInfo) {
            _state.value = current.copy(notes = value)
        }
    }

    fun onBackToSlots() {
        val current = _state.value
        if (current is SelfBookingUiState.CustomerInfo) {
            // Reload slots so the previously selected slot is visible again.
            loadSlots(LocalDate.now())
        }
    }

    // -------------------------------------------------------------------------
    // Reservation
    // -------------------------------------------------------------------------

    fun onConfirmBooking() {
        val current = _state.value
        if (current !is SelfBookingUiState.CustomerInfo) return
        if (current.name.isBlank() || current.phone.isBlank()) return
        _state.value = SelfBookingUiState.Confirming
        viewModelScope.launch {
            runCatching {
                selfBookingApi.reserveSlot(
                    BookingReserveRequest(
                        slotId = current.slot.slotId,
                        locationId = locationId,
                        customerName = current.name.trim(),
                        customerPhone = current.phone.trim(),
                        customerEmail = current.email.trim().takeIf { it.isNotEmpty() },
                        service = current.service.trim().takeIf { it.isNotEmpty() },
                        notes = current.notes.trim().takeIf { it.isNotEmpty() },
                    )
                )
            }.onSuccess { response ->
                val confirmation = response.data
                if (confirmation == null) {
                    _state.value = SelfBookingUiState.Error("Reservation failed. Please try again.")
                } else {
                    _state.value = SelfBookingUiState.Confirmed(confirmation)
                }
            }.onFailure { e ->
                Timber.tag("SelfBooking").e(e, "reserveSlot failed slotId=%s", current.slot.slotId)
                _state.value = when {
                    e is HttpException && e.code() == 404 ->
                        SelfBookingUiState.Error("That slot is no longer available. Please choose another time.")
                    e is HttpException && e.code() == 409 ->
                        SelfBookingUiState.Error("That slot was just taken. Please choose another time.")
                    e is HttpException && e.code() == 429 ->
                        SelfBookingUiState.Error("Too many requests. Please wait and try again.")
                    e is IOException ->
                        SelfBookingUiState.Error("Network error. Check your connection and try again.")
                    else ->
                        SelfBookingUiState.Error("Something went wrong. Please try again.")
                }
            }
        }
    }

    fun retryFromError() {
        loadSlots(LocalDate.now())
    }
}
