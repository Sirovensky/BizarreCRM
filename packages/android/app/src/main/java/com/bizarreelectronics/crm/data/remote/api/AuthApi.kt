package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.LoginRequest
import com.bizarreelectronics.crm.data.remote.dto.LoginResponse
import com.bizarreelectronics.crm.data.remote.dto.RefreshResponse
import com.bizarreelectronics.crm.data.remote.dto.SetPasswordRequest
import com.bizarreelectronics.crm.data.remote.dto.TwoFactorRequest
import com.bizarreelectronics.crm.data.remote.dto.TwoFactorResponse
import com.bizarreelectronics.crm.data.remote.dto.UserDto
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST

interface AuthApi {

    @POST("auth/login")
    suspend fun login(@Body request: LoginRequest): ApiResponse<LoginResponse>

    @POST("auth/login/2fa-verify")
    suspend fun verify2FA(@Body request: TwoFactorRequest): ApiResponse<TwoFactorResponse>

    @POST("auth/login/2fa-setup")
    suspend fun setup2FA(@Body body: Map<String, String>): ApiResponse<LoginResponse>

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
}
