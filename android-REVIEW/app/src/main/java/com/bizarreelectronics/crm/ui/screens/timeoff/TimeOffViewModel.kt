package com.bizarreelectronics.crm.ui.screens.timeoff

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.TimeOffApi
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import javax.inject.Inject

/** Types of time-off request matching the server enum. */
enum class TimeOffType(val label: String, val apiValue: String) {
    Vacation("Vacation", "vacation"),
    Sick("Sick Leave", "sick"),
    Personal("Personal", "personal"),
    Unpaid("Unpaid", "unpaid"),
}

/** Status of a time-off request. */
enum class TimeOffStatus(val label: String) {
    Pending("Pending"),
    Approved("Approved"),
    Rejected("Rejected"),
    Cancelled("Cancelled"),
}

/** A single time-off request record. */
data class TimeOffRequest(
    val id: Long,
    val employeeId: Long,
    val employeeName: String,
    val startDate: String,
    val endDate: String,
    val type: String,
    val reason: String,
    val status: TimeOffStatus,
    val managerReason: String,
    val createdAt: String,
)

data class TimeOffUiState(
    val requests: List<TimeOffRequest> = emptyList(),
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val serverUnsupported: Boolean = false,
    val isManager: Boolean = false,
    /** null = "All" (manager); "pending" / "approved" etc. */
    val statusFilter: String? = null,
    val showRequestDialog: Boolean = false,
    val toastMessage: String? = null,
)

/**
 * §48.3 — Time-Off ViewModel (shared between staff request + manager queue screens).
 *
 * Role gate:
 *  - Staff: loads own requests; can submit new requests and cancel pending ones.
 *  - Manager/Admin: loads all pending requests by default; can approve/reject.
 *
 * 404-tolerant: shows "not configured on this server" empty state.
 */
@HiltViewModel
class TimeOffViewModel @Inject constructor(
    private val timeOffApi: TimeOffApi,
    private val authPreferences: AuthPreferences,
    private val serverMonitor: ServerReachabilityMonitor,
) : ViewModel() {

    private val _state = MutableStateFlow(TimeOffUiState())
    val state = _state.asStateFlow()

    private val isManagerOrAdmin: Boolean
        get() = authPreferences.userRole?.lowercase() in setOf("manager", "admin", "owner")

    init {
        val isManager = isManagerOrAdmin
        _state.value = _state.value.copy(
            isManager = isManager,
            statusFilter = if (isManager) "pending" else null,
        )
        loadRequests()
    }

    fun loadRequests() {
        if (!serverMonitor.isEffectivelyOnline.value) {
            _state.value = _state.value.copy(isLoading = false, error = "Device is offline")
            return
        }
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = _state.value.requests.isEmpty(), error = null)
            try {
                val response = timeOffApi.getRequests(status = _state.value.statusFilter)
                val list = parseRequestList(response.data)
                _state.value = _state.value.copy(
                    isLoading = false, isRefreshing = false,
                    requests = list, serverUnsupported = false,
                )
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    _state.value = _state.value.copy(
                        isLoading = false, isRefreshing = false,
                        serverUnsupported = true, requests = emptyList(),
                    )
                } else {
                    _state.value = _state.value.copy(
                        isLoading = false, isRefreshing = false,
                        error = "Failed to load requests (${e.code()})",
                    )
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false, isRefreshing = false,
                    error = e.message ?: "Failed to load requests",
                )
            }
        }
    }

    fun refresh() {
        _state.value = _state.value.copy(isRefreshing = true)
        loadRequests()
    }

    fun setStatusFilter(status: String?) {
        _state.value = _state.value.copy(statusFilter = status)
        loadRequests()
    }

    fun showRequestDialog() {
        _state.value = _state.value.copy(showRequestDialog = true)
    }

    fun dismissRequestDialog() {
        _state.value = _state.value.copy(showRequestDialog = false)
    }

    /** Staff submits a time-off request. */
    fun submitRequest(
        startDate: String,
        endDate: String,
        type: TimeOffType,
        reason: String,
    ) {
        if (startDate.isBlank() || endDate.isBlank()) {
            _state.value = _state.value.copy(toastMessage = "Start and end dates are required")
            return
        }
        viewModelScope.launch {
            val body = mapOf<String, Any>(
                "start_date" to startDate,
                "end_date" to endDate,
                "type" to type.apiValue,
                "reason" to reason,
            )
            runCatching { timeOffApi.submitRequest(body) }
                .onSuccess {
                    _state.value = _state.value.copy(
                        showRequestDialog = false,
                        toastMessage = "Time-off request submitted",
                    )
                    loadRequests()
                }
                .onFailure {
                    _state.value = _state.value.copy(toastMessage = "Failed to submit request")
                }
        }
    }

    /** Manager approves a pending request. */
    fun approveRequest(requestId: Long) {
        viewModelScope.launch {
            runCatching {
                timeOffApi.updateRequest(requestId, mapOf("action" to "approve"))
            }
                .onSuccess {
                    _state.value = _state.value.copy(toastMessage = "Request approved")
                    loadRequests()
                }
                .onFailure {
                    _state.value = _state.value.copy(toastMessage = "Failed to approve request")
                }
        }
    }

    /** Manager rejects a pending request with an optional reason. */
    fun rejectRequest(requestId: Long, reason: String) {
        viewModelScope.launch {
            val body = buildMap<String, Any> {
                put("action", "reject")
                if (reason.isNotBlank()) put("reason", reason)
            }
            runCatching { timeOffApi.updateRequest(requestId, body) }
                .onSuccess {
                    _state.value = _state.value.copy(toastMessage = "Request rejected")
                    loadRequests()
                }
                .onFailure {
                    _state.value = _state.value.copy(toastMessage = "Failed to reject request")
                }
        }
    }

    /** Staff cancels their own pending request. */
    fun cancelRequest(requestId: Long) {
        viewModelScope.launch {
            runCatching {
                timeOffApi.updateRequest(requestId, mapOf("action" to "cancel"))
            }
                .onSuccess {
                    _state.value = _state.value.copy(toastMessage = "Request cancelled")
                    loadRequests()
                }
                .onFailure {
                    _state.value = _state.value.copy(toastMessage = "Failed to cancel request")
                }
        }
    }

    fun clearToast() {
        _state.value = _state.value.copy(toastMessage = null)
    }

    // ── Parsing helpers ───────────────────────────────────────────────────────

    @Suppress("UNCHECKED_CAST")
    private fun parseRequestList(data: Any?): List<TimeOffRequest> {
        val map = data as? Map<*, *> ?: return emptyList()
        val list = map["requests"] as? List<*> ?: return emptyList()
        return list.mapNotNull { entry ->
            val m = entry as? Map<*, *> ?: return@mapNotNull null
            val rawStatus = (m["status"] as? String)?.lowercase() ?: "pending"
            val status = when (rawStatus) {
                "approved" -> TimeOffStatus.Approved
                "rejected" -> TimeOffStatus.Rejected
                "cancelled" -> TimeOffStatus.Cancelled
                else -> TimeOffStatus.Pending
            }
            TimeOffRequest(
                id = (m["id"] as? Number)?.toLong() ?: return@mapNotNull null,
                employeeId = (m["employee_id"] as? Number)?.toLong() ?: 0L,
                employeeName = m["employee_name"] as? String ?: "",
                startDate = m["start_date"] as? String ?: "",
                endDate = m["end_date"] as? String ?: "",
                type = m["type"] as? String ?: "",
                reason = m["reason"] as? String ?: "",
                status = status,
                managerReason = m["manager_reason"] as? String ?: "",
                createdAt = m["created_at"] as? String ?: "",
            )
        }
    }
}
