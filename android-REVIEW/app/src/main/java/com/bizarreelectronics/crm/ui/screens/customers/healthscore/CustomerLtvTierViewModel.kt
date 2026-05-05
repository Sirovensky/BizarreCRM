package com.bizarreelectronics.crm.ui.screens.customers.healthscore

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.CustomerApi
import com.bizarreelectronics.crm.data.remote.dto.CustomerLtvTier
import retrofit2.HttpException
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * §45.2 — ViewModel for the Customer LTV Tier screen.
 *
 * Fetches [CustomerLtvTier] from GET /customers/:id/ltv-tier.
 * 404-tolerant: [UiState.ltvTier] stays null and the screen shows an
 * informational "Data unavailable" notice rather than crashing.
 *
 * Note: "Tier thresholds per tenant" and "auto-apply pricing rules by tier"
 * are server-side features; this screen is display-only.
 */
data class CustomerLtvTierUiState(
    val isLoading: Boolean = true,
    val ltvTier: CustomerLtvTier? = null,
    val error: String? = null,
)

@HiltViewModel
class CustomerLtvTierViewModel @Inject constructor(
    private val customerApi: CustomerApi,
) : ViewModel() {

    private val _state = MutableStateFlow(CustomerLtvTierUiState())
    val state: StateFlow<CustomerLtvTierUiState> = _state.asStateFlow()

    fun load(customerId: Long) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                val response = customerApi.getLtvTier(customerId)
                _state.value = _state.value.copy(
                    isLoading = false,
                    ltvTier = response.data,
                )
            } catch (e: HttpException) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    // 404 = server endpoint not yet live; display graceful empty state.
                    error = if (e.code() == 404) null else "Failed to load LTV tier (${e.code()})",
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = "Failed to load LTV tier: ${e.message}",
                )
            }
        }
    }
}
