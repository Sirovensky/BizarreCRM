package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ActiveSessionDto
import com.bizarreelectronics.crm.data.remote.dto.TwoFactorFactorDto
import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.ForgotPinConfirm
import com.bizarreelectronics.crm.data.remote.dto.ForgotPinRequest
import com.bizarreelectronics.crm.data.remote.dto.PasskeyCredentialInfo
import com.bizarreelectronics.crm.data.remote.dto.PasskeyLoginBeginResponse
import com.bizarreelectronics.crm.data.remote.dto.PasskeyLoginFinishRequest
import com.bizarreelectronics.crm.data.remote.dto.PasskeyRegisterBeginResponse
import com.bizarreelectronics.crm.data.remote.dto.PasskeyRegisterFinishRequest
import com.bizarreelectronics.crm.data.remote.dto.MagicLinkRequest
import com.bizarreelectronics.crm.data.remote.dto.MagicLinkTokenExchange
import com.bizarreelectronics.crm.data.remote.dto.MagicLinkExchangeResponse
import com.bizarreelectronics.crm.data.remote.dto.TenantMeResponse
import com.bizarreelectronics.crm.data.remote.dto.BackupCodeRecoveryRequest
import com.bizarreelectronics.crm.data.remote.dto.ForgotPasswordRequest
import com.bizarreelectronics.crm.data.remote.dto.LoginRequest
import com.bizarreelectronics.crm.data.remote.dto.LoginResponse
import com.bizarreelectronics.crm.data.remote.dto.MessageResponse
import com.bizarreelectronics.crm.data.remote.dto.RecoveryCodesResponse
import com.bizarreelectronics.crm.data.remote.dto.RefreshResponse
import com.bizarreelectronics.crm.data.remote.dto.ResetPasswordRequest
import com.bizarreelectronics.crm.data.remote.dto.SetPasswordRequest
import com.bizarreelectronics.crm.data.remote.dto.SetupStatusResponse
import com.bizarreelectronics.crm.data.remote.dto.SsoDiscoveryResponse
import com.bizarreelectronics.crm.data.remote.dto.SsoTokenExchangeRequest
import com.bizarreelectronics.crm.data.remote.dto.SwitchUserRequest
import com.bizarreelectronics.crm.data.remote.dto.SwitchUserResponse
import com.bizarreelectronics.crm.data.remote.dto.TwoFactorRequest
import com.bizarreelectronics.crm.data.remote.dto.TwoFactorResponse
import com.bizarreelectronics.crm.data.remote.dto.TwoFaSetupResponse
import com.bizarreelectronics.crm.data.remote.dto.UserDto
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path

interface AuthApi {

    @POST("auth/login")
    suspend fun login(@Body request: LoginRequest): ApiResponse<LoginResponse>

    @POST("auth/login/2fa-verify")
    suspend fun verify2FA(@Body request: TwoFactorRequest): ApiResponse<TwoFactorResponse>

    // §2.4 L298 — 2FA enroll. Returns QR data URL, raw secret, manualEntry key,
    // and a (possibly refreshed) challengeToken. Response shape: TwoFaSetupResponse.
    @POST("auth/login/2fa-setup")
    suspend fun setup2FA(@Body body: Map<String, String>): ApiResponse<TwoFaSetupResponse>

    @POST("auth/login/set-password")
    suspend fun setPassword(@Body request: SetPasswordRequest): ApiResponse<LoginResponse>

    @POST("auth/refresh")
    suspend fun refresh(): ApiResponse<RefreshResponse>

    @POST("auth/logout")
    suspend fun logout(): ApiResponse<Unit>

    @GET("auth/me")
    suspend fun getMe(): ApiResponse<UserDto>

    @POST("auth/verify-pin")
    suspend fun verifyPin(@Body body: Map<String, String>): ApiResponse<@JvmSuppressWildcards Map<String, Boolean>>

    @POST("auth/device-token")
    suspend fun registerDeviceToken(@Body body: Map<String, String>): ApiResponse<Unit>

    // U6 fix: profile-screen password and PIN changes. The server endpoints
    // may or may not yet exist under these exact paths (an audit task to add
    // them is tracked server-side). Body shape matches the other auth endpoints
    // that already take Map<String, String>.
    @POST("auth/change-password")
    suspend fun changePassword(@Body body: Map<String, String>): ApiResponse<Unit>

    @POST("auth/change-pin")
    suspend fun changePin(@Body body: Map<String, String>): ApiResponse<Unit>

    // §2.8 — Password reset + backup-code recovery
    @POST("auth/forgot-password")
    suspend fun forgotPassword(@Body request: ForgotPasswordRequest): ApiResponse<MessageResponse>

    @POST("auth/reset-password")
    suspend fun resetPassword(@Body request: ResetPasswordRequest): ApiResponse<MessageResponse>

    @POST("auth/recover-with-backup-code")
    suspend fun recoverWithBackupCode(@Body request: BackupCodeRecoveryRequest): ApiResponse<MessageResponse>

    // §2.1 — setup-status probe. Unauthenticated. Called once on first transition
    // to the credentials step to determine whether the server needs first-run setup
    // or multi-tenant tenant selection before showing the login form.
    @GET("auth/setup-status")
    suspend fun getSetupStatus(): ApiResponse<SetupStatusResponse>

    // §2.5 — switch user on a shared device. Authenticated (requires existing
    // session). Server validates pin against all active users' bcrypt hashes,
    // issues a new 1h accessToken + 8h refreshToken for the matched user.
    // Rate-limited by IP (429 with Retry-After if exceeded).
    // Body: { pin }. Response: { accessToken, user }.
    // SECURITY: pin value is NEVER logged.
    @POST("auth/switch-user")
    suspend fun switchUser(@Body body: SwitchUserRequest): ApiResponse<SwitchUserResponse>

    // §2.11 — Active sessions list + revoke.
    // GET returns all sessions for the current user; current=true marks the
    // calling session. DELETE revokes a specific session by ID.
    // 404 → server does not expose this endpoint yet; ViewModel maps to empty list.
    @GET("auth/sessions")
    suspend fun sessions(): ApiResponse<List<ActiveSessionDto>>

    @DELETE("auth/sessions/{id}")
    suspend fun revokeSession(@Path("id") id: String): ApiResponse<Unit>

    // §2.19 L427 — Recovery codes regenerate.
    // Body carries { password: <current> } for re-authentication.
    // 404 → server predates this endpoint; ViewModel maps to NotSupported state.
    // SECURITY: password value is NEVER logged (Redactor handles body redaction).
    @POST("auth/account/2fa/recovery-codes/regenerate")
    suspend fun regenerateRecoveryCodes(
        @Body body: Map<String, String>,
    ): ApiResponse<RecoveryCodesResponse>

    // §2.18 L419 — 2FA factor list + enroll.
    //
    // GET /auth/2fa/factors — returns all factors currently enrolled for the
    // authenticated user. 404 → server predates this endpoint; ViewModel maps
    // to NotSupported state.
    //
    // POST /auth/2fa/factors/enroll — enroll a new factor.
    // Body shape: { type: "totp"|"sms"|"hardware_key"|"passkey", label?: string }
    // For SMS, body also carries { phone: E.164 } for server-side OTP dispatch.
    // Returns ApiResponse<Unit>; the caller navigates to the per-type verify step.
    // 404 → type not yet supported on this server; ViewModel flags accordingly.
    @GET("auth/2fa/factors")
    suspend fun listFactors(): ApiResponse<List<TwoFactorFactorDto>>

    @POST("auth/2fa/factors/enroll")
    suspend fun enrollFactor(@Body body: Map<String, String>): ApiResponse<Unit>

    // §2.20 L443 — SSO provider discovery + token exchange.
    //
    // GET /auth/sso/providers — lists IdP configurations enabled for this tenant.
    //   404 → no SSO configured; ViewModel hides the "Sign in with SSO" button silently.
    //   Response: SsoDiscoveryResponse { providers: List<SsoProvider> }
    //
    // POST /auth/sso/token-exchange — exchanges the authorization code from the
    //   Chrome Custom Tabs callback for an access + refresh token pair.
    //   Body: { provider, code, state }. 400 → state mismatch (CSRF guard).
    //   Response: LoginResponse (re-uses the same token shape as password login).
    //   404 → server predates this endpoint; treat as unsupported.
    @GET("auth/sso/providers")
    suspend fun getSsoProviders(): ApiResponse<SsoDiscoveryResponse>

    @POST("auth/sso/token-exchange")
    suspend fun tokenExchange(@Body request: SsoTokenExchangeRequest): ApiResponse<TwoFactorResponse>

    // §2.21 L454 — Magic-link login.
    //
    // POST /auth/magic-link/request — dispatches a signed one-time link to [email].
    //   Body: MagicLinkRequest { email }
    //   Response: MessageResponse { message }
    //   404 → magic-link login is disabled for this tenant; caller hides the button.
    //
    // POST /auth/magic-link/exchange — redeems the token from the App Link URI.
    //   Body: MagicLinkTokenExchange { token, deviceFingerprint }
    //   Same-device path: returns { accessToken, refreshToken, user }.
    //   Different-device path: returns { requires_2fa: true, challengeToken }.
    //   404 → magic-link login is disabled; caller surfaces a graceful error.
    //   Token is one-time-use; server enforces 15-minute TTL.
    //
    // GET /tenants/me — returns TenantMeResponse.  When magic_links_enabled = false
    //   the "Email me a link" button is hidden on the credentials step (opt-out model).
    @POST("auth/magic-link/request")
    suspend fun requestMagicLink(@Body request: MagicLinkRequest): ApiResponse<MessageResponse>

    @POST("auth/magic-link/exchange")
    suspend fun exchangeMagicLink(@Body request: MagicLinkTokenExchange): ApiResponse<MagicLinkExchangeResponse>

    @GET("tenants/me")
    suspend fun getTenantMe(): ApiResponse<TenantMeResponse>

    // §2.22 L463 — Passkey (WebAuthn) registration + login + list + delete.
    //
    // Registration flow (two-step challenge/response):
    //   POST /auth/passkey/register/begin  → PasskeyRegisterBeginResponse { challengeJson }
    //     Android passes challengeJson to CredentialManager.create() via PasskeyManager.
    //   POST /auth/passkey/register/finish → Unit (server stores the new credential).
    //     Body: { responseJson: <attestation JSON from CredentialManager> }
    //   404 on either endpoint → passkeys are disabled for this tenant.
    //
    // Login flow (two-step challenge/response):
    //   POST /auth/passkey/login/begin   → PasskeyLoginBeginResponse { challengeJson }
    //     Android passes challengeJson to CredentialManager.getCredential() via PasskeyManager.
    //   POST /auth/passkey/login/finish  → TwoFactorResponse (same token shape as password login).
    //     Body: { responseJson: <assertion JSON from CredentialManager> }
    //   404 on either endpoint → passkeys are disabled for this tenant.
    //
    // Management:
    //   GET  /auth/passkey/list     → list of PasskeyCredentialInfo (empty if none enrolled).
    //   DELETE /auth/passkey/{id}   → removes a single credential.
    //   404 on list → server predates passkey support; ViewModel treats as empty list.
    //   404 on delete → credential already removed (idempotent; surface user-friendly message).
    //
    // Hardware key (§2.23): CredentialManager's FIDO2 stack transparently includes
    // USB-C / NFC security keys. No separate endpoint is required — the same begin/finish
    // handshake works for both platform authenticators and roaming (hardware key) authenticators.
    @POST("auth/passkey/register/begin")
    suspend fun beginPasskeyRegistration(): ApiResponse<PasskeyRegisterBeginResponse>

    @POST("auth/passkey/register/finish")
    suspend fun finishPasskeyRegistration(
        @Body request: PasskeyRegisterFinishRequest,
    ): ApiResponse<Unit>

    @POST("auth/passkey/login/begin")
    suspend fun beginPasskeyLogin(): ApiResponse<PasskeyLoginBeginResponse>

    @POST("auth/passkey/login/finish")
    suspend fun finishPasskeyLogin(
        @Body request: PasskeyLoginFinishRequest,
    ): ApiResponse<TwoFactorResponse>

    @GET("auth/passkey/list")
    suspend fun listPasskeys(): ApiResponse<List<PasskeyCredentialInfo>>

    @DELETE("auth/passkey/{id}")
    suspend fun deletePasskey(@Path("id") id: String): ApiResponse<Unit>

    // §2.15 L387-L388 — Forgot-PIN email reset.
    //
    // POST /auth/forgot-pin/request — dispatches a reset link to [email].
    //   Response: MessageResponse { message }
    //   404 → feature disabled (email server absent on self-hosted tenant).
    //         Callers surface "Ask admin to reset from Employees" fallback.
    //
    // POST /auth/forgot-pin/confirm — redeems the token from the deep link
    //   and sets [newPin] as the new PIN on the server.
    //   Response: MessageResponse { message }
    //   404 → feature disabled; same fallback as above.
    //   SECURITY: [ForgotPinConfirm.newPin] is NEVER logged.
    @POST("auth/forgot-pin/request")
    suspend fun requestForgotPin(
        @Body request: ForgotPinRequest,
    ): ApiResponse<MessageResponse>

    @POST("auth/forgot-pin/confirm")
    suspend fun confirmForgotPin(
        @Body request: ForgotPinConfirm,
    ): ApiResponse<MessageResponse>
}
