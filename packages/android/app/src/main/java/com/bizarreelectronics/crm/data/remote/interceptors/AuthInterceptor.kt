package com.bizarreelectronics.crm.data.remote.interceptors

import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.RefreshResponse
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import javax.inject.Inject
import javax.inject.Singleton

/**
 * OkHttp interceptor that handles JWT authentication.
 *
 * - Attaches Authorization: Bearer {token} header to every request
 * - On 401 response: attempts token refresh via /auth/refresh
 * - If refresh succeeds: retries the original request with the new token
 * - If refresh fails: clears auth state so the user must re-login
 */
@Singleton
class AuthInterceptor @Inject constructor(
    private val authPrefs: AuthPreferences,
    private val gson: Gson
) : Interceptor {

    companion object {
        private const val HEADER_AUTHORIZATION = "Authorization"
        private const val BEARER_PREFIX = "Bearer "
    }

    @Volatile
    private var isRefreshing = false

    override fun intercept(chain: Interceptor.Chain): Response {
        val originalRequest = chain.request()

        // Skip auth header for login, refresh, and public endpoints
        if (isAuthEndpoint(originalRequest)) {
            return chain.proceed(originalRequest)
        }

        val token = getAccessToken()
        val authenticatedRequest = if (token != null) {
            originalRequest.newBuilder()
                .header(HEADER_AUTHORIZATION, "$BEARER_PREFIX$token")
                .build()
        } else {
            originalRequest
        }

        val response = chain.proceed(authenticatedRequest)

        // If we get a 401, attempt a token refresh
        if (response.code == 401 && !isRefreshEndpoint(originalRequest)) {
            synchronized(this) {
                // Double-check: another thread may have already refreshed
                val currentToken = getAccessToken()
                if (currentToken != null && currentToken == token) {
                    // Token hasn't changed, we need to refresh
                    val newToken = attemptTokenRefresh(chain)
                    if (newToken != null) {
                        // Close the original 401 response
                        response.close()

                        // Retry with the new token
                        val retryRequest = originalRequest.newBuilder()
                            .header(HEADER_AUTHORIZATION, "$BEARER_PREFIX$newToken")
                            .build()
                        return chain.proceed(retryRequest)
                    } else {
                        // Refresh failed, clear auth state
                        clearAuthState()
                    }
                } else if (currentToken != null) {
                    // Another thread already refreshed, retry with the new token
                    response.close()
                    val retryRequest = originalRequest.newBuilder()
                        .header(HEADER_AUTHORIZATION, "$BEARER_PREFIX$currentToken")
                        .build()
                    return chain.proceed(retryRequest)
                }
            }
        }

        return response
    }

    private fun attemptTokenRefresh(chain: Interceptor.Chain): String? {
        if (isRefreshing) return null

        isRefreshing = true
        try {
            // Send refresh token in body (server also accepts from cookie for browsers)
            val storedRefreshToken = authPrefs.refreshToken ?: return null
            val refreshBody = """{"refreshToken":"$storedRefreshToken"}"""
                .toRequestBody("application/json; charset=utf-8".toMediaType())
            val refreshRequest = chain.request().newBuilder()
                .url(
                    chain.request().url.newBuilder()
                        .encodedPath("/api/v1/auth/refresh")
                        .query(null)
                        .build()
                )
                .post(refreshBody)
                .removeHeader(HEADER_AUTHORIZATION)
                .addHeader("Content-Type", "application/json")
                .build()

            val refreshResponse = chain.proceed(refreshRequest)

            if (refreshResponse.isSuccessful) {
                val body = refreshResponse.body?.string()
                refreshResponse.close()

                if (body != null) {
                    val type = object : TypeToken<ApiResponse<RefreshResponse>>() {}.type
                    val parsed: ApiResponse<RefreshResponse> = gson.fromJson(body, type)
                    val newToken = parsed.data?.accessToken

                    if (newToken != null) {
                        saveAccessToken(newToken)
                        return newToken
                    }
                }
            } else {
                refreshResponse.close()
            }
        } catch (e: Exception) {
            // Refresh request failed (network error, etc.)
        } finally {
            isRefreshing = false
        }

        return null
    }

    private fun getAccessToken(): String? {
        return authPrefs.accessToken
    }

    private fun saveAccessToken(token: String) {
        authPrefs.accessToken = token
    }

    private fun clearAuthState() {
        authPrefs.clear()
    }

    private fun isAuthEndpoint(request: Request): Boolean {
        val path = request.url.encodedPath
        return path.contains("/auth/login") && !path.contains("/auth/login/2fa")
    }

    private fun isRefreshEndpoint(request: Request): Boolean {
        return request.url.encodedPath.contains("/auth/refresh")
    }
}
