package com.bizarreelectronics.crm.ui.screens.appointments

import com.bizarreelectronics.crm.data.remote.dto.AppointmentItem
import com.bizarreelectronics.crm.data.remote.api.AppointmentApi
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AppointmentRepository @Inject constructor(
    private val api: AppointmentApi,
) {
    suspend fun getAppointments(): List<AppointmentItem> {
        val response = api.getAppointments()
        return response.data ?: emptyList()
    }

    suspend fun getAppointmentById(id: Long): AppointmentItem {
        val response = api.getAppointment(id)
        return response.data ?: error("Appointment $id not found")
    }

    suspend fun patchAppointment(id: Long, body: Map<String, Any?>): AppointmentItem {
        val response = api.patchAppointment(id, body)
        return response.data ?: error("Patch returned no data")
    }

    suspend fun cancelAppointment(id: Long, notifyCustomer: Boolean): Boolean {
        val response = api.cancelAppointment(id, mapOf("notify_customer" to notifyCustomer))
        return response.success
    }

    suspend fun sendReminder(id: Long): Boolean {
        return runCatching { api.sendReminder(id) }.map { it.success }.getOrDefault(false)
    }
}
