package com.bizarreelectronics.crm.ui.screens.goals

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.GoalApi
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import javax.inject.Inject

/** A single goal item returned by the server. */
data class GoalItem(
    val id: Long,
    val title: String,
    val metric: String,           // tickets | revenue | commission | nps
    val target: Double,
    val progress: Double,
    val period: String,           // e.g. "2026-04"
    val employeeId: Long,
    val employeeName: String,
    val isTeamGoal: Boolean,
)

data class GoalsUiState(
    val goals: List<GoalItem> = emptyList(),
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val serverUnsupported: Boolean = false,
    val isManager: Boolean = false,
    val showCreateDialog: Boolean = false,
    val toastMessage: String? = null,
)

/**
 * §48.1 — Goals ViewModel
 *
 * Role gate:
 *  - Staff: loads own goals only (no employeeId filter needed — server scopes by JWT).
 *  - Manager/Admin: loads all goals; can create goals for any employee.
 *
 * 404-tolerant: server may not implement /goals yet — shows empty "not configured"
 * state rather than an error.
 */
@HiltViewModel
class GoalsViewModel @Inject constructor(
    private val goalApi: GoalApi,
    private val authPreferences: AuthPreferences,
    private val serverMonitor: ServerReachabilityMonitor,
) : ViewModel() {

    private val _state = MutableStateFlow(GoalsUiState())
    val state = _state.asStateFlow()

    private val isManagerOrAdmin: Boolean
        get() = authPreferences.userRole?.lowercase() in setOf("manager", "admin", "owner")

    init {
        _state.value = _state.value.copy(isManager = isManagerOrAdmin)
        loadGoals()
    }

    fun loadGoals() {
        if (!serverMonitor.isEffectivelyOnline.value) {
            _state.value = _state.value.copy(isLoading = false, error = "Device is offline")
            return
        }
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = _state.value.goals.isEmpty(), error = null)
            try {
                val response = goalApi.getGoals()
                val rawList = parseGoalList(response.data)
                _state.value = _state.value.copy(
                    isLoading = false,
                    isRefreshing = false,
                    goals = rawList,
                    serverUnsupported = false,
                )
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    _state.value = _state.value.copy(
                        isLoading = false, isRefreshing = false,
                        serverUnsupported = true, goals = emptyList(),
                    )
                } else {
                    _state.value = _state.value.copy(
                        isLoading = false, isRefreshing = false,
                        error = "Failed to load goals (${e.code()})",
                    )
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false, isRefreshing = false,
                    error = e.message ?: "Failed to load goals",
                )
            }
        }
    }

    fun refresh() {
        _state.value = _state.value.copy(isRefreshing = true)
        loadGoals()
    }

    fun showCreateDialog() {
        _state.value = _state.value.copy(showCreateDialog = true)
    }

    fun dismissCreateDialog() {
        _state.value = _state.value.copy(showCreateDialog = false)
    }

    /** Create a new goal. [employeeId] defaults to current user if null. */
    fun createGoal(
        title: String,
        metric: String,
        target: Double,
        period: String,
        isTeamGoal: Boolean,
        employeeId: Long? = null,
    ) {
        if (title.isBlank()) {
            _state.value = _state.value.copy(toastMessage = "Title is required")
            return
        }
        viewModelScope.launch {
            val body = buildMap<String, Any> {
                put("title", title)
                put("metric", metric)
                put("target", target)
                put("period", period)
                put("is_team_goal", isTeamGoal)
                if (employeeId != null) put("employee_id", employeeId)
            }
            runCatching { goalApi.createGoal(body) }
                .onSuccess {
                    _state.value = _state.value.copy(
                        showCreateDialog = false,
                        toastMessage = "Goal created",
                    )
                    loadGoals()
                }
                .onFailure {
                    _state.value = _state.value.copy(toastMessage = "Failed to create goal")
                }
        }
    }

    fun deleteGoal(id: Long) {
        viewModelScope.launch {
            runCatching { goalApi.deleteGoal(id) }
                .onSuccess {
                    _state.value = _state.value.copy(toastMessage = "Goal removed")
                    loadGoals()
                }
                .onFailure {
                    _state.value = _state.value.copy(toastMessage = "Failed to remove goal")
                }
        }
    }

    fun clearToast() {
        _state.value = _state.value.copy(toastMessage = null)
    }

    // ── Parsing helpers ───────────────────────────────────────────────────────

    @Suppress("UNCHECKED_CAST")
    private fun parseGoalList(data: Any?): List<GoalItem> {
        val map = data as? Map<*, *> ?: return emptyList()
        val list = map["goals"] as? List<*> ?: return emptyList()
        return list.mapNotNull { entry ->
            val m = entry as? Map<*, *> ?: return@mapNotNull null
            GoalItem(
                id = (m["id"] as? Number)?.toLong() ?: return@mapNotNull null,
                title = m["title"] as? String ?: "",
                metric = m["metric"] as? String ?: "tickets",
                target = (m["target"] as? Number)?.toDouble() ?: 0.0,
                progress = (m["progress"] as? Number)?.toDouble() ?: 0.0,
                period = m["period"] as? String ?: "",
                employeeId = (m["employee_id"] as? Number)?.toLong() ?: 0L,
                employeeName = m["employee_name"] as? String ?: "",
                isTeamGoal = m["is_team_goal"] as? Boolean ?: false,
            )
        }
    }
}
