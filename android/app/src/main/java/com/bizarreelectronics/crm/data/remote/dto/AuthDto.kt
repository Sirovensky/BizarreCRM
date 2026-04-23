package com.bizarreelectronics.crm.data.remote.dto

import com.google.gson.annotations.SerializedName

data class LoginRequest(
    val username: String,
    val password: String
)

data class LoginResponse(
    @SerializedName("challengeToken")
    val challengeToken: String?,
    @SerializedName("requiresPasswordSetup")
    val requiresPasswordSetup: Boolean? = false,
    @SerializedName("totpEnabled")
    val totpEnabled: Boolean? = false,
    @SerializedName("requires2faSetup")
    val requires2faSetup: Boolean? = false,
    @SerializedName("qrCode")
    val qrCode: String? = null,
    @SerializedName("qr")
    val qr: String? = null,
)

data class TwoFactorRequest(
    val challengeToken: String,
    val code: String
)

data class TwoFactorResponse(
    @SerializedName("accessToken")
    val accessToken: String,
    @SerializedName("refreshToken")
    val refreshToken: String?,
    val user: UserDto,
    val backupCodes: List<String>?,
)

data class SetPasswordRequest(
    val challengeToken: String,
    val password: String
)

data class RefreshResponse(
    @SerializedName("accessToken")
    val accessToken: String
)

data class UserDto(
    val id: Long,
    val username: String,
    @SerializedName("first_name")
    val firstName: String?,
    @SerializedName("last_name")
    val lastName: String?,
    val email: String?,
    val role: String,
    @SerializedName("avatar_url")
    val avatarUrl: String?
)

// RegisterDeviceRequest removed — /auth/register-device does not exist on server

// §2.8 — Password reset + backup-code recovery DTOs

data class ForgotPasswordRequest(
    val email: String,
)

data class ResetPasswordRequest(
    val token: String,
    val password: String,
)

/** §2.8 backup-code recovery — server takes email + backupCode + newPassword */
data class BackupCodeRecoveryRequest(
    val email: String,
    @SerializedName("backupCode")
    val backupCode: String,
    @SerializedName("newPassword")
    val newPassword: String,
)

/** Generic server message wrapper used by forgot-password, reset-password, and recovery */
data class MessageResponse(
    val message: String?,
)

/**
 * §2.1 — Response from GET /auth/setup-status.
 *
 * Server returns exactly two fields:
 *   - needsSetup:    true when no active users exist (first-run wizard required)
 *   - isMultiTenant: true when the server is running in SaaS/multi-tenant mode
 *
 * Verified against packages/server/src/routes/auth.routes.ts line 435-445.
 */
data class SetupStatusResponse(
    @SerializedName("needsSetup")
    val needsSetup: Boolean,
    @SerializedName("isMultiTenant")
    val isMultiTenant: Boolean? = null,
)
