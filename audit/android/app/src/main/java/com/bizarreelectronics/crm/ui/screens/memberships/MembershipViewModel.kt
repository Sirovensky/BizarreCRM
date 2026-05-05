package com.bizarreelectronics.crm.ui.screens.memberships

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.Membership
import com.bizarreelectronics.crm.data.remote.api.MembershipTier
import com.bizarreelectronics.crm.data.repository.MembershipRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
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

sealed class CancelState {
    data object Idle : CancelState()
    data object Loading : CancelState()
    data object Success : CancelState()
    data class Error(val message: String) : CancelState()
}

// ─── ViewModel ───────────────────────────────────────────────────────────────

/**
 * Drives [MembershipListScreen] and the enroll-member / cancel-membership flows.
 *
 * Uses [MembershipRepository] for all API calls. 404-tolerant: if the server
 * doesn't implement memberships the state flips to [MembershipUiState.NotAvailable]
 * and the screen shows a graceful "Not available on this server" card.
 *
 * Plan §38 L3298-L3327.
 */
@HiltViewModel
class MembershipViewModel @Inject constructor(
    private val repo: MembershipRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow<MembershipUiState>(MembershipUiState.Loading)
    val uiState: StateFlow<MembershipUiState> = _uiState.asStateFlow()

    private val _enrollState = MutableStateFlow<EnrollState>(EnrollState.Idle)
    val enrollState: StateFlow<EnrollState> = _enrollState.asStateFlow()

    private val _cancelState = MutableStateFlow<CancelState>(CancelState.Idle)
    val cancelState: StateFlow<CancelState> = _cancelState.asStateFlow()

    init {
        load()
    }

    fun load() {
        viewModelScope.launch {
            _uiState.value = MembershipUiState.Loading
            val tiersResult = repo.getTiers()
            val membersResult = repo.getMemberships()

            tiersResult.fold(
                onSuccess = { tiers ->
                    membersResult.fold(
                        onSuccess = { memberships ->
                            _uiState.value = MembershipUiState.Ready(
                                tiers = tiers,
                                memberships = memberships,
                            )
                        },
                        onFailure = { e -> handleLoadError(e) },
                    )
                },
                onFailure = { e -> handleLoadError(e) },
            )
        }
    }

    private fun handleLoadError(e: Throwable) {
        Timber.e(e, "MembershipViewModel.load")
        when (e) {
            is MembershipRepository.NotAvailableException ->
                _uiState.value = MembershipUiState.NotAvailable
            else ->
                _uiState.value = MembershipUiState.Error(e.message ?: "Unknown error")
        }
    }

    /**
     * Enroll a customer into the given tier (§38.2).
     */
    fun enroll(
        customerId: Long,
        tierId: Long,
        billing: String,
        paymentMethod: String,
    ) {
        viewModelScope.launch {
            _enrollState.value = EnrollState.Loading
            repo.enroll(customerId, tierId, billing, paymentMethod).fold(
                onSuccess = { membership ->
                    _enrollState.value = EnrollState.Success(membership)
                    load()
                },
                onFailure = { e ->
                    Timber.e(e, "MembershipViewModel.enroll")
                    _enrollState.value = EnrollState.Error(e.message ?: "Enrollment failed")
                },
            )
        }
    }

    fun clearEnrollState() {
        _enrollState.value = EnrollState.Idle
    }

    /**
     * Cancel a membership. Caller should show a [ConfirmDialog] before invoking.
     * [immediate] = true = cancel now; false = cancel at period end.
     * Plan §38.2 — cancel flow with ConfirmDialog.
     */
    fun cancelMembership(membershipId: Long, immediate: Boolean = false) {
        viewModelScope.launch {
            _cancelState.value = CancelState.Loading
            repo.cancel(membershipId, immediate).fold(
                onSuccess = {
                    _cancelState.value = CancelState.Success
                    load()
                },
                onFailure = { e ->
                    Timber.e(e, "MembershipViewModel.cancel")
                    _cancelState.value = CancelState.Error(e.message ?: "Cancel failed")
                },
            )
        }
    }

    fun clearCancelState() {
        _cancelState.value = CancelState.Idle
    }
}
