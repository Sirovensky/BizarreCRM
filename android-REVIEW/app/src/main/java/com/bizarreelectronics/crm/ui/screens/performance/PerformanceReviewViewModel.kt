package com.bizarreelectronics.crm.ui.screens.performance

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.PerformanceApi
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import javax.inject.Inject

/** Ratings for a single performance review category (1–5 scale). */
data class ReviewRatings(
    val quality: Int = 0,
    val speed: Int = 0,
    val attitude: Int = 0,
    val teamwork: Int = 0,
    val overall: Int = 0,
)

/** A single performance review record. */
data class PerformanceReview(
    val id: Long,
    val employeeId: Long,
    val employeeName: String,
    val cycle: String,
    val reviewDate: String,
    val ratings: ReviewRatings,
    val managerComments: String,
    val reviewerName: String,
)

data class PerformanceReviewUiState(
    val reviews: List<PerformanceReview> = emptyList(),
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val serverUnsupported: Boolean = false,
    val isManager: Boolean = false,
    val showCreateDialog: Boolean = false,
    val toastMessage: String? = null,
)

/**
 * §48.2 — Performance Reviews ViewModel
 *
 * Role gate:
 *  - Staff: sees own reviews (server scopes by JWT).
 *  - Manager/Admin: sees all employees' reviews; can create new reviews.
 *
 * 404-tolerant: shows "not configured" empty state on HttpException(404).
 */
@HiltViewModel
class PerformanceReviewViewModel @Inject constructor(
    private val performanceApi: PerformanceApi,
    private val authPreferences: AuthPreferences,
    private val serverMonitor: ServerReachabilityMonitor,
) : ViewModel() {

    private val _state = MutableStateFlow(PerformanceReviewUiState())
    val state = _state.asStateFlow()

    private val isManagerOrAdmin: Boolean
        get() = authPreferences.userRole?.lowercase() in setOf("manager", "admin", "owner")

    init {
        _state.value = _state.value.copy(isManager = isManagerOrAdmin)
        loadReviews()
    }

    fun loadReviews() {
        if (!serverMonitor.isEffectivelyOnline.value) {
            _state.value = _state.value.copy(isLoading = false, error = "Device is offline")
            return
        }
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = _state.value.reviews.isEmpty(), error = null)
            try {
                val response = performanceApi.getReviews()
                val list = parseReviewList(response.data)
                _state.value = _state.value.copy(
                    isLoading = false, isRefreshing = false,
                    reviews = list, serverUnsupported = false,
                )
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    _state.value = _state.value.copy(
                        isLoading = false, isRefreshing = false,
                        serverUnsupported = true, reviews = emptyList(),
                    )
                } else {
                    _state.value = _state.value.copy(
                        isLoading = false, isRefreshing = false,
                        error = "Failed to load reviews (${e.code()})",
                    )
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false, isRefreshing = false,
                    error = e.message ?: "Failed to load reviews",
                )
            }
        }
    }

    fun refresh() {
        _state.value = _state.value.copy(isRefreshing = true)
        loadReviews()
    }

    fun showCreateDialog() {
        _state.value = _state.value.copy(showCreateDialog = true)
    }

    fun dismissCreateDialog() {
        _state.value = _state.value.copy(showCreateDialog = false)
    }

    fun submitReview(
        employeeId: Long,
        cycle: String,
        ratings: ReviewRatings,
        comments: String,
        reviewDate: String,
    ) {
        if (employeeId <= 0L) {
            _state.value = _state.value.copy(toastMessage = "Employee is required")
            return
        }
        viewModelScope.launch {
            val body = buildMap<String, Any> {
                put("employee_id", employeeId)
                put("cycle", cycle)
                put("review_date", reviewDate)
                put("manager_comments", comments)
                put("ratings", mapOf(
                    "quality" to ratings.quality,
                    "speed" to ratings.speed,
                    "attitude" to ratings.attitude,
                    "teamwork" to ratings.teamwork,
                    "overall" to ratings.overall,
                ))
            }
            runCatching { performanceApi.createReview(body) }
                .onSuccess {
                    _state.value = _state.value.copy(
                        showCreateDialog = false,
                        toastMessage = "Review submitted",
                    )
                    loadReviews()
                }
                .onFailure {
                    _state.value = _state.value.copy(toastMessage = "Failed to submit review")
                }
        }
    }

    fun clearToast() {
        _state.value = _state.value.copy(toastMessage = null)
    }

    // ── Parsing helpers ───────────────────────────────────────────────────────

    @Suppress("UNCHECKED_CAST")
    private fun parseReviewList(data: Any?): List<PerformanceReview> {
        val map = data as? Map<*, *> ?: return emptyList()
        val list = map["reviews"] as? List<*> ?: return emptyList()
        return list.mapNotNull { entry ->
            val m = entry as? Map<*, *> ?: return@mapNotNull null
            val ratingsMap = m["ratings"] as? Map<*, *>
            PerformanceReview(
                id = (m["id"] as? Number)?.toLong() ?: return@mapNotNull null,
                employeeId = (m["employee_id"] as? Number)?.toLong() ?: 0L,
                employeeName = m["employee_name"] as? String ?: "",
                cycle = m["cycle"] as? String ?: "",
                reviewDate = m["review_date"] as? String ?: "",
                managerComments = m["manager_comments"] as? String ?: "",
                reviewerName = m["reviewer_name"] as? String ?: "",
                ratings = ReviewRatings(
                    quality = (ratingsMap?.get("quality") as? Number)?.toInt() ?: 0,
                    speed = (ratingsMap?.get("speed") as? Number)?.toInt() ?: 0,
                    attitude = (ratingsMap?.get("attitude") as? Number)?.toInt() ?: 0,
                    teamwork = (ratingsMap?.get("teamwork") as? Number)?.toInt() ?: 0,
                    overall = (ratingsMap?.get("overall") as? Number)?.toInt() ?: 0,
                ),
            )
        }
    }
}
