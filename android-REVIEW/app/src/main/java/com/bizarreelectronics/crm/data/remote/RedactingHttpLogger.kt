package com.bizarreelectronics.crm.data.remote

import android.util.Log
import okhttp3.logging.HttpLoggingInterceptor
import javax.inject.Inject
import javax.inject.Singleton

/**
 * §28.6 / §32.4 — `HttpLoggingInterceptor.Logger` that scrubs sensitive
 * fields out of request + response bodies before they hit Logcat.
 *
 * Headers are already redacted by `redactHeader(...)` calls in
 * `RetrofitClient.provideLoggingInterceptor`. This logger sits as the sink
 * for body-level lines so JSON payloads with `password`, `pin`,
 * `accessToken`, `refreshToken`, `challengeToken`, `backupCode`,
 * `currentPin`, `newPin`, `secret`, `setupToken` get masked as `"***"`
 * instead of leaking in plaintext.
 *
 * Wire this in by passing an instance to `HttpLoggingInterceptor(logger)`
 * in `RetrofitClient.provideLoggingInterceptor`.
 *
 * Strategy:
 *   - Logger only sees String lines after OkHttp has already chunked
 *     the body. We do one regex pass per known sensitive key.
 *   - Order-independent + works on nested JSON.
 *   - False-positive risk is acceptable — anything matching `"password"`
 *     is almost certainly a credential.
 *   - We never delete lines, only mask values, so the structure of the
 *     log stays intact for diagnostics.
 */
@Singleton
class RedactingHttpLogger @Inject constructor() : HttpLoggingInterceptor.Logger {

    override fun log(message: String) {
        val safe = redact(message)
        Log.d(TAG, safe)
    }

    private fun redact(raw: String): String {
        if (raw.isEmpty()) return raw
        var out = raw
        for (key in SENSITIVE_KEYS) {
            val pattern = Regex("(\"$key\"\\s*:\\s*)\"[^\"]*\"", RegexOption.IGNORE_CASE)
            out = pattern.replace(out) { "${it.groupValues[1]}\"$REDACTED\"" }
        }
        // Also catch form-urlencoded payloads (login flow) — pattern
        // `password=foo` or `pin=1234`.
        for (key in SENSITIVE_KEYS) {
            val pattern = Regex("(?<=[?&]|^)$key=([^&\\s]+)", RegexOption.IGNORE_CASE)
            out = pattern.replace(out) { "$key=$REDACTED" }
        }
        return out
    }

    private companion object {
        private const val TAG = "OkHttpClient"
        private const val REDACTED = "***"

        private val SENSITIVE_KEYS = listOf(
            "password",
            "currentPassword",
            "newPassword",
            "pin",
            "currentPin",
            "newPin",
            "accessToken",
            "refreshToken",
            "challengeToken",
            "recoveryToken",
            "backupCode",
            "secret",
            "manualEntry",
            "setup_token",
            "setupToken",
        )
    }
}
