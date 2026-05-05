package com.bizarreelectronics.crm.ui.screens.pricingcatalog

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.CatalogApi
import com.bizarreelectronics.crm.data.remote.dto.AddDeviceModelRequest
import com.bizarreelectronics.crm.data.remote.dto.DeviceModelItem
import com.bizarreelectronics.crm.data.remote.dto.ManufacturerItem
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import javax.inject.Inject

/**
 * DeviceCatalogViewModel — §44.3
 *
 * Manages [DeviceCatalogScreen] state. Loads manufacturer list on init;
 * searches device models server-side with debounce.
 *
 * Admin-only addDevice wraps POST /catalog/devices.
 */
@HiltViewModel
class DeviceCatalogViewModel @Inject constructor(
    private val catalogApi: CatalogApi,
    private val serverMonitor: ServerReachabilityMonitor,
) : ViewModel() {

    private val _state = MutableStateFlow(DeviceCatalogUiState())
    val state = _state.asStateFlow()

    private var searchJob: Job? = null

    init {
        loadManufacturers()
    }

    /** Load all manufacturers for filter chips. */
    fun loadManufacturers() {
        if (!serverMonitor.isEffectivelyOnline.value) {
            _state.value = _state.value.copy(isLoading = false, offline = true)
            return
        }
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null, offline = false)
            try {
                val response = catalogApi.getManufacturers()
                _state.value = _state.value.copy(
                    isLoading = false,
                    manufacturers = response.data ?: emptyList(),
                )
                // Kick off initial device search (popular devices).
                searchDevices()
            } catch (e: HttpException) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = "Failed to load manufacturers (${e.code()})",
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = e.message ?: "Failed to load manufacturers",
                )
            }
        }
    }

    /** Debounce search query changes and trigger server search. */
    fun onSearchQueryChanged(query: String) {
        _state.value = _state.value.copy(searchQuery = query)
        searchJob?.cancel()
        searchJob = viewModelScope.launch {
            delay(300)
            searchDevices()
        }
    }

    fun onManufacturerSelected(manufacturerId: Long?) {
        _state.value = _state.value.copy(selectedManufacturerId = manufacturerId)
        searchDevices()
    }

    fun onCategorySelected(category: String?) {
        _state.value = _state.value.copy(selectedCategory = category)
        searchDevices()
    }

    /** Execute server search with current filter state. */
    fun searchDevices() {
        if (!serverMonitor.isEffectivelyOnline.value) {
            _state.value = _state.value.copy(isLoadingDevices = false, offline = true)
            return
        }
        val s = _state.value
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoadingDevices = true, deviceError = null)
            try {
                val response = catalogApi.searchDevices(
                    query = s.searchQuery.trim().takeIf { it.isNotBlank() },
                    category = s.selectedCategory,
                    manufacturerId = s.selectedManufacturerId?.toInt(),
                    popular = if (s.searchQuery.isBlank() && s.selectedManufacturerId == null) 1 else null,
                    limit = 200,
                )
                _state.value = _state.value.copy(
                    isLoadingDevices = false,
                    devices = response.data ?: emptyList(),
                )
            } catch (e: HttpException) {
                _state.value = _state.value.copy(
                    isLoadingDevices = false,
                    deviceError = "Search failed (${e.code()})",
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoadingDevices = false,
                    deviceError = e.message ?: "Search failed",
                )
            }
        }
    }

    /**
     * Admin only: add a new device model.
     *
     * @param manufacturerId  Manufacturer the model belongs to.
     * @param name            Device model name.
     * @param category        Device category slug (phone/tablet/laptop/tv/other).
     * @param releaseYear     Optional 4-digit release year.
     */
    fun addDevice(
        manufacturerId: Long,
        name: String,
        category: String,
        releaseYear: Int?,
    ) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isSaving = true, saveError = null)
            try {
                catalogApi.addDevice(
                    AddDeviceModelRequest(
                        manufacturerId = manufacturerId,
                        name = name.trim(),
                        category = category,
                        releaseYear = releaseYear,
                    )
                )
                _state.value = _state.value.copy(isSaving = false)
                searchDevices()
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
 * UI state for [DeviceCatalogScreen].
 *
 * @param manufacturers         Manufacturer list for filter chips.
 * @param devices               Current device model search results.
 * @param searchQuery           Active free-text search string.
 * @param selectedManufacturerId Null = all manufacturers.
 * @param selectedCategory      Null = all categories.
 * @param isLoading             True while loading manufacturers.
 * @param isLoadingDevices      True while searching devices.
 * @param isSaving              True while addDevice is in flight.
 * @param error                 Manufacturer load error; null when none.
 * @param deviceError           Device search error; null when none.
 * @param saveError             addDevice error; null when none.
 * @param offline               True when server is unreachable.
 */
data class DeviceCatalogUiState(
    val manufacturers: List<ManufacturerItem> = emptyList(),
    val devices: List<DeviceModelItem> = emptyList(),
    val searchQuery: String = "",
    val selectedManufacturerId: Long? = null,
    val selectedCategory: String? = null,
    val isLoading: Boolean = true,
    val isLoadingDevices: Boolean = false,
    val isSaving: Boolean = false,
    val error: String? = null,
    val deviceError: String? = null,
    val saveError: String? = null,
    val offline: Boolean = false,
)
