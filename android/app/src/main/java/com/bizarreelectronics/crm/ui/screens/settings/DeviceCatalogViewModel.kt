package com.bizarreelectronics.crm.ui.screens.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.CatalogApi
import com.bizarreelectronics.crm.data.remote.dto.DeviceModelItem
import com.bizarreelectronics.crm.data.remote.dto.ManufacturerItem
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import javax.inject.Inject

/**
 * DeviceCatalogViewModel — §44.3
 *
 * Manages the [DeviceCatalogScreen] state. Loads the manufacturers + device
 * models hierarchy from [CatalogApi] (GET /catalog/manufacturers and
 * GET /catalog/devices).
 *
 * UI flow:
 *  1. Top level: list of manufacturers with model counts.
 *  2. Selecting a manufacturer expands to its device models inline.
 *  3. Search bar queries /catalog/devices?q= across all manufacturers.
 *
 * 404-tolerant throughout.
 *
 * iOS parallel: same endpoints consumed by the iOS Swift client.
 */
@HiltViewModel
class DeviceCatalogViewModel @Inject constructor(
    private val catalogApi: CatalogApi,
    private val serverMonitor: ServerReachabilityMonitor,
) : ViewModel() {

    private val _state = MutableStateFlow(DeviceCatalogUiState())
    val state = _state.asStateFlow()

    init {
        loadManufacturers()
    }

    /** Load manufacturers list (used as first level of hierarchy). */
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
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    _state.value = _state.value.copy(isLoading = false, manufacturers = emptyList())
                } else {
                    _state.value = _state.value.copy(
                        isLoading = false,
                        error = "Failed to load manufacturers (${e.code()})",
                    )
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = e.message ?: "Failed to load manufacturers",
                )
            }
        }
    }

    /**
     * Toggle device-model expansion for a manufacturer row.
     *
     * If already expanded, collapses and clears cached models.
     * If not expanded, fetches models for that manufacturer and expands.
     *
     * @param manufacturerId The manufacturer to expand/collapse.
     */
    fun toggleManufacturer(manufacturerId: Long) {
        val current = _state.value
        if (current.expandedManufacturerId == manufacturerId) {
            // Collapse
            _state.value = current.copy(expandedManufacturerId = null, expandedModels = emptyList())
            return
        }
        // Expand — fetch models
        _state.value = current.copy(
            expandedManufacturerId = manufacturerId,
            isLoadingModels = true,
            modelsError = null,
            expandedModels = emptyList(),
        )
        viewModelScope.launch {
            try {
                val response = catalogApi.searchDevices(manufacturerId = manufacturerId.toInt())
                _state.value = _state.value.copy(
                    isLoadingModels = false,
                    expandedModels = response.data ?: emptyList(),
                )
            } catch (e: HttpException) {
                _state.value = _state.value.copy(
                    isLoadingModels = false,
                    modelsError = if (e.code() == 404) null else "Failed to load models (${e.code()})",
                    expandedModels = emptyList(),
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoadingModels = false,
                    modelsError = e.message ?: "Failed to load models",
                    expandedModels = emptyList(),
                )
            }
        }
    }

    /**
     * Search across all device models via [CatalogApi.searchDevices].
     *
     * Passing a blank [query] clears the search results, returning to the
     * manufacturer hierarchy view.
     *
     * @param query Free-text search term.
     */
    fun search(query: String) {
        _state.value = _state.value.copy(searchQuery = query)
        if (query.isBlank()) {
            _state.value = _state.value.copy(searchResults = null, isSearching = false)
            return
        }
        viewModelScope.launch {
            _state.value = _state.value.copy(isSearching = true, searchError = null)
            try {
                val response = catalogApi.searchDevices(query = query, limit = 100)
                _state.value = _state.value.copy(
                    isSearching = false,
                    searchResults = response.data ?: emptyList(),
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isSearching = false,
                    searchError = e.message ?: "Search failed",
                    searchResults = emptyList(),
                )
            }
        }
    }

    /** Clear a transient search error. */
    fun clearSearchError() {
        _state.value = _state.value.copy(searchError = null)
    }
}

/**
 * UI state for [DeviceCatalogScreen].
 *
 * @param manufacturers          Top-level manufacturers list.
 * @param expandedManufacturerId Manufacturer currently expanded to show models; null = none.
 * @param expandedModels         Device models for [expandedManufacturerId].
 * @param searchQuery            Current search text.
 * @param searchResults          Results from /catalog/devices?q=; null = not in search mode.
 * @param isLoading              True while loading manufacturers.
 * @param isLoadingModels        True while loading models for an expanded manufacturer.
 * @param isSearching            True while a search request is in flight.
 * @param error                  Manufacturer load error; null when none.
 * @param modelsError            Model expansion error; null when none.
 * @param searchError            Search error; null when none.
 * @param offline                True when server is unreachable.
 */
data class DeviceCatalogUiState(
    val manufacturers: List<ManufacturerItem> = emptyList(),
    val expandedManufacturerId: Long? = null,
    val expandedModels: List<DeviceModelItem> = emptyList(),
    val searchQuery: String = "",
    val searchResults: List<DeviceModelItem>? = null,
    val isLoading: Boolean = true,
    val isLoadingModels: Boolean = false,
    val isSearching: Boolean = false,
    val error: String? = null,
    val modelsError: String? = null,
    val searchError: String? = null,
    val offline: Boolean = false,
)
