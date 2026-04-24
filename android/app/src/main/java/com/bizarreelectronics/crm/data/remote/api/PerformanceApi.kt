package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query

/**
 * §48.2 — Performance Reviews API
 *
 * Server endpoints:
 *   GET  /performance/reviews              — list reviews (manager: all; staff: own)
 *   POST /performance/reviews              — manager creates/submits a review
 *   GET  /performance/reviews/:id          — single review detail
 *
 * All endpoints are 404-tolerant; callers show "not configured on this server"
 * empty state on HttpException(404) or network failure.
 */
interface PerformanceApi {

    /**
     * List performance reviews.
     * [employeeId] filters by staff member (manager only).
     * [cycle] filters by cycle label, e.g. "Q1-2026" or "annual-2025".
     * Returns { reviews: [...] }.
     */
    @GET("performance/reviews")
    suspend fun getReviews(
        @Query("employee_id") employeeId: Long? = null,
        @Query("cycle") cycle: String? = null,
    ): ApiResponse<@JvmSuppressWildcards Any>

    /**
     * Fetch a single review.
     * Returns { review: { ... } }.
     */
    @GET("performance/reviews/{id}")
    suspend fun getReview(
        @Path("id") reviewId: Long,
    ): ApiResponse<@JvmSuppressWildcards Any>

    /**
     * Create or submit a performance review.
     * Body: { employee_id, cycle, ratings: {quality,speed,attitude,teamwork,overall},
     *          manager_comments, review_date }
     */
    @POST("performance/reviews")
    suspend fun createReview(
        @Body body: Map<String, @JvmSuppressWildcards Any>,
    ): ApiResponse<@JvmSuppressWildcards Any>
}
