package com.bizarreelectronics.crm.data.remote.interceptors

import com.bizarreelectronics.crm.util.RateLimiterCore
import com.bizarreelectronics.crm.util.RateLimiter
import kotlinx.coroutines.runBlocking
import okhttp3.Interceptor
import okhttp3.Response
import javax.inject.Inject
import javax.inject.Singleton

/**
 * OkHttp interceptor that enforces client-side token-bucket rate limiting
 * before forwarding requests to the server (ActionPlan §1, L255-L259).
 *
 * ## Placement in the interceptor chain
 * This interceptor runs BEFORE [ClockDriftInterceptor]: rate limiting decides
 * whether the call proceeds at all, so it is the outermost application-level
 * interceptor in [com.bizarreelectronics.crm.data.remote.RetrofitClient].
 *
 * ## Category derivation
 * The HTTP method determines the bucket:
 *   - GET, HEAD → [RateLimiterCore.Category.READ]
 *   - POST, PUT, PATCH, DELETE, and anything else → [RateLimiterCore.Category.WRITE]
 *
 * ## Exemptions (L259)
 * Auth endpoints and sync-queue flush calls bypass throttling — [RateLimiterCore.isExempt]
 * encapsulates the exemption logic.
 *
 * ## Server hints (L256)
 * After every response the interceptor checks:
 *   - HTTP 429 status code
 *   - `Retry-After` response header (seconds)
 *   - `X-RateLimit-Remaining` response header
 * Any present hint is forwarded to [RateLimiter.recordServerHint].
 *
 * ## Blocking vs. suspending
 * OkHttp dispatches calls on its own thread pool, which does not understand
 * Kotlin coroutines. [runBlocking] bridges the gap. When a token is immediately
 * available, [RateLimiter.acquire] returns without any actual suspension, so
 * the [runBlocking] overhead is negligible for the common case.
 */
@Singleton
class RateLimitInterceptor @Inject constructor(
    private val rateLimiter: RateLimiter,
) : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val method  = request.method
        val path    = request.url.encodedPath
        val tag     = request.tag(String::class.java)

        // Exempt paths bypass client-side throttling entirely (L259).
        if (rateLimiter.isExempt(method, path, tag)) {
            return chain.proceed(request)
        }

        val category = categoryFor(method)

        // Bridge coroutine suspension to the OkHttp blocking thread.
        // acquire() returns immediately when a token is available; it only
        // suspends (and therefore blocks here) when the bucket is empty.
        runBlocking { rateLimiter.acquire(category) }

        val response = chain.proceed(request)

        // Forward server hints so the client backs off proactively (L256).
        recordHintsFromResponse(response, category)

        return response
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    private fun categoryFor(method: String): RateLimiterCore.Category = when (method.uppercase()) {
        "GET", "HEAD" -> RateLimiterCore.Category.READ
        else          -> RateLimiterCore.Category.WRITE
    }

    private fun recordHintsFromResponse(response: Response, category: RateLimiterCore.Category) {
        val is429          = response.code == HTTP_TOO_MANY_REQUESTS
        val retryAfter     = response.header(HEADER_RETRY_AFTER)?.toLongOrNull()
        val remaining      = response.header(HEADER_RATE_LIMIT_REMAINING)?.toIntOrNull()

        val effectiveRetry = when {
            is429 && retryAfter == null -> DEFAULT_429_RETRY_SECONDS
            else                        -> retryAfter
        }

        if (effectiveRetry != null || remaining != null) {
            rateLimiter.recordServerHint(
                retryAfterSeconds = effectiveRetry,
                remaining         = remaining,
                category          = category,
            )
        }
    }

    companion object {
        private const val HTTP_TOO_MANY_REQUESTS      = 429
        private const val HEADER_RETRY_AFTER          = "Retry-After"
        private const val HEADER_RATE_LIMIT_REMAINING = "X-RateLimit-Remaining"

        /**
         * When a 429 arrives without a Retry-After header, pause for this many
         * seconds before retrying. Conservative enough not to hammer the server,
         * short enough not to stall the user indefinitely.
         */
        private const val DEFAULT_429_RETRY_SECONDS = 10L
    }
}
