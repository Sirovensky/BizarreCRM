package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.google.gson.annotations.SerializedName
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.PATCH

interface NotificationPreferencesApi {
    @GET("users/me/notification-prefs")
    suspend fun getMyPreferences(): ApiResponse<NotificationPreferencesData>

    @PATCH("users/me/notification-prefs")
    suspend fun patchMyPreferences(
        @Body request: NotificationPreferencesPatchRequest,
    ): ApiResponse<NotificationPreferencesData>
}

data class NotificationPreferencesData(
    val preferences: List<NotificationPreferenceDto> = emptyList(),
    @SerializedName("event_types")
    val eventTypes: List<String> = emptyList(),
    val channels: List<String> = emptyList(),
)

data class NotificationPreferenceDto(
    @SerializedName("event_type")
    val eventType: String,
    val channel: String,
    val enabled: Boolean = true,
    @SerializedName("quiet_hours")
    val quietHours: NotificationQuietHoursDto? = null,
    val stored: Boolean = false,
)

data class NotificationPreferencesPatchRequest(
    val preferences: List<NotificationPreferencePatchDto>,
)

data class NotificationPreferencePatchDto(
    @SerializedName("event_type")
    val eventType: String,
    val channel: String,
    val enabled: Boolean,
    @SerializedName("quiet_hours")
    val quietHours: NotificationQuietHoursDto? = null,
)

data class NotificationQuietHoursDto(
    val enabled: Boolean,
    @SerializedName("start_minutes")
    val startMinutes: Int,
    @SerializedName("end_minutes")
    val endMinutes: Int,
)
