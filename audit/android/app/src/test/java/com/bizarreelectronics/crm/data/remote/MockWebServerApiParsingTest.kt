package com.bizarreelectronics.crm.data.remote

import com.bizarreelectronics.crm.data.remote.api.AuthApi
import com.bizarreelectronics.crm.data.remote.api.CustomerApi
import com.bizarreelectronics.crm.data.remote.api.TicketApi
import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.CustomerListData
import com.bizarreelectronics.crm.data.remote.dto.LoginRequest
import com.bizarreelectronics.crm.data.remote.dto.LoginResponse
import com.bizarreelectronics.crm.data.remote.dto.TicketListData
import com.google.gson.Gson
import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import retrofit2.HttpException
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory

/**
 * JVM integration tests for Retrofit + MockWebServer (ActionPlan §31.2).
 *
 * Validates that every [ApiResponse] shape the server emits is parsed correctly
 * by the Retrofit + Gson stack — no real network, no Android device required.
 *
 * API envelope: `{ success: true|false, data: <payload>|null, message: <string?> }`.
 *
 * Test cases:
 *   1. Auth login — success=true, data=LoginResponse (challengeToken) parsed.
 *   2. Auth login — success=false, data=null, message returned.
 *   3. 401 Unauthorized — HttpException wraps the error code.
 *   4. 500 Server error — HttpException wraps the error code.
 *   5. Ticket list — success=true, data.tickets array parsed with count.
 *   6. Customer list — success=true, data.customers array parsed.
 *   7. Empty ticket list — data.tickets is empty, pagination absent.
 *   8. Network failure (server shut down) — exception propagates correctly.
 *   9. Malformed JSON body — retrofit throws a parse exception.
 *  10. Null data field — data=null is null in Kotlin.
 *  11. Request path — login sends to correct endpoint.
 */
class MockWebServerApiParsingTest {

    private lateinit var server: MockWebServer
    private lateinit var retrofit: Retrofit
    private val gson = Gson()

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()

        val okHttpClient = OkHttpClient.Builder().build()

        retrofit = Retrofit.Builder()
            .baseUrl(server.url("/api/v1/"))
            .client(okHttpClient)
            .addConverterFactory(GsonConverterFactory.create(gson))
            .build()
    }

    @After
    fun tearDown() {
        // Gracefully shut down — tolerate the case where test 8 already shut it down.
        try { server.shutdown() } catch (_: Exception) {}
    }

    // ── 1. Auth login success — challengeToken returned ──────────────────────

    @Test
    fun `auth login — success response parses challengeToken`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("Content-Type", "application/json")
                .setBody(
                    """{"success":true,"data":{"challengeToken":"ct-abc-123","totpEnabled":true,"requiresPasswordSetup":false}}"""
                ),
        )

        val api = retrofit.create(AuthApi::class.java)
        val response: ApiResponse<LoginResponse> = api.login(LoginRequest(username = "admin", password = "admin123"))

        assertTrue(response.success)
        assertNotNull(response.data)
        assertEquals("ct-abc-123", response.data?.challengeToken)
        assertEquals(true, response.data?.totpEnabled)
        assertNull(response.message)
    }

    // ── 2. Auth login failure — success=false, message present ───────────────

    @Test
    fun `auth login — success=false with message field`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("Content-Type", "application/json")
                .setBody("""{"success":false,"data":null,"message":"Invalid credentials"}"""),
        )

        val api = retrofit.create(AuthApi::class.java)
        val response = api.login(LoginRequest(username = "admin", password = "wrong"))

        assertFalse(response.success)
        assertNull(response.data)
        assertEquals("Invalid credentials", response.message)
    }

    // ── 3. 401 Unauthorized — HTTP error propagates as HttpException ──────────

    @Test
    fun `401 response — throws HttpException with code 401`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(401)
                .setHeader("Content-Type", "application/json")
                .setBody("""{"success":false,"message":"Unauthorized"}"""),
        )

        val api = retrofit.create(AuthApi::class.java)
        var caught: HttpException? = null
        try {
            api.login(LoginRequest(username = "x", password = "y"))
        } catch (e: HttpException) {
            caught = e
        }

        assertNotNull("Expected HttpException for 401", caught)
        assertEquals(401, caught?.code())
    }

    // ── 4. 500 Server error ───────────────────────────────────────────────────

    @Test
    fun `500 server error — throws HttpException with code 500`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(500)
                .setHeader("Content-Type", "application/json")
                .setBody("""{"success":false,"message":"Internal Server Error"}"""),
        )

        val api = retrofit.create(AuthApi::class.java)
        var caught: HttpException? = null
        try {
            api.login(LoginRequest(username = "x", password = "y"))
        } catch (e: HttpException) {
            caught = e
        }

        assertNotNull("Expected HttpException for 500", caught)
        assertEquals(500, caught?.code())
    }

    // ── 5. Ticket list — items array parsed correctly ─────────────────────────

    @Test
    fun `ticket list — parses tickets array with correct count`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("Content-Type", "application/json")
                .setBody(
                    """{"success":true,"data":{"tickets":[
                        {"id":1,"order_id":"T-001","created_at":"2026-01-01 00:00:00","updated_at":"2026-01-01 00:00:00"},
                        {"id":2,"order_id":"T-002","created_at":"2026-01-02 00:00:00","updated_at":"2026-01-02 00:00:00"}
                    ]}}"""
                ),
        )

        val api = retrofit.create(TicketApi::class.java)
        val response: ApiResponse<TicketListData> = api.getTickets(emptyMap())

        assertTrue(response.success)
        val data = response.data
        assertNotNull(data)
        assertEquals(2, data?.tickets?.size)
        assertEquals(1L, data?.tickets?.get(0)?.id)
        assertEquals("T-002", data?.tickets?.get(1)?.orderId)
    }

    // ── 6. Customer list — customers array parsed ─────────────────────────────

    @Test
    fun `customer list — parses customers array`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("Content-Type", "application/json")
                .setBody(
                    """{"success":true,"data":{"customers":[
                        {"id":10,"first_name":"Alice","last_name":"Nguyen"},
                        {"id":11,"first_name":"Bob","last_name":"Smith"}
                    ]}}"""
                ),
        )

        val api = retrofit.create(CustomerApi::class.java)
        val response: ApiResponse<CustomerListData> = api.getCustomers(emptyMap())

        assertTrue(response.success)
        val data: CustomerListData? = response.data
        assertNotNull(data)
        assertEquals(2, data?.customers?.size)
        assertEquals("Alice", data?.customers?.get(0)?.firstName)
        assertEquals("Smith", data?.customers?.get(1)?.lastName)
    }

    // ── 7. Empty ticket list ──────────────────────────────────────────────────

    @Test
    fun `ticket list — empty tickets array parsed as empty list`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("Content-Type", "application/json")
                .setBody("""{"success":true,"data":{"tickets":[]}}"""),
        )

        val api = retrofit.create(TicketApi::class.java)
        val response: ApiResponse<TicketListData> = api.getTickets(emptyMap())

        assertTrue(response.success)
        val data: TicketListData? = response.data
        assertNotNull(data)
        assertTrue("tickets should be empty", data?.tickets?.isEmpty() == true)
        assertNull("pagination should be absent", data?.pagination)
    }

    // ── 8. Network failure after shutdown ─────────────────────────────────────

    @Test
    fun `network failure — exception propagates when server is down`() = runTest {
        // Shut down the server immediately so the next request has no target.
        server.shutdown()

        val api = retrofit.create(AuthApi::class.java)
        var exceptionThrown = false
        try {
            api.login(LoginRequest(username = "x", password = "y"))
        } catch (e: Exception) {
            exceptionThrown = true
        }

        assertTrue("Should throw when server is unreachable", exceptionThrown)
    }

    // ── 9. Malformed JSON — parse exception ───────────────────────────────────

    @Test
    fun `malformed JSON body — throws on deserialization`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("Content-Type", "application/json")
                .setBody("NOT_JSON{{{"),
        )

        val api = retrofit.create(AuthApi::class.java)
        var exceptionThrown = false
        try {
            api.login(LoginRequest(username = "x", password = "y"))
        } catch (e: Exception) {
            exceptionThrown = true
        }

        assertTrue("Malformed JSON must throw", exceptionThrown)
    }

    // ── 10. Null data field ───────────────────────────────────────────────────

    @Test
    fun `null data field — data is null in ApiResponse`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("Content-Type", "application/json")
                .setBody("""{"success":false,"data":null,"message":"Account locked"}"""),
        )

        val api = retrofit.create(AuthApi::class.java)
        val response: ApiResponse<LoginResponse> =
            api.login(LoginRequest(username = "locked", password = "any"))

        assertFalse(response.success)
        assertNull(response.data)
        assertEquals("Account locked", response.message)
    }

    // ── 11. Request path verification ────────────────────────────────────────

    @Test
    fun `request path — login sends POST to auth-login endpoint`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("Content-Type", "application/json")
                .setBody("""{"success":true,"data":{"challengeToken":"ct-xyz","totpEnabled":true}}"""),
        )

        val api = retrofit.create(AuthApi::class.java)
        api.login(LoginRequest(username = "u", password = "p"))

        val request = server.takeRequest()
        assertEquals("/api/v1/auth/login", request.path)
        assertEquals("POST", request.method)
        assertTrue(
            "Content-Type should be application/json",
            request.getHeader("Content-Type")?.contains("application/json") == true,
        )
    }
}
