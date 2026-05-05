package com.bizarreelectronics.crm.data.remote.interceptors

import okhttp3.Interceptor
import okhttp3.Response
import java.io.IOException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.min
import kotlin.random.Random

/**
 * OkHttp interceptor that retries transient failures with exponential backoff + jitter
 * (ActionPlan §1, L165).
 *
 * ## Retry policy
 * - Max 3 total attempts (1 initial + 2 retries).
 * - Delay = min(base * 2^n + random(0..250ms), 5000ms) where base = 500ms.
 * - Retries: 5xx server errors, SocketTimeoutException, UnknownHostException.
 * - Special handling for 429: respects `Retry-After` header (seconds, parsed as Long).
 * - Retries 408 (Request Timeout) and 425 (Too Early) in addition to 5xx.
 * - Does NOT retry other 4xx (client errors are not transient).
 * - Does NOT retry POST/PUT/PATCH/DELETE unless the request carries an
 *   `X-Idempotency-Key` header — body-mutating calls must opt in to retry.
 *
 * ## Placement in the interceptor chain
 * Add AFTER [RateLimitInterceptor] so rate-limit backoff runs before retry backoff.
 * The retry loop re-calls [chain.proceed] on the same request, which re-enters
 * all inner interceptors — that is correct and expected OkHttp behaviour.
 */
@Singleton
class RetryInterceptor @Inject constructor() : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()

        var lastResponse: Response? = null
        var lastException: IOException? = null

        for (attempt in 0 until MAX_ATTEMPTS) {
            if (attempt > 0) {
                // Close the previous unsuccessful response before sleeping to
                // release the connection back to the pool.
                lastResponse?.close()

                val delayMs = computeDelay(attempt - 1, lastResponse)
                Thread.sleep(delayMs)
            }

            try {
                val response = chain.proceed(request)

                if (!shouldRetry(request, response)) {
                    return response
                }

                // Retryable status — keep looping unless this was the last attempt.
                lastResponse = response
            } catch (e: SocketTimeoutException) {
                lastException = e
                if (!isIdempotent(request)) throw e
            } catch (e: UnknownHostException) {
                lastException = e
                if (!isIdempotent(request)) throw e
            }
        }

        // All attempts exhausted.
        lastResponse?.let { return it }
        throw lastException ?: IOException("RetryInterceptor: all $MAX_ATTEMPTS attempts failed")
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    /**
     * Returns true if the response warrants a retry and the request is eligible
     * (idempotent or safe method).
     */
    private fun shouldRetry(request: okhttp3.Request, response: Response): Boolean {
        val code = response.code
        if (!isRetryableCode(code)) return false
        return isIdempotent(request)
    }

    /**
     * A request is retry-eligible when:
     * - It uses a safe HTTP method (GET, HEAD, OPTIONS, TRACE), OR
     * - It carries an `X-Idempotency-Key` header that makes the mutation safe to replay.
     */
    private fun isIdempotent(request: okhttp3.Request): Boolean {
        val method = request.method.uppercase()
        if (method in SAFE_METHODS) return true
        return request.header(HEADER_IDEMPOTENCY_KEY) != null
    }

    /**
     * HTTP status codes that are eligible for retry:
     * - 408 Request Timeout
     * - 425 Too Early
     * - 429 Too Many Requests (with Retry-After support)
     * - 5xx Server Error (all of them)
     *
     * All other 4xx codes are client errors that will not resolve on retry.
     */
    private fun isRetryableCode(code: Int): Boolean = when {
        code == 408 -> true
        code == 425 -> true
        code == 429 -> true
        code in 500..599 -> true
        else -> false
    }

    /**
     * Computes the sleep duration (ms) before attempt [n+1]:
     *
     *   delay = min(BASE_DELAY_MS * 2^n + jitter(0..JITTER_MAX_MS), MAX_DELAY_MS)
     *
     * If the response carries a `Retry-After` header (only on 429), that value
     * (in seconds) overrides the exponential calculation when it is larger.
     */
    private fun computeDelay(n: Int, response: Response?): Long {
        val jitter = Random.nextLong(0L, JITTER_MAX_MS + 1)
        val exponential = BASE_DELAY_MS * (1L shl n) + jitter
        val backoff = min(exponential, MAX_DELAY_MS)

        // Honour Retry-After on 429.
        if (response?.code == 429) {
            val retryAfterSecs = response.header(HEADER_RETRY_AFTER)?.toLongOrNull()
            if (retryAfterSecs != null) {
                val retryAfterMs = retryAfterSecs * 1_000L
                return min(max(backoff, retryAfterMs), MAX_DELAY_MS)
            }
        }

        return backoff
    }

    companion object {
        /** Total number of attempts (1 original + 2 retries). */
        internal const val MAX_ATTEMPTS = 3

        /** Base delay for the exponential calculation (ms). */
        internal const val BASE_DELAY_MS = 500L

        /** Maximum jitter added per attempt (ms). */
        internal const val JITTER_MAX_MS = 250L

        /** Hard cap on any single delay (ms). */
        internal const val MAX_DELAY_MS = 5_000L

        /** Request header that opts a non-idempotent call into retry eligibility. */
        internal const val HEADER_IDEMPOTENCY_KEY = "X-Idempotency-Key"

        private const val HEADER_RETRY_AFTER = "Retry-After"

        /** HTTP methods that are safe to retry without an idempotency key. */
        private val SAFE_METHODS = setOf("GET", "HEAD", "OPTIONS", "TRACE")
    }
}

/** Alias for [kotlin.math.max] kept local to avoid import ambiguity with Long overloads. */
private fun max(a: Long, b: Long): Long = if (a >= b) a else b
