package com.bizarreelectronics.crm.data.repository

import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.remote.api.NotificationPreferenceDto
import com.bizarreelectronics.crm.data.remote.api.NotificationPreferencesApi
import com.bizarreelectronics.crm.data.remote.api.NotificationPreferencesPatchRequest
import com.bizarreelectronics.crm.data.remote.api.NotificationQuietHoursDto
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import retrofit2.HttpException
import timber.log.Timber

@Singleton
class NotificationPreferencesRepository @Inject constructor(
    private val api: NotificationPreferencesApi,
    private val appPreferences: AppPreferences,
) {
    suspend fun refreshLocalFromServer(): Boolean = withContext(Dispatchers.IO) {
        try {
            val data = api.getMyPreferences().data ?: return@withContext false
            var appliedAny = false
            data.preferences
                .filter { it.stored }
                .forEach { pref ->
                    applyStoredPreference(pref)
                    appliedAny = true
                }
            appliedAny
        } catch (e: HttpException) {
            if (e.code() != 404) {
                Timber.w(e, "notification preferences refresh failed")
            }
            false
        } catch (e: Exception) {
            Timber.w(e, "notification preferences refresh failed")
            false
        }
    }

    suspend fun patchServer(request: NotificationPreferencesPatchRequest): Boolean =
        withContext(Dispatchers.IO) {
            try {
                api.patchMyPreferences(request)
                true
            } catch (e: HttpException) {
                if (e.code() != 404) {
                    Timber.w(e, "notification preferences patch failed")
                }
                false
            } catch (e: Exception) {
                Timber.w(e, "notification preferences patch failed")
                false
            }
        }

    private fun applyStoredPreference(pref: NotificationPreferenceDto) {
        pref.quietHours?.let(::applyQuietHours)

        val eventType = canonicalEventId(pref.eventType)
        when {
            eventType == EVENT_GLOBAL && pref.channel == CHANNEL_EMAIL ->
                appPreferences.notifEmailAlertsEnabled = pref.enabled
            eventType == EVENT_GLOBAL && pref.channel == CHANNEL_SMS ->
                appPreferences.notifSmsAlertsEnabled = pref.enabled
            eventType == EVENT_GLOBAL && pref.channel == CHANNEL_PUSH ->
                appPreferences.notifPushEnabled = pref.enabled
            eventType == EVENT_LOW_STOCK && pref.channel == CHANNEL_IN_APP ->
                appPreferences.notifLowStockEnabled = pref.enabled
            eventType == EVENT_TICKET_CREATED && pref.channel == CHANNEL_IN_APP ->
                appPreferences.notifNewTicketEnabled = pref.enabled
            eventType == EVENT_APPOINTMENT_REMINDER && pref.channel == CHANNEL_IN_APP ->
                appPreferences.notifAppointmentReminderEnabled = pref.enabled
            pref.channel in MATRIX_CHANNELS ->
                appPreferences.setNotifMatrixEnabled(eventType, pref.channel, pref.enabled)
        }
    }

    private fun applyQuietHours(quietHours: NotificationQuietHoursDto) {
        appPreferences.quietHoursEnabled = quietHours.enabled
        appPreferences.quietHoursStartMinutes = quietHours.startMinutes
        appPreferences.quietHoursEndMinutes = quietHours.endMinutes
    }

    private fun canonicalEventId(eventType: String): String = when (eventType) {
        "inventory_low" -> EVENT_LOW_STOCK
        "time_off_requested" -> "timeoff_request"
        "security_alert" -> "security_event"
        else -> eventType
    }

    companion object {
        const val EVENT_GLOBAL = "global"
        const val EVENT_LOW_STOCK = "low_stock"
        const val EVENT_TICKET_CREATED = "ticket_created"
        const val EVENT_APPOINTMENT_REMINDER = "appointment_reminder"
        const val CHANNEL_PUSH = "push"
        const val CHANNEL_IN_APP = "in_app"
        const val CHANNEL_EMAIL = "email"
        const val CHANNEL_SMS = "sms"

        val MATRIX_CHANNELS: Set<String> = setOf(CHANNEL_PUSH, CHANNEL_SMS, CHANNEL_EMAIL)
    }
}
