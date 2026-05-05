package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.NotificationListData
import com.bizarreelectronics.crm.data.remote.dto.UnreadCountData
import retrofit2.http.GET
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query

interface NotificationApi {

    @GET("notifications")
    suspend fun getNotifications(
        @Query("page") page: Int = 1
    ): ApiResponse<NotificationListData>

    @GET("notifications/unread-count")
    suspend fun getUnreadCount(): ApiResponse<UnreadCountData>

    @PATCH("notifications/{id}/read")
    suspend fun markRead(@Path("id") id: Long): ApiResponse<Unit>

    @POST("notifications/mark-all-read")
    suspend fun markAllRead(): ApiResponse<Unit>
}
