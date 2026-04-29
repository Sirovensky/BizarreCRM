package com.bizarreelectronics.crm.ui.screens.publictracking

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.PublicTrackingApi
import com.bizarreelectronics.crm.data.remote.dto.PublicTicketData
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import timber.log.Timber
import java.io.IOException
import javax.inject.Inject

// ---------------------------------------------------------------------------
// §55.2 — Public tracking screen state
// ---------------------------------------------------------------------------

sealed class PublicTrackingUiState {
    /** Initial loading; orderId + token known, network request in-flight. */
    object Loading : PublicTrackingUiState()

    /** Ticket data loaded successfully. */
    data class Success(val ticket: PublicTicketData) : PublicTrackingUiState()

    /**
     * Server returned 404. Either the tracking token is wrong, the orderId
     * does not exist, or the ticket was deleted. Customer copy: "not found".
     */
    object NotFound : PublicTrackingUiState()

    /**
     * Network or server error. Includes a human-readable [message] for the
     * UI to show alongside a Retry action.
     */
    data class Error(val message: String) : PublicTrackingUiState()
}

/**
 * ViewModel backing [PublicTrackingScreen].
 *
 * Accepts two nav arguments extracted from [SavedStateHandle]:
 *   - `orderId`       — ticket order ID, e.g. "T-0042"
 *   - `trackingToken` — 32-char hex bearer token from the tracking URL
 *
 * Both are required. If either is blank the VM emits [PublicTrackingUiState.NotFound]
 * immediately without a network request.
 *
 * No authentication required: [PublicTrackingApi] uses a separate unauthenticated
 * Retrofit instance (or the same instance but with no auth interceptor on this
 * path — see DI binding).
 */
@HiltViewModel
class PublicTrackingViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val publicTrackingApi: PublicTrackingApi,
) : ViewModel() {

    private val orderId: String = savedStateHandle.get<String>("orderId").orEmpty()
    private val trackingToken: String = savedStateHandle.get<String>("trackingToken").orEmpty()

    private val _state = MutableStateFlow<PublicTrackingUiState>(PublicTrackingUiState.Loading)
    val state: StateFlow<PublicTrackingUiState> = _state.asStateFlow()

    init {
        if (orderId.isBlank() || trackingToken.isBlank()) {
            _state.value = PublicTrackingUiState.NotFound
        } else {
            load()
        }
    }

    fun retry() {
        if (orderId.isBlank() || trackingToken.isBlank()) return
        load()
    }

    private fun load() {
        _state.value = PublicTrackingUiState.Loading
        viewModelScope.launch {
            runCatching {
                publicTrackingApi.getPortalTicket(
                    orderId = orderId,
                    authorization = "Bearer $trackingToken",
                )
            }.onSuccess { response ->
                val data = response.data
                if (data == null) {
                    _state.value = PublicTrackingUiState.NotFound
                } else {
                    _state.value = PublicTrackingUiState.Success(data)
                }
            }.onFailure { e ->
                Timber.tag("PublicTracking").e(e, "load failed orderId=%s", orderId)
                _state.value = when {
                    e is HttpException && e.code() == 404 -> PublicTrackingUiState.NotFound
                    e is HttpException && e.code() == 429 -> PublicTrackingUiState.Error(
                        "Too many requests. Please wait a moment and try again."
                    )
                    e is IOException -> PublicTrackingUiState.Error(
                        "Network error. Check your connection and try again."
                    )
                    else -> PublicTrackingUiState.Error(
                        "Something went wrong. Please try again."
                    )
                }
            }
        }
    }
}
