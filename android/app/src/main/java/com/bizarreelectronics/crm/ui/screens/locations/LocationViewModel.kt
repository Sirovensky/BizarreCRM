package com.bizarreelectronics.crm.ui.screens.locations

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.LocationApi
import com.bizarreelectronics.crm.data.remote.dto.CreateLocationRequest
import com.bizarreelectronics.crm.data.remote.dto.LocationDto
import com.bizarreelectronics.crm.data.remote.dto.UpdateLocationRequest
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

// ─── UI state ────────────────────────────────────────────────────────────────

/** Filter for the location list's active/inactive chips. */
enum class LocationFilter { ALL, ACTIVE, INACTIVE }

data class LocationListUiState(
    val locations: List<LocationDto> = emptyList(),
    val filter: LocationFilter = LocationFilter.ACTIVE,
    val isLoading: Boolean = false,
    val isRefreshing: Boolean = false,
    val errorMessage: String? = null,
    /** Non-null while the "Deactivate location" ConfirmDialog is open. */
    val pendingDeactivate: LocationDto? = null,
)

data class LocationDetailUiState(
    val location: LocationDto? = null,
    val isLoading: Boolean = false,
    val isSaving: Boolean = false,
    val errorMessage: String? = null,
    val savedOk: Boolean = false,
    /** Non-null while the "Set as default" ConfirmDialog is open. */
    val pendingSetDefault: LocationDto? = null,
    /** Non-null while the "Deactivate location" ConfirmDialog is open. */
    val pendingDeactivate: LocationDto? = null,
)

data class LocationFormState(
    val name: String = "",
    val addressLine: String = "",
    val city: String = "",
    val state: String = "",
    val postcode: String = "",
    val country: String = "US",
    val phone: String = "",
    val email: String = "",
    val timezone: String = "America/New_York",
    val notes: String = "",
    val isSaving: Boolean = false,
    val errorMessage: String? = null,
    val savedOk: Boolean = false,
)

// ─── List ViewModel ──────────────────────────────────────────────────────────

/**
 * Drives [LocationListScreen].
 *
 * ActionPlan §63.1 — Location switcher + §63.4 Consolidated view.
 *
 * 404-tolerant: when the server returns 404 (endpoint not yet deployed on an
 * older self-hosted install) the list degrades to an empty state with a
 * "Locations not available on this server" message.
 */
@HiltViewModel
class LocationListViewModel @Inject constructor(
    private val locationApi: LocationApi,
) : ViewModel() {

    private val _uiState = MutableStateFlow(LocationListUiState(isLoading = true))
    val uiState: StateFlow<LocationListUiState> = _uiState.asStateFlow()

    init {
        load()
    }

    fun load() {
        viewModelScope.launch { performLoad(isRefresh = false) }
    }

    /**
     * BUGHUNT-2026-05-18: pull-to-refresh hook. Keeps the list visible while
     * the round-trip happens (vs. swap-to-spinner that `load()` does on first
     * paint).
     */
    fun refresh() {
        viewModelScope.launch { performLoad(isRefresh = true) }
    }

    private suspend fun performLoad(isRefresh: Boolean) {
        _uiState.value = _uiState.value.copy(
            isLoading = !isRefresh && _uiState.value.locations.isEmpty(),
            isRefreshing = isRefresh,
            errorMessage = null,
        )
        // BUGHUNT-2026-05-17: runCatching swallows CancellationException.
        try {
            val response = locationApi.getLocations(active = null)
            if (response.success) {
                _uiState.value = _uiState.value.copy(
                    locations = response.data ?: emptyList(),
                    isLoading = false,
                    isRefreshing = false,
                )
            } else {
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    isRefreshing = false,
                    errorMessage = "Failed to load locations.",
                )
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            _uiState.value = _uiState.value.copy(
                isLoading = false,
                isRefreshing = false,
                errorMessage = if (e.message?.contains("404") == true)
                    "Locations not available on this server version."
                else
                    "Could not load locations. Check your connection.",
            )
        }
    }

    fun setFilter(filter: LocationFilter) {
        _uiState.value = _uiState.value.copy(filter = filter)
    }

    fun requestDeactivate(location: LocationDto) {
        _uiState.value = _uiState.value.copy(pendingDeactivate = location)
    }

    fun cancelDeactivate() {
        _uiState.value = _uiState.value.copy(pendingDeactivate = null)
    }

    fun confirmDeactivate() {
        val target = _uiState.value.pendingDeactivate ?: return
        _uiState.value = _uiState.value.copy(pendingDeactivate = null)
        viewModelScope.launch {
            // BUGHUNT-2026-05-17: runCatching swallows CancellationException;
            // post-commit cancel could leave UI showing the deactivated
            // location until next reload. Re-throw to preserve coroutine
            // cancellation; surface errors only on real failures.
            try {
                locationApi.deactivateLocation(target.id)
                load()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    errorMessage = e.message ?: "Failed to deactivate location.",
                )
            }
        }
    }

    fun clearError() {
        _uiState.value = _uiState.value.copy(errorMessage = null)
    }
}

// ─── Detail / Edit ViewModel ─────────────────────────────────────────────────

/**
 * Drives [LocationDetailScreen] (read + quick-actions) and [LocationEditScreen].
 *
 * ActionPlan §63.2 — Per-location config (name, address, phone, email, timezone, notes).
 */
@HiltViewModel
class LocationDetailViewModel @Inject constructor(
    private val locationApi: LocationApi,
) : ViewModel() {

    private val _uiState = MutableStateFlow(LocationDetailUiState(isLoading = true))
    val uiState: StateFlow<LocationDetailUiState> = _uiState.asStateFlow()

    fun load(id: Long) {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, errorMessage = null)
            // BUGHUNT-2026-05-17: runCatching swallows CancellationException.
            try {
                val response = locationApi.getLocation(id)
                _uiState.value = _uiState.value.copy(
                    location = if (response.success) response.data else null,
                    isLoading = false,
                    errorMessage = if (!response.success) "Failed to load location." else null,
                )
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    errorMessage = e.message ?: "Could not load location.",
                )
            }
        }
    }

    fun requestSetDefault(location: LocationDto) {
        _uiState.value = _uiState.value.copy(pendingSetDefault = location)
    }

    fun cancelSetDefault() {
        _uiState.value = _uiState.value.copy(pendingSetDefault = null)
    }

    fun confirmSetDefault() {
        val target = _uiState.value.pendingSetDefault ?: return
        _uiState.value = _uiState.value.copy(pendingSetDefault = null)
        viewModelScope.launch {
            // BUGHUNT-2026-05-17: runCatching swallows CancellationException.
            try {
                val response = locationApi.setDefault(target.id)
                if (response.success) {
                    _uiState.value = _uiState.value.copy(location = response.data)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    errorMessage = e.message ?: "Failed to set default location.",
                )
            }
        }
    }

    fun requestDeactivate(location: LocationDto) {
        _uiState.value = _uiState.value.copy(pendingDeactivate = location)
    }

    fun cancelDeactivate() {
        _uiState.value = _uiState.value.copy(pendingDeactivate = null)
    }

    fun confirmDeactivate(onSuccess: () -> Unit) {
        val target = _uiState.value.pendingDeactivate ?: return
        _uiState.value = _uiState.value.copy(pendingDeactivate = null)
        viewModelScope.launch {
            // BUGHUNT-2026-05-17: runCatching swallows CancellationException.
            try {
                locationApi.deactivateLocation(target.id)
                onSuccess()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    errorMessage = e.message ?: "Failed to deactivate location.",
                )
            }
        }
    }

    fun clearError() {
        _uiState.value = _uiState.value.copy(errorMessage = null)
    }
}

// ─── Create ViewModel ────────────────────────────────────────────────────────

/**
 * Drives [LocationCreateScreen].
 *
 * ActionPlan §63.2 — create a new location (admin only; server enforces 403).
 */
@HiltViewModel
class LocationCreateViewModel @Inject constructor(
    private val locationApi: LocationApi,
) : ViewModel() {

    private val _uiState = MutableStateFlow(LocationFormState())
    val uiState: StateFlow<LocationFormState> = _uiState.asStateFlow()

    fun onNameChange(v: String)        { _uiState.value = _uiState.value.copy(name = v) }
    fun onAddressChange(v: String)     { _uiState.value = _uiState.value.copy(addressLine = v) }
    fun onCityChange(v: String)        { _uiState.value = _uiState.value.copy(city = v) }
    fun onStateChange(v: String)       { _uiState.value = _uiState.value.copy(state = v) }
    fun onPostcodeChange(v: String)    { _uiState.value = _uiState.value.copy(postcode = v) }
    fun onCountryChange(v: String)     { _uiState.value = _uiState.value.copy(country = v) }
    fun onPhoneChange(v: String)       { _uiState.value = _uiState.value.copy(phone = v) }
    fun onEmailChange(v: String)       { _uiState.value = _uiState.value.copy(email = v) }
    fun onTimezoneChange(v: String)    { _uiState.value = _uiState.value.copy(timezone = v) }
    fun onNotesChange(v: String)       { _uiState.value = _uiState.value.copy(notes = v) }

    fun save(onSuccess: (Long) -> Unit) {
        val s = _uiState.value
        if (s.name.isBlank()) {
            _uiState.value = s.copy(errorMessage = "Name is required.")
            return
        }
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isSaving = true, errorMessage = null)
            // BUGHUNT-2026-05-17: runCatching swallows CancellationException;
            // form dismiss mid-POST + retap could create DUPLICATE location.
            try {
                val response = locationApi.createLocation(
                    CreateLocationRequest(
                        name        = s.name.trim(),
                        addressLine = s.addressLine.trim().takeIf { it.isNotEmpty() },
                        city        = s.city.trim().takeIf { it.isNotEmpty() },
                        state       = s.state.trim().takeIf { it.isNotEmpty() },
                        postcode    = s.postcode.trim().takeIf { it.isNotEmpty() },
                        country     = s.country.trim().ifEmpty { "US" },
                        phone       = s.phone.trim().takeIf { it.isNotEmpty() },
                        email       = s.email.trim().takeIf { it.isNotEmpty() },
                        timezone    = s.timezone.trim().ifEmpty { "America/New_York" },
                        notes       = s.notes.trim().takeIf { it.isNotEmpty() },
                    )
                )
                if (response.success && response.data != null) {
                    _uiState.value = _uiState.value.copy(isSaving = false, savedOk = true)
                    onSuccess(response.data.id)
                } else {
                    _uiState.value = _uiState.value.copy(
                        isSaving = false,
                        errorMessage = "Failed to create location.",
                    )
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    isSaving = false,
                    errorMessage = e.message ?: "Could not create location.",
                )
            }
        }
    }

    fun clearError() {
        _uiState.value = _uiState.value.copy(errorMessage = null)
    }
}
