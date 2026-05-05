package com.bizarreelectronics.crm.ui.screens.customers.healthscore

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.CustomerApi
import com.bizarreelectronics.crm.data.remote.dto.CustomerHealthScore
import retrofit2.HttpException
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * §45.1 — ViewModel for the Customer Health Score screen.
 *
 * Fetches [CustomerHealthScore] from GET /customers/:id/health-score.
 * Exposes a [recalculate] action that calls POST /customers/:id/health-score/recalculate.
 * Both calls are 404-tolerant: [UiState.error] is set on failure so the screen
 * can show a graceful empty state rather than crashing.
 */

data class CustomerHealthScoreUiState(
    val isLoading: Boolean = true,
    val isRecalculating: Boolean = false,
    val healthScore: CustomerHealthScore? = null,
    val error: String? = null,
    val showExplanationSheet: Boolean = false,
)

@HiltViewModel
class CustomerHealthScoreViewModel @Inject constructor(
    private val customerApi: CustomerApi,
) : ViewModel() {

    private val _state = MutableStateFlow(CustomerHealthScoreUiState())
    val state: StateFlow<CustomerHealthScoreUiState> = _state.asStateFlow()

    fun load(customerId: Long) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                val response = customerApi.getHealthScore(customerId)
                _state.value = _state.value.copy(
                    isLoading = false,
                    healthScore = response.data,
                )
            } catch (e: HttpException) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = if (e.code() == 404) null else "Failed to load health score (${e.code()})",
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = "Failed to load health score: ${e.message}",
                )
            }
        }
    }

    fun recalculate(customerId: Long) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isRecalculating = true)
            try {
                val response = customerApi.recalculateHealthScore(customerId)
                _state.value = _state.value.copy(
                    isRecalculating = false,
                    healthScore = response.data ?: _state.value.healthScore,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isRecalculating = false,
                    error = "Recalculation failed: ${e.message}",
                )
            }
        }
    }

    fun openExplanationSheet() {
        _state.value = _state.value.copy(showExplanationSheet = true)
    }

    fun dismissExplanationSheet() {
        _state.value = _state.value.copy(showExplanationSheet = false)
    }
}
