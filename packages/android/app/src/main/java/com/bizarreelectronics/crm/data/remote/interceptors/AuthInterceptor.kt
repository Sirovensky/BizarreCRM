package com.bizarreelectronics.crm.data.remote.interceptors

import android.util.Log
import com.bizarreelectronics.crm.BuildConfig
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.RefreshResponse
import com.google.gson.Gson
import com.google.gson.JsonObject
import com.google.gson.reflect.TypeToken
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.util.concurrent.TimeUnit
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
        private const val TAG = "AuthInterceptor"
        private const val HEADER_AUTHORIZATION = "Authorization"
        private const val BEARER_PREFIX = "Bearer "
        private const val LOGOUT_TIMEOUT_MS = 2_000L
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
                        clearAuthState(chain)
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
            // Use JsonObject to properly escape any special characters in the token
            val storedRefreshToken = authPrefs.refreshToken
            if (storedRefreshToken.isNullOrBlank()) {
                // No refresh token on disk — the session is dead. Wipe state and
                // emit the logout event so the UI can bounce back to login.
                if (BuildConfig.DEBUG) {
                    Log.w(TAG, "No refresh token stored; forcing logout")
                }
                clearAuthState(chain)
                return null
            }

            val bodyJson = JsonObject().apply {
                addProperty("refreshToken", storedRefreshToken)
            }.toString()
            val refreshBody = bodyJson
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
                // 2xx but no token in payload — treat as a failed refresh.
                clearAuthState(chain)
            } else {
                // Only wipe tokens on 401/403 — server explicitly says this
                // refresh token is revoked/expired. Other codes (500/502/503,
                // tenant-resolver 404, gateway HTML) can be transient and
                // previously also dropped the user back to the login screen
                // after a wifi blip or restart window. Preserve tokens so
                // the next attempt can retry once the server is back.
                val code = refreshResponse.code
                refreshResponse.close()
                if (code == 401 || code == 403) {
                    clearAuthState(chain)
                } else {
                    if (BuildConfig.DEBUG) {
                        Log.w(TAG, "Refresh got HTTP $code (transient?); keeping tokens for retry")
                    }
                }
            }
        } catch (e: Exception) {
            // Network / IO error — DO NOT wipe tokens. Previously any exception
            // here (wifi blip, DNS hiccup, server not yet reachable after
            // phone wake) logged the user out and forced a username/password
            // re-entry on the next app launch. Keep the tokens so the next
            // authenticated request can retry the refresh once the network
            // is back. A revoked token still surfaces as the 401/403 branch
            // above on the first successful round-trip.
            if (BuildConfig.DEBUG) {
                Log.w(TAG, "Token refresh failed (network); keeping tokens: ${e.javaClass.simpleName}")
            }
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

    /**
     * Revokes the server-side session and refresh token BEFORE wiping local
     * preferences (SEC-H102).
     *
     * Strategy:
     * - Derive the logout URL from the in-flight request's base URL so we
     *   respect whatever server URL is configured in prefs.
     * - The access token is still in prefs at call time, so we attach it in the
     *   Authorization header — the server needs it to identify the session row.
     * - A bare OkHttpClient (no interceptors, no auth retry) is used to avoid
     *   recursive interception. It has a strict 2-second call timeout.
     * - Any failure (4xx, 5xx, timeout, network error) is best-effort: log at
     *   WARN and always proceed to wipe local state.
     */
    private fun clearAuthState(chain: Interceptor.Chain) {
        val currentToken = authPrefs.accessToken
        if (currentToken != null) {
            try {
                val logoutUrl = chain.request().url.newBuilder()
                    .encodedPath("/api/v1/auth/logout")
                    .query(null)
                    .build()

                val logoutRequest = Request.Builder()
                    .url(logoutUrl)
                    .post("{}".toRequestBody("application/json; charset=utf-8".toMediaType()))
                    .header(HEADER_AUTHORIZATION, "$BEARER_PREFIX$currentToken")
                    .header("Content-Type", "application/json")
                    .build()

                // Bare client — no interceptors, no retries — just the raw call.
                // hostnameVerifier mirrors the self-signed-cert policy the app already uses.
                val bareClient = okhttp3.OkHttpClient.Builder()
                    .callTimeout(LOGOUT_TIMEOUT_MS, TimeUnit.MILLISECONDS)
                    .hostnameVerifier { _, _ -> true }
                    .build()

                val resp = bareClient.newCall(logoutRequest).execute()
                if (BuildConfig.DEBUG) {
                    Log.d(TAG, "Server-side logout HTTP ${resp.code}")
                }
                resp.close()
            } catch (e: Exception) {
                Log.w(TAG, "Best-effort /auth/logout failed (${e.javaClass.simpleName}); proceeding with local wipe")
            }
        }
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
