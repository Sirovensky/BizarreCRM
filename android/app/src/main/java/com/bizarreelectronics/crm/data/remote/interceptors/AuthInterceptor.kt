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
import java.net.Inet4Address
import java.net.InetAddress
import java.security.SecureRandom
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509TrustManager

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

                // AUDIT-AND-015: bare client with hostname-restricted TLS policy matching
                // RetrofitClient — trust-all only for LAN hosts in DEBUG; release and
                // public hostnames use platform CA + default hostname verifier so a MITM
                // cannot intercept and suppress the logout (keeping the server session alive).
                val logoutHost = logoutUrl.host
                val bareClient = buildLogoutClient(logoutHost)

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

    // AUDIT-AND-015: LAN-host predicate — mirrors RetrofitClient.isDebugTrustedHost.
    private val debugLoopbackHosts: Set<String> = setOf(
        "localhost", "10.0.2.2", "10.0.3.2", "127.0.0.1", "::1",
    )

    private fun isLanHost(hostname: String?): Boolean {
        if (hostname.isNullOrBlank()) return false
        val h = hostname.lowercase()
        if (h in debugLoopbackHosts) return true
        return try {
            val addr: InetAddress = InetAddress.getByName(h)
            if (addr !is Inet4Address) false
            else {
                val b = addr.address
                val b0 = b[0].toInt() and 0xff
                val b1 = b[1].toInt() and 0xff
                b0 == 10 || (b0 == 172 && b1 in 16..31) || (b0 == 192 && b1 == 168)
            }
        } catch (_: Exception) { false }
    }

    /**
     * Builds a bare OkHttpClient for the fire-and-forget /auth/logout call.
     * TLS policy: DEBUG + LAN host → accept self-signed cert (matching RetrofitClient).
     * Release OR public host → platform default CA + hostname verifier.
     * No interceptors, no retries — caller swallows all failures (best-effort semantics).
     */
    private fun buildLogoutClient(logoutHost: String): okhttp3.OkHttpClient {
        val builder = okhttp3.OkHttpClient.Builder()
            .callTimeout(LOGOUT_TIMEOUT_MS, TimeUnit.MILLISECONDS)

        if (BuildConfig.DEBUG && isLanHost(logoutHost)) {
            try {
                val tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
                tmf.init(null as java.security.KeyStore?)
                val platformTm = tmf.trustManagers.filterIsInstance<X509TrustManager>().first()

                val lanTrustAll = object : X509TrustManager {
                    override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) =
                        platformTm.checkClientTrusted(chain, authType)
                    override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {
                        try { platformTm.checkServerTrusted(chain, authType) }
                        catch (_: CertificateException) { /* accept self-signed on LAN */ }
                    }
                    override fun getAcceptedIssuers(): Array<X509Certificate> = platformTm.acceptedIssuers
                }
                val sslCtx = SSLContext.getInstance("TLS")
                sslCtx.init(null, arrayOf<TrustManager>(lanTrustAll), SecureRandom())
                builder.sslSocketFactory(sslCtx.socketFactory, lanTrustAll)
                builder.hostnameVerifier { hn, session ->
                    isLanHost(hn) || HttpsURLConnection.getDefaultHostnameVerifier().verify(hn, session)
                }
            } catch (e: Exception) {
                Log.w(TAG, "buildLogoutClient: failed to configure LAN TLS, using platform defaults: ${e.message}")
            }
        }
        // else: no custom TLS set → OkHttp uses platform defaults (correct for release / cloud)
        return builder.build()
    }

    private fun isAuthEndpoint(request: Request): Boolean {
        val path = request.url.encodedPath
        // AUDIT-AND-014: explicitly enumerate all public auth paths so that
        // /auth/login/2fa, /auth/forgot-password, and /auth/reset-password are
        // also exempt from the Bearer header. The previous logic attached Bearer
        // to the 2FA verify endpoint by mistake (the negative exclusion was
        // only for /auth/login/2fa, but the outer condition already matched it).
        return path.contains("/auth/login") ||
            path.contains("/auth/forgot-password") ||
            path.contains("/auth/reset-password")
    }

    private fun isRefreshEndpoint(request: Request): Boolean {
        return request.url.encodedPath.contains("/auth/refresh")
    }
}
