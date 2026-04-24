package com.bizarreelectronics.crm.ui.screens.settings

// §2.18 L417-L426 — JVM unit tests for TwoFactorFactorsViewModel.
//
// Three tests as specified in ActionPlan L426:
//   (a) refresh_success       — happy path emits Content with returned factors.
//   (b) refresh_404           — server 404 maps to NotSupported state.
//   (c) enroll_unsupported    — enrollFactor("unknown") emits Toast event.

import com.bizarreelectronics.crm.data.remote.api.AuthApi
import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.TwoFactorFactorDto
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import retrofit2.HttpException
import retrofit2.Response

@OptIn(ExperimentalCoroutinesApi::class)
class TwoFactorFactorsViewModelTest {

    private val testDispatcher = StandardTestDispatcher()

    @Before
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    // ── (a) refresh success — Content with factor list ────────────────────────

    @Test
    fun `refresh success - emits Content with returned factors`() = runTest {
        val expectedFactors = listOf(
            TwoFactorFactorDto(
                type = "totp",
                enrolledAt = "2026-04-01T12:00:00Z",
                label = "Google Authenticator",
                isPrimary = true,
            ),
            TwoFactorFactorDto(
                type = "sms",
                enrolledAt = "2026-04-10T09:00:00Z",
                label = "+15551234567",
                isPrimary = false,
            ),
        )

        val api = object : StubAuthApi() {
            override suspend fun listFactors() =
                ApiResponse(success = true, data = expectedFactors)
        }

        val vm = TwoFactorFactorsViewModel(api)
        advanceUntilIdle()

        val state = vm.uiState.value
        assertTrue("Expected Content state, got $state", state is TwoFactorFactorsUiState.Content)
        assertEquals(expectedFactors, (state as TwoFactorFactorsUiState.Content).factors)
    }

    // ── (b) server 404 → NotSupported ────────────────────────────────────────

    @Test
    fun `refresh 404 - maps to NotSupported state`() = runTest {
        val api = object : StubAuthApi() {
            override suspend fun listFactors(): ApiResponse<List<TwoFactorFactorDto>> {
                throw HttpException(
                    Response.error<ApiResponse<List<TwoFactorFactorDto>>>(
                        404,
                        okhttp3.ResponseBody.create(null, "Not Found"),
                    )
                )
            }
        }

        val vm = TwoFactorFactorsViewModel(api)
        advanceUntilIdle()

        assertEquals(TwoFactorFactorsUiState.NotSupported, vm.uiState.value)
    }

    // ── (c) enrollFactor("unknown") → Toast event ─────────────────────────────

    @Test
    fun `enrollFactor unknown type - emits Toast event`() = runTest {
        val api = object : StubAuthApi() {
            override suspend fun listFactors() =
                ApiResponse(success = true, data = emptyList<TwoFactorFactorDto>())
        }

        val vm = TwoFactorFactorsViewModel(api)
        advanceUntilIdle() // consume init refresh

        // Collect first event after calling enrollFactor with an unsupported type.
        var capturedEvent: TwoFactorFactorsEvent? = null
        val job = kotlinx.coroutines.launch {
            vm.events.collect { capturedEvent = it }
        }

        vm.enrollFactor("unknown_factor_type")
        advanceUntilIdle()
        job.cancel()

        assertTrue(
            "Expected Toast event, got $capturedEvent",
            capturedEvent is TwoFactorFactorsEvent.Toast,
        )
        val toast = capturedEvent as TwoFactorFactorsEvent.Toast
        assertTrue(
            "Toast message should mention the type, got: ${toast.message}",
            toast.message.contains("unknown_factor_type"),
        )
    }

    // ── Stub base — only listFactors() and enrollFactor() are exercised ───────

    private abstract class StubAuthApi : AuthApi {
        override suspend fun login(request: com.bizarreelectronics.crm.data.remote.dto.LoginRequest) =
            throw UnsupportedOperationException()
        override suspend fun verify2FA(request: com.bizarreelectronics.crm.data.remote.dto.TwoFactorRequest) =
            throw UnsupportedOperationException()
        override suspend fun setup2FA(body: Map<String, String>) =
            throw UnsupportedOperationException()
        override suspend fun setPassword(request: com.bizarreelectronics.crm.data.remote.dto.SetPasswordRequest) =
            throw UnsupportedOperationException()
        override suspend fun refresh() =
            throw UnsupportedOperationException()
        override suspend fun logout() =
            throw UnsupportedOperationException()
        override suspend fun getMe() =
            throw UnsupportedOperationException()
        override suspend fun verifyPin(body: Map<String, String>) =
            throw UnsupportedOperationException()
        override suspend fun registerDeviceToken(body: Map<String, String>) =
            throw UnsupportedOperationException()
        override suspend fun changePassword(body: Map<String, String>) =
            throw UnsupportedOperationException()
        override suspend fun changePin(body: Map<String, String>) =
            throw UnsupportedOperationException()
        override suspend fun forgotPassword(request: com.bizarreelectronics.crm.data.remote.dto.ForgotPasswordRequest) =
            throw UnsupportedOperationException()
        override suspend fun resetPassword(request: com.bizarreelectronics.crm.data.remote.dto.ResetPasswordRequest) =
            throw UnsupportedOperationException()
        override suspend fun recoverWithBackupCode(request: com.bizarreelectronics.crm.data.remote.dto.BackupCodeRecoveryRequest) =
            throw UnsupportedOperationException()
        override suspend fun getSetupStatus() =
            throw UnsupportedOperationException()
        override suspend fun switchUser(body: com.bizarreelectronics.crm.data.remote.dto.SwitchUserRequest) =
            throw UnsupportedOperationException()
        override suspend fun sessions() =
            throw UnsupportedOperationException()
        override suspend fun revokeSession(id: String) =
            throw UnsupportedOperationException()
        override suspend fun regenerateRecoveryCodes(body: Map<String, String>) =
            throw UnsupportedOperationException()
        override suspend fun listFactors() =
            throw UnsupportedOperationException()
        override suspend fun enrollFactor(body: Map<String, String>) =
            throw UnsupportedOperationException()
    }
}
