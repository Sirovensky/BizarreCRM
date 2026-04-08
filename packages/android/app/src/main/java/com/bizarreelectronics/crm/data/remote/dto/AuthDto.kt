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
