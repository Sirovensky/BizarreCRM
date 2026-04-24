package com.bizarreelectronics.crm.ui.screens.memberships

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.EnrollMemberRequest
import com.bizarreelectronics.crm.data.remote.api.Membership
import com.bizarreelectronics.crm.data.remote.api.MembershipApi
import com.bizarreelectronics.crm.data.remote.api.MembershipTier
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import timber.log.Timber
import javax.inject.Inject

// ─── UI state ────────────────────────────────────────────────────────────────

sealed class MembershipUiState {
    data object Loading : MembershipUiState()
    data object NotAvailable : MembershipUiState()
    data class Ready(
        val tiers: List<MembershipTier>,
        val memberships: List<Membership>,
    ) : MembershipUiState()
    data class Error(val message: String) : MembershipUiState()
}

sealed class EnrollState {
    data object Idle : EnrollState()
    data object Loading : EnrollState()
    data class Success(val membership: Membership) : EnrollState()
    data class Error(val message: String) : EnrollState()
}

// ─── ViewModel ───────────────────────────────────────────────────────────────

/**
 * Drives [MembershipListScreen] and the enroll-member flow.
 *
 * 404-tolerant: if the server doesn't implement memberships the state
 * flips to [MembershipUiState.NotAvailable] and the screen shows a
 * graceful "Not available on this server" card. Plan §38 L2997-L3025.
 */
@HiltViewModel
class MembershipViewModel @Inject constructor(
    private val api: MembershipApi,
) : ViewModel() {

    private val _uiState = MutableStateFlow<MembershipUiState>(MembershipUiState.Loading)
    val uiState: StateFlow<MembershipUiState> = _uiState.asStateFlow()

    private val _enrollState = MutableStateFlow<EnrollState>(EnrollState.Idle)
    val enrollState: StateFlow<EnrollState> = _enrollState.asStateFlow()

    init {
        load()
    }

    fun load() {
        viewModelScope.launch {
            _uiState.value = MembershipUiState.Loading
            try {
                val tiersResp = api.getTiers()
                val membersResp = api.getMemberships()
                _uiState.value = MembershipUiState.Ready(
                    tiers = tiersResp.data?.tiers ?: emptyList(),
                    memberships = membersResp.data?.memberships ?: emptyList(),
                )
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    _uiState.value = MembershipUiState.NotAvailable
                } else {
                    _uiState.value = MembershipUiState.Error(
                        e.message() ?: "Server error (${e.code()})"
                    )
                }
            } catch (e: Exception) {
                Timber.e(e, "MembershipViewModel.load")
                _uiState.value = MembershipUiState.Error(e.message ?: "Unknown error")
            }
        }
    }

    /**
     * Enroll a customer into the given tier (§38.2).
     *
     * @param customerId  target customer
     * @param tierId      chosen tier
     * @param billing     "monthly" | "annual"
     * @param paymentMethod  e.g. "cash", "card"
     */
    fun enroll(
        customerId: Long,
        tierId: Long,
        billing: String,
        paymentMethod: String,
    ) {
        viewModelScope.launch {
            _enrollState.value = EnrollState.Loading
            try {
                val resp = api.enroll(
                    EnrollMemberRequest(
                        customerId = customerId,
                        tierId = tierId,
                        billing = billing,
                        paymentMethod = paymentMethod,
                    )
                )
                val membership = resp.data?.membership
                if (membership != null) {
                    _enrollState.value = EnrollState.Success(membership)
                    load()
                } else {
                    _enrollState.value = EnrollState.Error("Enrollment failed — empty response")
                }
            } catch (e: HttpException) {
                _enrollState.value = EnrollState.Error(
                    e.message() ?: "Server error (${e.code()})"
                )
            } catch (e: Exception) {
                Timber.e(e, "MembershipViewModel.enroll")
                _enrollState.value = EnrollState.Error(e.message ?: "Unknown error")
            }
        }
    }

    fun clearEnrollState() {
        _enrollState.value = EnrollState.Idle
    }
}
