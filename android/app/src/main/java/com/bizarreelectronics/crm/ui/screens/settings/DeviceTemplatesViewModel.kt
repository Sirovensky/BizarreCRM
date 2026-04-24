package com.bizarreelectronics.crm.ui.screens.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.CreateDeviceTemplateRequest
import com.bizarreelectronics.crm.data.remote.api.DeviceTemplateApi
import com.bizarreelectronics.crm.data.remote.api.DeviceTemplateDto
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import javax.inject.Inject

/**
 * DeviceTemplatesViewModel — §4.9 L762
 *
 * Manages the [DeviceTemplatesScreen] state. Loads device templates from
 * [DeviceTemplateApi] and handles create / update operations.
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

    /** Reload templates from the server. */
    fun loadTemplates() {
        if (!serverMonitor.isEffectivelyOnline.value) {
            _state.value = _state.value.copy(isLoading = false, offline = true)
            return
        }

        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null, offline = false)
            try {
                val response = deviceTemplateApi.getTemplates()
                _state.value = _state.value.copy(
                    isLoading = false,
                    templates = response.data ?: emptyList(),
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

    /**
     * Persist a new or updated template.
     *
     * If [id] is non-null the existing template is updated via PUT; otherwise
     * a new template is created via POST.
     *
     * @param id             Template ID for update; null for create.
     * @param name           Display name.
     * @param deviceModelId  Optional linked device model.
     * @param commonRepairs  List of common repair names for pre-fill suggestions.
     */
    fun saveTemplate(
        id: Long?,
        name: String,
        deviceModelId: Long?,
        commonRepairs: List<String>,
    ) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isSaving = true, saveError = null)
            val body = CreateDeviceTemplateRequest(
                name = name.trim(),
                deviceModelId = deviceModelId,
                commonRepairs = commonRepairs.filter { it.isNotBlank() }.map { it.trim() },
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
}

/**
 * UI state for [DeviceTemplatesScreen].
 *
 * @param templates  List of device templates loaded from the server.
 * @param isLoading  True while loading.
 * @param isSaving   True while a save operation is in flight.
 * @param error      Fetch error message; null when none.
 * @param saveError  Save error message; null when none.
 * @param offline    True when server is unreachable.
 */
data class DeviceTemplatesUiState(
    val templates: List<DeviceTemplateDto> = emptyList(),
    val isLoading: Boolean = true,
    val isSaving: Boolean = false,
    val error: String? = null,
    val saveError: String? = null,
    val offline: Boolean = false,
)
