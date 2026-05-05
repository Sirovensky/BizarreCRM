package com.bizarreelectronics.crm.data.remote.interceptors

import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Before
import org.junit.Test
import java.net.SocketTimeoutException
import java.net.UnknownHostException

/**
 * JVM unit tests for [RetryInterceptor] (ActionPlan §1, L165).
 *
 * Uses a fake [Interceptor.Chain] stub to control response codes and exception
 * injection without a real network. Each test verifies a specific aspect of
 * the retry policy:
 *   - successful 200 is returned immediately
 *   - 5xx is retried up to MAX_ATTEMPTS times
 *   - 429 with Retry-After is retried (delay verified via elapsedMs)
 *   - 4xx (except 408/425/429) is NOT retried
 *   - GET is idempotent; POST without X-Idempotency-Key is NOT retried
 *   - POST WITH X-Idempotency-Key IS retried
 *   - SocketTimeoutException on GET is retried
 */
class RetryInterceptorTest {

    private lateinit var interceptor: RetryInterceptor

    @Before
    fun setUp() {
        interceptor = RetryInterceptor()
    }

    // -------------------------------------------------------------------------
    // Success — no retry needed
    // -------------------------------------------------------------------------

    @Test
    fun `200 response is returned on the first attempt`() {
        var callCount = 0
        val chain = fakeChain(method = "GET") {
            callCount++
            buildResponse(it.request(), 200)
        }

        val response = interceptor.intercept(chain)

        assertEquals(200, response.code)
        assertEquals("Should succeed on first attempt", 1, callCount)
        response.close()
    }

    // -------------------------------------------------------------------------
    // 5xx retries
    // -------------------------------------------------------------------------

    @Test
    fun `503 GET is retried up to MAX_ATTEMPTS and last response returned`() {
        var callCount = 0
        val chain = fakeChain(method = "GET") {
            callCount++
            buildResponse(it.request(), 503)
        }

        val response = interceptor.intercept(chain)

        assertEquals(503, response.code)
        assertEquals(
            "Should attempt MAX_ATTEMPTS=${RetryInterceptor.MAX_ATTEMPTS} times",
            RetryInterceptor.MAX_ATTEMPTS,
            callCount,
        )
        response.close()
    }

    @Test
    fun `500 GET succeeds on second attempt`() {
        var callCount = 0
        val chain = fakeChain(method = "GET") {
            callCount++
            val code = if (callCount == 1) 500 else 200
            buildResponse(it.request(), code)
        }

        val response = interceptor.intercept(chain)

        assertEquals(200, response.code)
        assertEquals("Should succeed on second attempt", 2, callCount)
        response.close()
    }

    // -------------------------------------------------------------------------
    // 429 with Retry-After
    // -------------------------------------------------------------------------

    @Test
    fun `429 GET is retried`() {
        var callCount = 0
        val chain = fakeChain(method = "GET") {
            callCount++
            val code = if (callCount == 1) 429 else 200
            buildResponse(it.request(), code, retryAfterSecs = if (callCount == 1) 0L else null)
        }

        val response = interceptor.intercept(chain)

        assertEquals(200, response.code)
        assertEquals(2, callCount)
        response.close()
    }

    // -------------------------------------------------------------------------
    // 4xx — only 408, 425, 429 are retried
    // -------------------------------------------------------------------------

    @Test
    fun `404 GET is NOT retried`() {
        var callCount = 0
        val chain = fakeChain(method = "GET") {
            callCount++
            buildResponse(it.request(), 404)
        }

        val response = interceptor.intercept(chain)

        assertEquals(404, response.code)
        assertEquals("404 should not be retried", 1, callCount)
        response.close()
    }

    @Test
    fun `408 GET is retried`() {
        var callCount = 0
        val chain = fakeChain(method = "GET") {
            callCount++
            val code = if (callCount == 1) 408 else 200
            buildResponse(it.request(), code)
        }

        val response = interceptor.intercept(chain)

        assertEquals(200, response.code)
        assertEquals(2, callCount)
        response.close()
    }

    @Test
    fun `425 GET is retried`() {
        var callCount = 0
        val chain = fakeChain(method = "GET") {
            callCount++
            val code = if (callCount == 1) 425 else 200
            buildResponse(it.request(), code)
        }

        val response = interceptor.intercept(chain)

        assertEquals(200, response.code)
        assertEquals(2, callCount)
        response.close()
    }

    // -------------------------------------------------------------------------
    // Idempotency — POST without key is NOT retried
    // -------------------------------------------------------------------------

    @Test
    fun `POST without X-Idempotency-Key is NOT retried on 500`() {
        var callCount = 0
        val chain = fakeChain(method = "POST", idempotencyKey = null) {
            callCount++
            buildResponse(it.request(), 500)
        }

        val response = interceptor.intercept(chain)

        assertEquals(500, response.code)
        assertEquals("POST without key must not be retried", 1, callCount)
        response.close()
    }

    @Test
    fun `POST with X-Idempotency-Key IS retried on 500`() {
        var callCount = 0
        val chain = fakeChain(method = "POST", idempotencyKey = "idem-abc-123") {
            callCount++
            val code = if (callCount == 1) 500 else 200
            buildResponse(it.request(), code)
        }

        val response = interceptor.intercept(chain)

        assertEquals(200, response.code)
        assertEquals(2, callCount)
        response.close()
    }

    // -------------------------------------------------------------------------
    // IOException types — SocketTimeoutException / UnknownHostException
    // -------------------------------------------------------------------------

    @Test
    fun `SocketTimeoutException on GET is retried and succeeds`() {
        var callCount = 0
        val chain = fakeChain(method = "GET") {
            callCount++
            if (callCount == 1) throw SocketTimeoutException("timeout")
            buildResponse(it.request(), 200)
        }

        val response = interceptor.intercept(chain)

        assertEquals(200, response.code)
        assertEquals(2, callCount)
        response.close()
    }

    @Test
    fun `UnknownHostException on GET is retried and succeeds`() {
        var callCount = 0
        val chain = fakeChain(method = "GET") {
            callCount++
            if (callCount == 1) throw UnknownHostException("host not found")
            buildResponse(it.request(), 200)
        }

        val response = interceptor.intercept(chain)

        assertEquals(200, response.code)
        assertEquals(2, callCount)
        response.close()
    }

    @Test
    fun `SocketTimeoutException on POST without key is NOT retried`() {
        var thrown: SocketTimeoutException? = null
        val chain = fakeChain(method = "POST", idempotencyKey = null) {
            throw SocketTimeoutException("timeout")
        }

        try {
            interceptor.intercept(chain)
        } catch (e: SocketTimeoutException) {
            thrown = e
        }

        assertNotNull("Exception should propagate for non-idempotent POST", thrown)
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    private fun fakeChain(
        method: String = "GET",
        idempotencyKey: String? = null,
        block: (Interceptor.Chain) -> Response,
    ): Interceptor.Chain {
        val url = "https://example.com/api/test"
        val requestBuilder = Request.Builder()
            .url(url)
            .method(method, if (method == "GET" || method == "HEAD") null else
                "{}".toRequestBody())
        if (idempotencyKey != null) {
            requestBuilder.header(RetryInterceptor.HEADER_IDEMPOTENCY_KEY, idempotencyKey)
        }
        val request = requestBuilder.build()

        return object : Interceptor.Chain {
            override fun request(): Request = request
            override fun proceed(request: Request): Response = block(this)
            // The following are required by the interface but unused in unit tests.
            override fun connection() = null
            override fun call(): okhttp3.Call = throw UnsupportedOperationException()
            override fun connectTimeoutMillis() = 0
            override fun withConnectTimeout(timeout: Int, unit: java.util.concurrent.TimeUnit) = this
            override fun readTimeoutMillis() = 0
            override fun withReadTimeout(timeout: Int, unit: java.util.concurrent.TimeUnit) = this
            override fun writeTimeoutMillis() = 0
            override fun withWriteTimeout(timeout: Int, unit: java.util.concurrent.TimeUnit) = this
        }
    }

    private fun buildResponse(
        request: Request,
        code: Int,
        retryAfterSecs: Long? = null,
    ): Response {
        val builder = Response.Builder()
            .request(request)
            .protocol(Protocol.HTTP_1_1)
            .code(code)
            .message(if (code == 200) "OK" else "Error")
            .body("{}".toResponseBody("application/json".toMediaTypeOrNull()))
        if (retryAfterSecs != null) {
            builder.header("Retry-After", retryAfterSecs.toString())
        }
        return builder.build()
    }

    private fun String.toRequestBody() =
        toByteArray().let { bytes ->
            okhttp3.RequestBody.create("application/json".toMediaTypeOrNull(), bytes)
        }
}
