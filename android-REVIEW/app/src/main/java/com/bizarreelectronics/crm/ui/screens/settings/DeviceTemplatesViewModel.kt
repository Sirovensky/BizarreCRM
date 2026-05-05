package com.bizarreelectronics.crm.ui.screens.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.DeviceTemplateApi
import com.bizarreelectronics.crm.data.remote.api.DeviceTemplateDto
import com.bizarreelectronics.crm.data.remote.api.UpsertDeviceTemplateRequest
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import javax.inject.Inject

/**
 * DeviceTemplatesViewModel — §44.1
 *
 * Manages the [DeviceTemplatesScreen] state. Loads device templates from
 * [DeviceTemplateApi] and handles create / update / delete operations.
 *
 * Templates are filterable by device category via [filterCategory].
 *
 * 404-tolerant: when the server returns 404 (pre-dates the endpoint) the
 * state degrades to an empty list without surfacing an error to the user.
 *
 * iOS parallel: the same server endpoints are consumed by the iOS Swift client.
 */
@HiltViewModel
class DeviceTemplatesViewModel @Inject constructor(
    private val deviceTemplateApi: DeviceTemplateApi,
    private val serverMonitor: ServerReachabilityMonitor,
) : ViewModel() {

    private val _state = MutableStateFlow(DeviceTemplatesUiState())
    val state = _state.asStateFlow()

    init {
        loadTemplates()
    }

    /** Reload templates from the server, optionally filtered by [category]. */
    fun loadTemplates(category: String? = _state.value.selectedCategory) {
        if (!serverMonitor.isEffectivelyOnline.value) {
            _state.value = _state.value.copy(isLoading = false, offline = true)
            return
        }

        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null, offline = false)
            try {
                val response = deviceTemplateApi.getTemplates(
                    category = category?.takeIf { it.isNotBlank() },
                )
                val templates = response.data ?: emptyList()
                // Derive available category chips from loaded data
                val categories = templates
                    .mapNotNull { it.deviceCategory?.trim() }
                    .filter { it.isNotBlank() }
                    .distinct()
                    .sorted()
                _state.value = _state.value.copy(
                    isLoading = false,
                    templates = templates,
                    availableCategories = categories,
                    selectedCategory = category,
                )
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    _state.value = _state.value.copy(isLoading = false, templates = emptyList())
                } else {
                    _state.value = _state.value.copy(
                        isLoading = false,
                        error = "Failed to load templates (${e.code()})",
                    )
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = e.message ?: "Failed to load templates",
                )
            }
        }
    }

    /** Select or deselect a category filter chip. */
    fun selectCategory(category: String?) {
        _state.value = _state.value.copy(selectedCategory = category)
        loadTemplates(category)
    }

    /**
     * Persist a new or updated template.
     *
     * @param id             Template ID for update; null for create.
     * @param name           Display name.
     * @param deviceCategory Optional device class (e.g. "Phone").
     * @param deviceModel    Optional device model name (e.g. "iPhone 14").
     * @param fault          Optional fault description.
     * @param estLaborMinutes Estimated labor time in minutes.
     * @param estLaborCostCents Estimated labor cost in cents.
     * @param suggestedPriceCents Suggested repair price in cents.
     * @param diagnosticChecklist List of pre-condition checklist items.
     * @param warrantyDays   Warranty period in days.
     */
    fun saveTemplate(
        id: Long?,
        name: String,
        deviceCategory: String?,
        deviceModel: String?,
        fault: String?,
        estLaborMinutes: Int,
        estLaborCostCents: Long,
        suggestedPriceCents: Long,
        diagnosticChecklist: List<String>,
        warrantyDays: Int,
    ) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isSaving = true, saveError = null)
            val body = UpsertDeviceTemplateRequest(
                name = name.trim(),
                deviceCategory = deviceCategory?.trim()?.takeIf { it.isNotBlank() },
                deviceModel = deviceModel?.trim()?.takeIf { it.isNotBlank() },
                fault = fault?.trim()?.takeIf { it.isNotBlank() },
                estLaborMinutes = estLaborMinutes,
                estLaborCost = estLaborCostCents,
                suggestedPrice = suggestedPriceCents,
                diagnosticChecklist = diagnosticChecklist.filter { it.isNotBlank() }.map { it.trim() },
                warrantyDays = warrantyDays,
            )
            try {
                if (id != null) {
                    deviceTemplateApi.updateTemplate(id, body)
                } else {
                    deviceTemplateApi.createTemplate(body)
                }
                _state.value = _state.value.copy(isSaving = false)
                loadTemplates()
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
     * Delete a template by ID (admin only, 404-tolerant).
     *
     * Clears [pendingDeleteId] after completion regardless of outcome so the
     * ConfirmDialog is dismissed.
     *
     * @param id Template ID to delete.
     */
    fun deleteTemplate(id: Long) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isDeleting = true, deleteError = null)
            try {
                deviceTemplateApi.deleteTemplate(id)
                _state.value = _state.value.copy(
                    isDeleting = false,
                    pendingDeleteId = null,
                )
                loadTemplates()
            } catch (e: HttpException) {
                val msg = if (e.code() == 404) null else "Delete failed (${e.code()})"
                _state.value = _state.value.copy(
                    isDeleting = false,
                    pendingDeleteId = null,
                    deleteError = msg,
                )
                if (e.code() == 404) loadTemplates() // already gone
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isDeleting = false,
                    pendingDeleteId = null,
                    deleteError = e.message ?: "Delete failed",
                )
            }
        }
    }

    /** Stage a template for deletion, showing the ConfirmDialog. */
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
 * UI state for [DeviceTemplatesScreen].
 *
 * @param templates            Loaded templates, filtered by [selectedCategory].
 * @param availableCategories  Distinct category values derived from loaded data; used for chips.
 * @param selectedCategory     Currently selected category chip; null = "All".
 * @param isLoading            True while the initial or refresh fetch is in flight.
 * @param isSaving             True while a save operation is in flight.
 * @param isDeleting           True while a delete operation is in flight.
 * @param error                Fetch error message; null when none.
 * @param saveError            Save error message; null when none.
 * @param deleteError          Delete error message; null when none.
 * @param pendingDeleteId      ID staged for ConfirmDialog delete; null = dialog closed.
 * @param offline              True when server is unreachable.
 */
data class DeviceTemplatesUiState(
    val templates: List<DeviceTemplateDto> = emptyList(),
    val availableCategories: List<String> = emptyList(),
    val selectedCategory: String? = null,
    val isLoading: Boolean = true,
    val isSaving: Boolean = false,
    val isDeleting: Boolean = false,
    val error: String? = null,
    val saveError: String? = null,
    val deleteError: String? = null,
    val pendingDeleteId: Long? = null,
    val offline: Boolean = false,
)
