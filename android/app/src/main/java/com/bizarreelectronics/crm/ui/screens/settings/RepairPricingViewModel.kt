package com.bizarreelectronics.crm.ui.screens.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.RepairPricingApi
import com.bizarreelectronics.crm.data.remote.api.UpsertRepairServiceRequest
import com.bizarreelectronics.crm.data.remote.dto.RepairServiceItem
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import javax.inject.Inject

/**
 * RepairPricingViewModel — §4.9 L766
 *
 * Manages the [RepairPricingScreen] state. Provides a searchable services catalog
 * backed by [RepairPricingApi]. Supports creating and updating service entries.
 *
 * 404-tolerant: when the server returns 404 the state degrades to an empty list.
 *
 * iOS parallel: same server endpoints consumed by the iOS Swift client.
 */
@HiltViewModel
class RepairPricingViewModel @Inject constructor(
    private val repairPricingApi: RepairPricingApi,
    private val serverMonitor: ServerReachabilityMonitor,
) : ViewModel() {

    private val _state = MutableStateFlow(RepairPricingUiState())
    val state = _state.asStateFlow()

    init {
        loadServices()
    }

    /** Reload services catalog; [query] filters by name if non-blank. */
    fun loadServices(query: String? = null) {
        if (!serverMonitor.isEffectivelyOnline.value) {
            _state.value = _state.value.copy(isLoading = false, offline = true)
            return
        }

        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null, offline = false)
            try {
                val response = repairPricingApi.getServices(
                    query = query?.takeIf { it.isNotBlank() },
                )
                _state.value = _state.value.copy(
                    isLoading = false,
                    services = response.data ?: emptyList(),
                    searchQuery = query ?: "",
                )
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    _state.value = _state.value.copy(isLoading = false, services = emptyList())
                } else {
                    _state.value = _state.value.copy(
                        isLoading = false,
                        error = "Failed to load services (${e.code()})",
                    )
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = e.message ?: "Failed to load services",
                )
            }
        }
    }

    /** Update the local search query and re-fetch from server. */
    fun search(query: String) {
        _state.value = _state.value.copy(searchQuery = query)
        loadServices(query)
    }

    /**
     * Create or update a repair service.
     *
     * @param id          Service ID for update; null for create.
     * @param name        Service display name.
     * @param category    Optional category slug.
     * @param laborPrice  Default labor rate.
     */
    fun saveService(
        id: Long?,
        name: String,
        category: String?,
        laborPrice: Double,
    ) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isSaving = true, saveError = null)
            val body = UpsertRepairServiceRequest(
                name = name.trim(),
                slug = if (id == null) UpsertRepairServiceRequest.slugify(name) else null,
                category = category?.trim()?.takeIf { it.isNotBlank() },
                laborPrice = laborPrice,
            )
            try {
                if (id != null) {
                    repairPricingApi.updateService(id, body)
                } else {
                    repairPricingApi.createService(body)
                }
                _state.value = _state.value.copy(isSaving = false)
                loadServices(_state.value.searchQuery.takeIf { it.isNotBlank() })
            } catch (e: HttpException) {
                _state.value = _state.value.copy(
                    isSaving = false,
                    saveError = "Save failed (${e.code()})",
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isSaving = false,
                    saveError = e.message ?: "Save failed",
                )
            }
        }
    }
}

/**
 * UI state for [RepairPricingScreen].
 *
 * @param services     Loaded services, filtered by [searchQuery] on the server.
 * @param searchQuery  Current search input shown in the search bar.
 * @param isLoading    True while the initial or refresh fetch is in flight.
 * @param isSaving     True while a save operation is in flight.
 * @param error        Fetch error message; null when none.
 * @param saveError    Save error message; null when none.
 * @param offline      True when server is unreachable.
 */
data class RepairPricingUiState(
    val services: List<RepairServiceItem> = emptyList(),
    val searchQuery: String = "",
    val isLoading: Boolean = true,
    val isSaving: Boolean = false,
    val error: String? = null,
    val saveError: String? = null,
    val offline: Boolean = false,
)
