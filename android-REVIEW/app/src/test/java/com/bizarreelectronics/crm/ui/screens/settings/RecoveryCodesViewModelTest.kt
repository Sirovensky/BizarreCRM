package com.bizarreelectronics.crm.ui.screens.settings

// §2.19 L427-L438 — JVM unit tests for RecoveryCodesViewModel.
//
// Three tests:
//   1. regenerate_success   — happy path emits Generated(codes).
//   2. regenerate_404       — server 404 maps to NotSupported.
//   3. regenerate_401       — wrong password re-emits RequiringPassword.

import com.bizarreelectronics.crm.data.remote.api.AuthApi
import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.RecoveryCodesResponse
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
class RecoveryCodesViewModelTest {

    private val testDispatcher = StandardTestDispatcher()

    @Before
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    // ── Test 1: happy path — server returns codes → Generated state ───────────

    @Test
    fun `regenerate success - emits Generated with returned codes`() = runTest {
        val expectedCodes = listOf("abc12345", "def67890", "ghi11111")
        val api = object : StubAuthApi() {
            override suspend fun regenerateRecoveryCodes(body: Map<String, String>) =
                ApiResponse(
                    success = true,
                    data = RecoveryCodesResponse(
                        codes = expectedCodes,
                        generatedAt = "2026-04-23T00:00:00Z",
                        remaining = expectedCodes.size,
                    ),
                )
        }

        val vm = RecoveryCodesViewModel(api)
        vm.regenerate("correct-password")
        advanceUntilIdle()

        val state = vm.uiState.value
        assertTrue("Expected Generated state, got $state", state is RecoveryCodesUiState.Generated)
        assertEquals(expectedCodes, (state as RecoveryCodesUiState.Generated).codes)
    }

    // ── Test 2: server 404 → NotSupported ────────────────────────────────────

    @Test
    fun `regenerate 404 - maps to NotSupported state`() = runTest {
        val api = object : StubAuthApi() {
            override suspend fun regenerateRecoveryCodes(body: Map<String, String>): ApiResponse<RecoveryCodesResponse> {
                throw HttpException(
                    Response.error<ApiResponse<RecoveryCodesResponse>>(
                        404,
                        okhttp3.ResponseBody.create(null, "Not Found"),
                    )
                )
            }
        }

        val vm = RecoveryCodesViewModel(api)
        vm.regenerate("any-password")
        advanceUntilIdle()

        assertEquals(RecoveryCodesUiState.NotSupported, vm.uiState.value)
    }

    // ── Test 3: server 401 → back to RequiringPassword (re-prompt) ───────────

    @Test
    fun `regenerate 401 - re-emits RequiringPassword for re-entry`() = runTest {
        val api = object : StubAuthApi() {
            override suspend fun regenerateRecoveryCodes(body: Map<String, String>): ApiResponse<RecoveryCodesResponse> {
                throw HttpException(
                    Response.error<ApiResponse<RecoveryCodesResponse>>(
                        401,
                        okhttp3.ResponseBody.create(null, "Unauthorized"),
                    )
                )
            }
        }

        val vm = RecoveryCodesViewModel(api)
        vm.regenerate("wrong-password")
        advanceUntilIdle()

        assertEquals(RecoveryCodesUiState.RequiringPassword, vm.uiState.value)
    }

    // ── Stub base — only regenerateRecoveryCodes() is exercised ──────────────

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
        override suspend fun deleteDeviceToken(token: String) =
            throw UnsupportedOperationException()
    }
}
