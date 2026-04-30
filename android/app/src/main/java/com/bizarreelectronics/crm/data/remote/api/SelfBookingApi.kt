package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.google.gson.annotations.SerializedName
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Query

/**
 * §58 — Appointment Self-Booking (customer-facing, public route).
 *
 * No authentication required: these endpoints are intentionally unauthenticated
 * so customers can book an appointment without a staff account. The server gates
 * access by locationId only; no JWT is issued or consumed.
 *
 * AuthInterceptor skips paths containing "/public/" (same as "/track/" for §55).
 *
 * Server routes (expected — 404-tolerant; client degrades to empty state):
 *   GET /api/v1/public/booking/slots    — available appointment slots for a location + date range
 *   POST /api/v1/public/booking/reserve — reserve a slot and create a pending appointment
 */
interface SelfBookingApi {

    /**
     * Fetch available booking slots for [locationId] within the given date range.
     *
     * [date] is ISO-8601 date (yyyy-MM-dd). The server returns slots for that
     * calendar week by default; pass explicit start/end if needed.
     *
     * Returns a list of [BookingSlot] on success. 404 when the location is not
     * found or booking is disabled for the location. 429 when rate-limited.
     */
    @GET("public/booking/slots")
    suspend fun getAvailableSlots(
        @Query("locationId") locationId: String,
        @Query("date") date: String,
    ): ApiResponse<List<BookingSlot>>

    /**
     * Reserve a slot and create a pending appointment.
     *
     * Returns a [BookingConfirmation] on success (HTTP 201).
     * 404 when the slot is no longer available or the location does not exist.
     * 409 when the slot was taken since it was fetched (race condition — show retry).
     */
    @POST("public/booking/reserve")
    suspend fun reserveSlot(
        @Body request: BookingReserveRequest,
    ): ApiResponse<BookingConfirmation>
}

// ---------------------------------------------------------------------------
// DTOs
// ---------------------------------------------------------------------------

/** A single bookable time slot returned by GET /public/booking/slots. */
data class BookingSlot(
    @SerializedName("slot_id")     val slotId: String,
    @SerializedName("start_time")  val startTime: String,   // ISO-8601 datetime
    @SerializedName("end_time")    val endTime: String,     // ISO-8601 datetime
    @SerializedName("available")   val available: Boolean,
    @SerializedName("label")       val label: String?,      // e.g. "10:00 AM"
    @SerializedName("service")     val service: String?,    // e.g. "Screen Repair"
)

/** Request body for POST /public/booking/reserve. */
data class BookingReserveRequest(
    @SerializedName("slot_id")       val slotId: String,
    @SerializedName("location_id")   val locationId: String,
    @SerializedName("customer_name") val customerName: String,
    @SerializedName("customer_phone")val customerPhone: String,
    @SerializedName("customer_email")val customerEmail: String?,
    @SerializedName("service")       val service: String?,
    @SerializedName("notes")         val notes: String?,
)

/** Confirmation returned on successful reservation. */
data class BookingConfirmation(
    @SerializedName("appointment_id") val appointmentId: Long?,
    @SerializedName("slot_id")        val slotId: String,
    @SerializedName("start_time")     val startTime: String,
    @SerializedName("confirmation_code") val confirmationCode: String?,
    @SerializedName("message")        val message: String?,
)
