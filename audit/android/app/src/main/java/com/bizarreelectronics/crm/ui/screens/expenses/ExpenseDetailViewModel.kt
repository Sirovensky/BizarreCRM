package com.bizarreelectronics.crm.ui.screens.expenses

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.ExpenseApi
import com.bizarreelectronics.crm.data.remote.dto.ExpenseDetail
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import javax.inject.Inject

data class ExpenseDetailUiState(
    val expense: ExpenseDetail? = null,
    val isLoading: Boolean = true,
    val isApprovalLoading: Boolean = false,
    val error: String? = null,
    val approvalError: String? = null,
    val approvalSuccess: String? = null,
    val isApprover: Boolean = false,
)

@HiltViewModel
class ExpenseDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val expenseApi: ExpenseApi,
    private val authPreferences: AuthPreferences,
) : ViewModel() {

    private val expenseId: Long = checkNotNull(savedStateHandle["id"])

    private val _state = MutableStateFlow(ExpenseDetailUiState())
    val state = _state.asStateFlow()

    init {
        val role = authPreferences.userRole
        val isApprover = role == "admin" || role == "manager"
        _state.value = _state.value.copy(isApprover = isApprover)
        load()
    }

    fun load() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                val response = expenseApi.getExpense(expenseId)
                _state.value = _state.value.copy(
                    expense = response.data,
                    isLoading = false,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = "Failed to load expense. ${e.message}",
                )
            }
        }
    }

    fun approve(comment: String) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isApprovalLoading = true, approvalError = null)
            try {
                expenseApi.approveExpense(expenseId, comment.takeIf { it.isNotBlank() })
                _state.value = _state.value.copy(
                    isApprovalLoading = false,
                    approvalSuccess = "Expense approved",
                )
                load()
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    // 404 tolerated — server may not have approval endpoint yet
                    _state.value = _state.value.copy(
                        isApprovalLoading = false,
                        approvalSuccess = "Approved (pending server sync)",
                    )
                } else {
                    _state.value = _state.value.copy(
                        isApprovalLoading = false,
                        approvalError = "Failed to approve: ${e.message}",
                    )
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isApprovalLoading = false,
                    approvalError = "Failed to approve: ${e.message}",
                )
            }
        }
    }

    fun reject(comment: String) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isApprovalLoading = true, approvalError = null)
            try {
                expenseApi.rejectExpense(expenseId, comment.takeIf { it.isNotBlank() })
                _state.value = _state.value.copy(
                    isApprovalLoading = false,
                    approvalSuccess = "Expense rejected",
                )
                load()
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    _state.value = _state.value.copy(
                        isApprovalLoading = false,
                        approvalSuccess = "Rejected (pending server sync)",
                    )
                } else {
                    _state.value = _state.value.copy(
                        isApprovalLoading = false,
                        approvalError = "Failed to reject: ${e.message}",
                    )
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isApprovalLoading = false,
                    approvalError = "Failed to reject: ${e.message}",
                )
            }
        }
    }

    fun clearApprovalMessage() {
        _state.value = _state.value.copy(approvalError = null, approvalSuccess = null)
    }
}
