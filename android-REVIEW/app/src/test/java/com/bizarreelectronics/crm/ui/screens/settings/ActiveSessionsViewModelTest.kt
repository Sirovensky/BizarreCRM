package com.bizarreelectronics.crm.ui.screens.settings

// §2.11 — JVM unit tests for ActiveSessionsViewModel optimistic-revoke rollback.
//
// Two tests:
//   1. revoke_success  — optimistic removal is committed (session absent after call).
//   2. revoke_failure  — network error rolls back to the pre-removal list.

import com.bizarreelectronics.crm.data.remote.api.AuthApi
import com.bizarreelectronics.crm.data.remote.dto.ActiveSessionDto
import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.IOException

@OptIn(ExperimentalCoroutinesApi::class)
class ActiveSessionsViewModelTest {

    private val testDispatcher = StandardTestDispatcher()

    // Minimal stub sessions
    private val sessionA = ActiveSessionDto(id = "aaa", device = "Phone A", current = false)
    private val sessionB = ActiveSessionDto(id = "bbb", device = "Phone B", current = true)

    @Before
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    // ── Test 1: successful revoke keeps optimistic removal ────────────────────

    @Test
    fun `revoke success - session is permanently removed from list`() = runTest {
        val api = object : StubAuthApi() {
            override suspend fun sessions() =
                ApiResponse(success = true, data = listOf(sessionA, sessionB))

            override suspend fun revokeSession(id: String) =
                ApiResponse<Unit>(success = true, data = null)
        }

        val vm = ActiveSessionsViewModel(api)
        advanceUntilIdle() // load sessions

        val contentBefore = vm.uiState.value as ActiveSessionsUiState.Content
        assertEquals(2, contentBefore.sessions.size)

        vm.revoke("aaa")
        advanceUntilIdle() // optimistic remove + server call completes

        val contentAfter = vm.uiState.value as ActiveSessionsUiState.Content
        assertEquals(1, contentAfter.sessions.size)
        assertFalse(contentAfter.sessions.any { it.id == "aaa" })
        assertEquals("bbb", contentAfter.sessions.first().id)
    }

    // ── Test 2: network failure rolls back optimistic removal ─────────────────

    @Test
    fun `revoke failure - optimistic removal is rolled back`() = runTest {
        val api = object : StubAuthApi() {
            override suspend fun sessions() =
                ApiResponse(success = true, data = listOf(sessionA, sessionB))

            override suspend fun revokeSession(id: String): ApiResponse<Unit> =
                throw IOException("network gone")
        }

        val vm = ActiveSessionsViewModel(api)
        advanceUntilIdle() // load sessions

        vm.revoke("aaa")
        advanceUntilIdle() // optimistic remove + failure + rollback

        val contentAfter = vm.uiState.value as ActiveSessionsUiState.Content
        assertEquals(2, contentAfter.sessions.size)
        assertTrue(contentAfter.sessions.any { it.id == "aaa" })
    }

    // ── Stub base — only sessions() and revokeSession() are overridden ────────

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
        override suspend fun regenerateRecoveryCodes(body: Map<String, String>) =
            throw UnsupportedOperationException()
        override suspend fun deleteDeviceToken(token: String) =
            throw UnsupportedOperationException()
    }
}
