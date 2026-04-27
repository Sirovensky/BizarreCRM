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
 * RepairPricingViewModel — §44.2
 *
 * Manages the [RepairPricingScreen] state. Provides a searchable, category-
 * filtered services catalog backed by [RepairPricingApi]. Supports creating,
 * updating, and deleting service entries.
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
    fun loadServices(
        query: String? = _state.value.searchQuery.takeIf { it.isNotBlank() },
        category: String? = _state.value.selectedCategory,
    ) {
        if (!serverMonitor.isEffectivelyOnline.value) {
            _state.value = _state.value.copy(isLoading = false, offline = true)
            return
        }

        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null, offline = false)
            try {
                val response = repairPricingApi.getServices(
                    query = query?.takeIf { it.isNotBlank() },
                    category = category?.takeIf { it.isNotBlank() },
                )
                val services = response.data ?: emptyList()
                val categories = services
                    .mapNotNull { it.category?.trim() }
                    .filter { it.isNotBlank() }
                    .distinct()
                    .sorted()
                _state.value = _state.value.copy(
                    isLoading = false,
                    services = services,
                    availableCategories = categories,
                    searchQuery = query ?: "",
                    selectedCategory = category,
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
        loadServices(query = query.takeIf { it.isNotBlank() }, category = _state.value.selectedCategory)
    }

    /** Select or deselect a category filter chip. */
    fun selectCategory(category: String?) {
        _state.value = _state.value.copy(selectedCategory = category)
        loadServices(
            query = _state.value.searchQuery.takeIf { it.isNotBlank() },
            category = category,
        )
    }

    /**
     * Create or update a repair service.
     *
     * @param id          Service ID for update; null for create.
     * @param name        Service display name.
     * @param category    Optional category slug.
     * @param laborPrice  Default labor rate (plain Double, not cents — server stores as REAL).
     * @param description Optional description text.
     */
    fun saveService(
        id: Long?,
        name: String,
        category: String?,
        laborPrice: Double,
        description: String? = null,
    ) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isSaving = true, saveError = null)
            val body = UpsertRepairServiceRequest(
                name = name.trim(),
                category = category?.trim()?.takeIf { it.isNotBlank() },
                laborPrice = laborPrice,
                description = description?.trim()?.takeIf { it.isNotBlank() },
            )
            try {
                if (id != null) {
                    repairPricingApi.updateService(id, body)
                } else {
                    repairPricingApi.createService(body)
                }
                _state.value = _state.value.copy(isSaving = false)
                loadServices()
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

    /**
     * Delete a service by ID (admin/manager only, 404-tolerant).
     *
     * Server returns 400 if the service is still referenced by repair_prices rows;
     * that error is surfaced in [deleteError].
     *
     * @param id Service ID to delete.
     */
    fun deleteService(id: Long) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isDeleting = true, deleteError = null)
            try {
                repairPricingApi.deleteService(id)
                _state.value = _state.value.copy(
                    isDeleting = false,
                    pendingDeleteId = null,
                )
                loadServices()
            } catch (e: HttpException) {
                val msg = when (e.code()) {
                    404 -> null // already gone
                    400 -> "Cannot delete — service is in use by repair prices"
                    else -> "Delete failed (${e.code()})"
                }
                _state.value = _state.value.copy(
                    isDeleting = false,
                    pendingDeleteId = null,
                    deleteError = msg,
                )
                if (e.code() == 404) loadServices()
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isDeleting = false,
                    pendingDeleteId = null,
                    deleteError = e.message ?: "Delete failed",
                )
            }
        }
    }

    /** Stage a service for deletion, showing the ConfirmDialog. */
    fun requestDelete(id: Long) {
        _state.value = _state.value.copy(pendingDeleteId = id)
    }

    /** Cancel the pending delete (ConfirmDialog dismissed). */
    fun cancelDelete() {
        _state.value = _state.value.copy(pendingDeleteId = null)
    }

    /** Clear a previously shown delete error snackbar. */
    fun clearDeleteError() {
        _state.value = _state.value.copy(deleteError = null)
    }
}

/**
 * UI state for [RepairPricingScreen].
 *
 * @param services             Loaded services, filtered by [searchQuery] and [selectedCategory].
 * @param availableCategories  Distinct category values for filter chips.
 * @param selectedCategory     Currently selected category chip; null = "All".
 * @param searchQuery          Current search input shown in the search bar.
 * @param isLoading            True while the initial or refresh fetch is in flight.
 * @param isSaving             True while a save operation is in flight.
 * @param isDeleting           True while a delete operation is in flight.
 * @param error                Fetch error message; null when none.
 * @param saveError            Save error message; null when none.
 * @param deleteError          Delete error message; null when none.
 * @param pendingDeleteId      ID staged for ConfirmDialog delete; null = dialog closed.
 * @param offline              True when server is unreachable.
 */
data class RepairPricingUiState(
    val services: List<RepairServiceItem> = emptyList(),
    val availableCategories: List<String> = emptyList(),
    val selectedCategory: String? = null,
    val searchQuery: String = "",
    val isLoading: Boolean = true,
    val isSaving: Boolean = false,
    val isDeleting: Boolean = false,
    val error: String? = null,
    val saveError: String? = null,
    val deleteError: String? = null,
    val pendingDeleteId: Long? = null,
    val offline: Boolean = false,
)
