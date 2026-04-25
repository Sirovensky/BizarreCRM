package com.bizarreelectronics.crm.ui.screens.settings

// §2.15 L387-L388 — JVM unit tests for ForgotPinViewModel state transitions.
//
// [ForgotPinViewModel.commitPin] is `internal open` so this test subclass can
// intercept the PIN-write side-effect without instantiating EncryptedSharedPreferences
// (an Android-framework dependency).  DeepLinkBus is pure Kotlin — used directly.
//
// Scenarios:
//   1. requestEmailReset happy path → EmailSent
//   2. requestEmailReset IOException → Error
//   3. requestEmailReset 404 → FeatureDisabled
//   4. deep-link token while EmailSent → SettingPin
//   5. blocklisted PIN (1234) → Error
//   6. valid PIN confirm → Success; commitPin() called
//   7. confirm 404 → FeatureDisabled

import com.bizarreelectronics.crm.data.remote.api.AuthApi
import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.ForgotPinConfirm
import com.bizarreelectronics.crm.data.remote.dto.ForgotPinRequest
import com.bizarreelectronics.crm.data.remote.dto.MessageResponse
import com.bizarreelectronics.crm.util.DeepLinkBus
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import okhttp3.ResponseBody
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import retrofit2.HttpException

@OptIn(ExperimentalCoroutinesApi::class)
class ForgotPinViewModelTest {

    private val testDispatcher = StandardTestDispatcher()

    @Before
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    // ── Test 1: happy-path email request ──────────────────────────────────────

    @Test
    fun `requestEmailReset happy path transitions to EmailSent`() = runTest {
        val api = object : StubAuthApi() {
            override suspend fun requestForgotPin(request: ForgotPinRequest) =
                ApiResponse(success = true, data = MessageResponse("sent"))
        }
        val vm = makeVm(api)
        assertEquals(ForgotPinViewModel.UiState.Idle, vm.state.value)

        vm.requestEmailReset("tech@example.com")
        advanceUntilIdle()

        assertEquals(ForgotPinViewModel.UiState.EmailSent, vm.state.value)
    }

    // ── Test 2: network error → Error ─────────────────────────────────────────

    @Test
    fun `requestEmailReset IOException transitions to Error`() = runTest {
        val api = object : StubAuthApi() {
            override suspend fun requestForgotPin(request: ForgotPinRequest): ApiResponse<MessageResponse> =
                throw java.io.IOException("no network")
        }
        val vm = makeVm(api)
        vm.requestEmailReset("tech@example.com")
        advanceUntilIdle()

        assertTrue(
            "Expected Error, got ${vm.state.value}",
            vm.state.value is ForgotPinViewModel.UiState.Error,
        )
    }

    // ── Test 3: 404 → FeatureDisabled ─────────────────────────────────────────

    @Test
    fun `requestEmailReset 404 transitions to FeatureDisabled`() = runTest {
        val api = object : StubAuthApi() {
            override suspend fun requestForgotPin(request: ForgotPinRequest): ApiResponse<MessageResponse> =
                throw make404()
        }
        val vm = makeVm(api)
        vm.requestEmailReset("tech@example.com")
        advanceUntilIdle()

        assertEquals(ForgotPinViewModel.UiState.FeatureDisabled, vm.state.value)
    }

    // ── Test 4: deep-link token while EmailSent → SettingPin ──────────────────

    @Test
    fun `deep-link token while EmailSent advances to SettingPin`() = runTest {
        val api = object : StubAuthApi() {
            override suspend fun requestForgotPin(request: ForgotPinRequest) =
                ApiResponse(success = true, data = MessageResponse("sent"))
        }
        val bus = DeepLinkBus()
        val vm = makeVm(api, bus)

        vm.requestEmailReset("tech@example.com")
        advanceUntilIdle() // → EmailSent

        bus.publishForgotPinToken("abc123abc123abc123abc1") // 22 valid chars
        advanceUntilIdle()

        val s = vm.state.value
        assertTrue("Expected SettingPin, got $s", s is ForgotPinViewModel.UiState.SettingPin)
        assertEquals("abc123abc123abc123abc1", (s as ForgotPinViewModel.UiState.SettingPin).token)
    }

    // ── Test 5: blocklisted PIN → Error ───────────────────────────────────────

    @Test
    fun `blocklisted PIN 1234 shows Error without network call`() = runTest {
        val bus = DeepLinkBus()
        val vm = makeVm(StubAuthApi(), bus)

        bus.publishForgotPinToken("tok123tok123tok123tok1")
        advanceUntilIdle() // → SettingPin

        vm.onDigit('1', 4)
        vm.onDigit('2', 4)
        vm.onDigit('3', 4)
        vm.onDigit('4', 4) // auto-submits 1234; blocked by PinBlocklist
        advanceUntilIdle()

        val s = vm.state.value
        assertTrue("Expected Error for 1234, got $s", s is ForgotPinViewModel.UiState.Error)
        val msg = (s as ForgotPinViewModel.UiState.Error).message
        assertTrue("Error should mention 'common'", msg.contains("common", ignoreCase = true))
    }

    // ── Test 6: valid PIN confirm → Success + commitPin called ────────────────

    @Test
    fun `valid PIN confirm transitions to Success and calls commitPin`() = runTest {
        var committedPin: String? = null
        val api = object : StubAuthApi() {
            override suspend fun confirmForgotPin(request: ForgotPinConfirm) =
                ApiResponse(success = true, data = MessageResponse("ok"))
        }
        val bus = DeepLinkBus()
        val vm = object : ForgotPinViewModel(api, NoOpPinPrefs, bus) {
            override fun commitPin(newPin: String) {
                committedPin = newPin
            }
        }

        bus.publishForgotPinToken("tok123tok123tok123tok1")
        advanceUntilIdle()

        // 7395 is not in blocklist
        vm.onDigit('7', 4)
        vm.onDigit('3', 4)
        vm.onDigit('9', 4)
        vm.onDigit('5', 4)
        advanceUntilIdle()

        assertEquals(ForgotPinViewModel.UiState.Success, vm.state.value)
        assertEquals("7395", committedPin)
    }

    // ── Test 7: confirm 404 → FeatureDisabled ────────────────────────────────

    @Test
    fun `confirm 404 transitions to FeatureDisabled`() = runTest {
        val api = object : StubAuthApi() {
            override suspend fun confirmForgotPin(request: ForgotPinConfirm): ApiResponse<MessageResponse> =
                throw make404()
        }
        val bus = DeepLinkBus()
        val vm = makeVm(api, bus)

        bus.publishForgotPinToken("tok123tok123tok123tok1")
        advanceUntilIdle()

        vm.onDigit('7', 4)
        vm.onDigit('3', 4)
        vm.onDigit('9', 4)
        vm.onDigit('5', 4)
        advanceUntilIdle()

        assertEquals(ForgotPinViewModel.UiState.FeatureDisabled, vm.state.value)
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun makeVm(
        api: AuthApi = StubAuthApi(),
        bus: DeepLinkBus = DeepLinkBus(),
    ): ForgotPinViewModel = object : ForgotPinViewModel(api, NoOpPinPrefs, bus) {
        override fun commitPin(newPin: String) = Unit // no-op; PinPreferences not needed
    }

    private fun make404(): HttpException {
        val body = ResponseBody.create(null, "")
        val response = retrofit2.Response.error<Any>(404, body)
        return HttpException(response)
    }

    // ── No-op PinPreferences stub ─────────────────────────────────────────────

    /**
     * Passed to [ForgotPinViewModel] so Hilt DI types are satisfied.
     * All three methods used by the VM ([commitPin]) are overridden in the
     * anonymous subclasses above; this object is never called in practice.
     *
     * We pass `null!!` as the context — it is stored but never read because
     * [ForgotPinViewModel.commitPin] is overridden in every test VM.
     */
    @Suppress("UNCHECKED_CAST")
    private object NoOpPinPrefs : com.bizarreelectronics.crm.data.local.prefs.PinPreferences(
        // The context parameter is stored in a field but EncryptedSharedPreferences
        // is only constructed on first access to `prefs`. Since every test VM overrides
        // `commitPin()` — the only method that touches `prefs` — EncryptedSharedPreferences
        // is never initialised and `null` is safe here.
        context = null as android.content.Context,
    )

    // ── Stub AuthApi ─────────────────────────────────────────────────────────

    private open class StubAuthApi : AuthApi {
        override suspend fun login(r: com.bizarreelectronics.crm.data.remote.dto.LoginRequest) = err()
        override suspend fun verify2FA(r: com.bizarreelectronics.crm.data.remote.dto.TwoFactorRequest) = err()
        override suspend fun setup2FA(b: Map<String, String>) = err()
        override suspend fun setPassword(r: com.bizarreelectronics.crm.data.remote.dto.SetPasswordRequest) = err()
        override suspend fun refresh() = err()
        override suspend fun logout() = err()
        override suspend fun getMe() = err()
        override suspend fun verifyPin(b: Map<String, String>) = err()
        override suspend fun registerDeviceToken(b: Map<String, String>) = err()
        override suspend fun changePassword(b: Map<String, String>) = err()
        override suspend fun changePin(b: Map<String, String>) = err()
        override suspend fun forgotPassword(r: com.bizarreelectronics.crm.data.remote.dto.ForgotPasswordRequest) = err()
        override suspend fun resetPassword(r: com.bizarreelectronics.crm.data.remote.dto.ResetPasswordRequest) = err()
        override suspend fun recoverWithBackupCode(r: com.bizarreelectronics.crm.data.remote.dto.BackupCodeRecoveryRequest) = err()
        override suspend fun getSetupStatus() = err()
        override suspend fun switchUser(b: com.bizarreelectronics.crm.data.remote.dto.SwitchUserRequest) = err()
        override suspend fun sessions() = err()
        override suspend fun revokeSession(id: String) = err()
        override suspend fun regenerateRecoveryCodes(b: Map<String, String>) = err()
        override suspend fun listFactors() = err()
        override suspend fun enrollFactor(b: Map<String, String>) = err()
        override suspend fun getSsoProviders() = err()
        override suspend fun tokenExchange(r: com.bizarreelectronics.crm.data.remote.dto.SsoTokenExchangeRequest) = err()
        override suspend fun requestMagicLink(r: com.bizarreelectronics.crm.data.remote.dto.MagicLinkRequest) = err()
        override suspend fun exchangeMagicLink(r: com.bizarreelectronics.crm.data.remote.dto.MagicLinkTokenExchange) = err()
        override suspend fun getTenantMe() = err()
        override suspend fun requestForgotPin(r: ForgotPinRequest): ApiResponse<MessageResponse> = err()
        override suspend fun confirmForgotPin(r: ForgotPinConfirm): ApiResponse<MessageResponse> = err()
        override suspend fun deleteDeviceToken(token: String) = err()
        private fun err(): Nothing = throw UnsupportedOperationException("stub")
    }
}
