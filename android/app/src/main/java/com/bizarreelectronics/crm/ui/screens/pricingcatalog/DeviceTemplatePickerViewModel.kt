package com.bizarreelectronics.crm.ui.screens.pricingcatalog

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.ApplyTemplateBody
import com.bizarreelectronics.crm.data.remote.api.ApplyTemplateResult
import com.bizarreelectronics.crm.data.remote.api.DeviceTemplateApi
import com.bizarreelectronics.crm.data.remote.api.DeviceTemplateDto
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import javax.inject.Inject

/**
 * DeviceTemplatePickerViewModel — §44.1
 *
 * Backs [DeviceTemplatePickerSheet]. Loads all templates on init; applies
 * client-side search filter against [onSearchChanged]. The "Apply" button calls
 * [applyTemplate] which POSTs to the server and exposes the result via
 * [TemplatePickerUiState.applyResult].
 */
@HiltViewModel
class DeviceTemplatePickerViewModel @Inject constructor(
    private val deviceTemplateApi: DeviceTemplateApi,
) : ViewModel() {

    private val _state = MutableStateFlow(TemplatePickerUiState())
    val state = _state.asStateFlow()

    init {
        loadTemplates()
    }

    private fun loadTemplates() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true)
            try {
                val response = deviceTemplateApi.getTemplates()
                val all = response.data ?: emptyList()
                _state.value = _state.value.copy(
                    isLoading = false,
                    allTemplates = all,
                    filteredTemplates = all,
                )
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    _state.value = _state.value.copy(isLoading = false)
                } else {
                    _state.value = _state.value.copy(
                        isLoading = false,
                        applyError = "Failed to load templates (${e.code()})",
                    )
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    applyError = e.message ?: "Failed to load templates",
                )
            }
        }
    }

    /** Filter templates client-side by name, model, or repair names. */
    fun onSearchChanged(query: String) {
        _state.value = _state.value.copy(searchQuery = query)
        val q = query.trim().lowercase()
        _state.value = _state.value.copy(
            filteredTemplates = if (q.isBlank()) {
                _state.value.allTemplates
            } else {
                _state.value.allTemplates.filter { t ->
                    t.name.lowercase().contains(q) ||
                        t.displaySubtitle?.lowercase()?.contains(q) == true ||
                        t.displayRepairs.any { r -> r.lowercase().contains(q) }
                }
            }
        )
    }

    /**
     * Apply a template to a ticket. Sets [TemplatePickerUiState.applyResult] on success.
     *
     * @param templateId      Template to apply.
     * @param ticketId        Target ticket.
     * @param ticketDeviceId  Optional ticket device binding.
     */
    fun applyTemplate(
        templateId: Long,
        ticketId: Long,
        ticketDeviceId: Long? = null,
    ) {
        viewModelScope.launch {
            _state.value = _state.value.copy(applyingId = templateId, applyError = null)
            try {
                val response = deviceTemplateApi.applyTemplate(
                    id = templateId,
                    ticketId = ticketId,
                    body = ApplyTemplateBody(ticketDeviceId = ticketDeviceId),
                )
                _state.value = _state.value.copy(
                    applyingId = null,
                    applyResult = response.data,
                )
            } catch (e: HttpException) {
                _state.value = _state.value.copy(
                    applyingId = null,
                    applyError = "Apply failed (${e.code()})",
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    applyingId = null,
                    applyError = e.message ?: "Apply failed",
                )
            }
        }
    }

    /** Clear apply result after caller has consumed it. */
    fun clearApplyResult() {
        _state.value = _state.value.copy(applyResult = null)
    }
}

/**
 * UI state for [DeviceTemplatePickerSheet].
 *
 * @param allTemplates       Full unfiltered list from server.
 * @param filteredTemplates  List after applying [searchQuery].
 * @param searchQuery        Active search string.
 * @param isLoading          True while loading.
 * @param applyingId         ID of template currently being applied; null otherwise.
 * @param applyResult        Result of last successful apply; null until applied.
 * @param applyError         Error from last apply or load; null when none.
 */
data class TemplatePickerUiState(
    val allTemplates: List<DeviceTemplateDto> = emptyList(),
    val filteredTemplates: List<DeviceTemplateDto> = emptyList(),
    val searchQuery: String = "",
    val isLoading: Boolean = false,
    val applyingId: Long? = null,
    val applyResult: ApplyTemplateResult? = null,
    val applyError: String? = null,
)
