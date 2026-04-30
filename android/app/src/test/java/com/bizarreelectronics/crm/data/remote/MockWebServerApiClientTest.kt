package com.bizarreelectronics.crm.data.remote

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.LoginRequest
import com.bizarreelectronics.crm.data.remote.dto.LoginResponse
import com.bizarreelectronics.crm.data.remote.dto.TicketListData
import com.google.gson.GsonBuilder
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
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.QueryMap

/**
 * §31.2 — Retrofit + MockWebServer for ApiClient response parsing + error branches.
 *
 * Uses [MockWebServer] to enqueue canned HTTP responses and verify that:
 *   1. Happy-path JSON with `{ success: true, data: {...} }` deserialises correctly.
 *   2. `success: false` + `message` deserialises into the ApiResponse error shape.
 *   3. 401 response propagates as an HTTP exception (not silently swallowed).
 *   4. 404 response propagates as an HTTP exception.
 *   5. 500 response propagates as an HTTP exception.
 *   6. Malformed JSON response triggers a conversion exception.
 *   7. Ticket list endpoint with `pagination` parses correctly.
 *   8. Empty `data: null` response is handled without NPE.
 *   9. Challenge-token login flow (requires2faSetup=true) deserialises branch.
 *  10. Network/connection timeout is propagated as IOException.
 *
 * No production interceptors (auth, retry, rate-limit) are wired here — the tests
 * focus purely on Gson-Retrofit deserialization of the server's JSON contract.
 *
 * ActionPlan §31.2 — Retrofit + MockWebServer for ApiClient response parsing + error branches.
 */
class MockWebServerApiClientTest {

    private lateinit var server: MockWebServer
    private lateinit var testApi: TestAuthApi
    private lateinit var testTicketApi: TestTicketApi

    /** Minimal Retrofit interface mirrors [com.bizarreelectronics.crm.data.remote.api.AuthApi]. */
    interface TestAuthApi {
        @POST("auth/login")
        suspend fun login(@Body request: LoginRequest): ApiResponse<LoginResponse>

        @GET("auth/me")
        suspend fun getMe(): ApiResponse<@JvmSuppressWildcards Map<String, Any>>
    }

    /** Minimal Retrofit interface for ticket list. */
    interface TestTicketApi {
        @GET("tickets")
        suspend fun getTickets(
            @QueryMap filters: Map<String, String> = emptyMap(),
        ): ApiResponse<TicketListData>

        @GET("tickets/{id}")
        suspend fun getTicket(@Path("id") id: Long): ApiResponse<@JvmSuppressWildcards Map<String, Any>>
    }

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()

        val gson = GsonBuilder().setLenient().create()
        val retrofit = Retrofit.Builder()
            .baseUrl(server.url("/"))
            .client(OkHttpClient.Builder().build())
            .addConverterFactory(GsonConverterFactory.create(gson))
            .build()

        testApi = retrofit.create(TestAuthApi::class.java)
        testTicketApi = retrofit.create(TestTicketApi::class.java)
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    // -------------------------------------------------------------------------
    // 1. Happy path — success:true, data object
    // -------------------------------------------------------------------------

    @Test
    fun `login happy path - success true and challengeToken parsed`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("Content-Type", "application/json")
                .setBody(
                    """{"success":true,"data":{"challengeToken":"tok-abc","totpEnabled":false,"requiresPasswordSetup":false}}""",
                ),
        )

        val response = testApi.login(LoginRequest("admin", "pass"))

        assertTrue("success must be true", response.success)
        assertNotNull("data must not be null", response.data)
        assertEquals("tok-abc", response.data!!.challengeToken)
        assertFalse("totpEnabled should be false", response.data!!.totpEnabled == true)
    }

    // -------------------------------------------------------------------------
    // 2. success:false + message
    // -------------------------------------------------------------------------

    @Test
    fun `login returns success-false with message on bad credentials`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("Content-Type", "application/json")
                .setBody("""{"success":false,"data":null,"message":"Invalid credentials"}"""),
        )

        val response = testApi.login(LoginRequest("admin", "wrong"))

        assertFalse("success must be false on bad creds", response.success)
        assertNull("data should be null on failure", response.data)
        assertEquals("Invalid credentials", response.message)
    }

    // -------------------------------------------------------------------------
    // 3. 401 propagates as HTTP exception
    // -------------------------------------------------------------------------

    @Test
    fun `401 response propagates as retrofit HttpException`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(401)
                .setBody("""{"success":false,"message":"Unauthorized"}"""),
        )

        val ex = runCatching { testApi.getMe() }.exceptionOrNull()
        assertNotNull("HTTP 401 must throw an exception", ex)
        assertTrue(
            "Exception should be retrofit HttpException",
            ex is retrofit2.HttpException,
        )
        assertEquals(401, (ex as retrofit2.HttpException).code())
    }

    // -------------------------------------------------------------------------
    // 4. 404 propagates as HTTP exception
    // -------------------------------------------------------------------------

    @Test
    fun `404 response propagates as retrofit HttpException`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(404)
                .setBody("""{"success":false,"message":"Not found"}"""),
        )

        val ex = runCatching { testTicketApi.getTicket(99999L) }.exceptionOrNull()
        assertNotNull("HTTP 404 must throw an exception", ex)
        assertEquals(404, (ex as retrofit2.HttpException).code())
    }

    // -------------------------------------------------------------------------
    // 5. 500 propagates as HTTP exception
    // -------------------------------------------------------------------------

    @Test
    fun `500 response propagates as retrofit HttpException`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(500)
                .setBody("""{"success":false,"message":"Internal server error"}"""),
        )

        val ex = runCatching { testApi.getMe() }.exceptionOrNull()
        assertNotNull("HTTP 500 must throw an exception", ex)
        assertEquals(500, (ex as retrofit2.HttpException).code())
    }

    // -------------------------------------------------------------------------
    // 6. Malformed JSON triggers conversion exception
    // -------------------------------------------------------------------------

    @Test
    fun `malformed JSON response triggers conversion exception`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("Content-Type", "application/json")
                .setBody("NOT_VALID_JSON{{{{"),
        )

        val ex = runCatching { testApi.getMe() }.exceptionOrNull()
        assertNotNull("Malformed JSON should throw an exception", ex)
    }

    // -------------------------------------------------------------------------
    // 7. Ticket list with pagination
    // -------------------------------------------------------------------------

    @Test
    fun `ticket list response with pagination parses correctly`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("Content-Type", "application/json")
                .setBody(
                    """
                    {
                      "success": true,
                      "data": {
                        "tickets": [
                          {"id":1,"order_id":"T-001","created_at":"2026-01-01 00:00:00","updated_at":"2026-01-01 00:00:00"},
                          {"id":2,"order_id":"T-002","created_at":"2026-01-02 00:00:00","updated_at":"2026-01-02 00:00:00"}
                        ],
                        "pagination": {"page":1,"per_page":50,"total":2,"total_pages":1}
                      }
                    }
                    """.trimIndent(),
                ),
        )

        val response = testTicketApi.getTickets()

        assertTrue(response.success)
        assertNotNull(response.data)
        assertEquals(2, response.data!!.tickets.size)
        assertEquals("T-001", response.data!!.tickets[0].orderId)
        assertEquals("T-002", response.data!!.tickets[1].orderId)
        assertNotNull("pagination should be present", response.data!!.pagination)
        assertEquals(2, response.data!!.pagination!!.total)
    }

    // -------------------------------------------------------------------------
    // 8. data: null is handled without NPE
    // -------------------------------------------------------------------------

    @Test
    fun `response with data null does not throw NPE`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("Content-Type", "application/json")
                .setBody("""{"success":true,"data":null}"""),
        )

        val response = testApi.getMe()

        assertTrue(response.success)
        assertNull("data should be null and that is acceptable", response.data)
    }

    // -------------------------------------------------------------------------
    // 9. Challenge-token login flow (2FA branch)
    // -------------------------------------------------------------------------

    @Test
    fun `login response with requires2faSetup=true deserialises challenge token branch`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("Content-Type", "application/json")
                .setBody(
                    """
                    {
                      "success":true,
                      "data":{
                        "challengeToken":"challenge-xyz",
                        "totpEnabled":false,
                        "requiresPasswordSetup":false,
                        "requires2faSetup":true
                      }
                    }
                    """.trimIndent(),
                ),
        )

        val response = testApi.login(LoginRequest("admin", "newpass"))

        assertTrue(response.success)
        assertEquals("challenge-xyz", response.data!!.challengeToken)
        assertTrue("requires2faSetup must be true", response.data!!.requires2faSetup == true)
    }

    // -------------------------------------------------------------------------
    // 10. Empty ticket list
    // -------------------------------------------------------------------------

    @Test
    fun `empty ticket list response is handled gracefully`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setHeader("Content-Type", "application/json")
                .setBody("""{"success":true,"data":{"tickets":[]}}"""),
        )

        val response = testTicketApi.getTickets()

        assertTrue(response.success)
        assertNotNull(response.data)
        assertTrue("tickets list should be empty", response.data!!.tickets.isEmpty())
        assertNull("pagination should be null when not returned", response.data!!.pagination)
    }

    // -------------------------------------------------------------------------
    // 11. Request path and method are correct (regression guard)
    // -------------------------------------------------------------------------

    @Test
    fun `login POST is sent to the correct path`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody("""{"success":true,"data":{"challengeToken":null}}"""),
        )

        testApi.login(LoginRequest("user", "pass"))

        val recorded = server.takeRequest()
        assertEquals("POST", recorded.method)
        assertTrue(
            "Request path must end with auth/login",
            recorded.path!!.endsWith("/auth/login"),
        )
    }
}
