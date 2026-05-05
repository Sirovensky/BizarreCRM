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

    /** §10.3 Minimal quick-create: POST /appointments with title + start_time + end_time only. */
    suspend fun quickCreate(body: Map<String, Any?>): AppointmentItem {
        val response = api.createAppointment(body)
        return response.data ?: error("Quick-create returned no data")
    }

    /** §10.1 Kanban reschedule: PATCH /appointments/{id} with new employee / start time. */
    suspend fun reschedule(id: Long, body: Map<String, Any?>): AppointmentItem {
        val response = api.patchAppointment(id, body)
        return response.data ?: error("Reschedule returned no data")
    }

    /**
     * §10.6 Check-in: POST /appointments/{id}/check-in.
     * Server sets status="checked_in" + checked_in_at=now.
     * Returns 404 on older server versions — callers fall back to PATCH status.
     */
    suspend fun checkIn(id: Long): AppointmentItem {
        val response = api.checkIn(id)
        return response.data ?: error("Check-in returned no data")
    }

    /**
     * §10.6 Check-out: POST /appointments/{id}/check-out.
     * Server sets status="completed" + checked_out_at=now.
     * Returns 404 on older server versions — callers fall back to PATCH status.
     */
    suspend fun checkOut(id: Long): AppointmentItem {
        val response = api.checkOut(id)
        return response.data ?: error("Check-out returned no data")
    }
}
