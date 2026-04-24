package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ActiveSessionDto
import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
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
}
