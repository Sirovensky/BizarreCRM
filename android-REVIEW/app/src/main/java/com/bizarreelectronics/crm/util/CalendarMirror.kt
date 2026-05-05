package com.bizarreelectronics.crm.util

import android.content.Context
import android.content.Intent
import android.provider.CalendarContract
import com.bizarreelectronics.crm.data.remote.dto.AppointmentItem
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter

/**
 * CalendarMirror (L1437) — launches the system calendar app via [Intent.ACTION_INSERT]
 * with appointment data pre-filled.
 *
 * Uses an Intent-based approach (CalendarContract.Events.CONTENT_URI as target),
 * which lets the user's installed calendar app handle insertion. No
 * READ_CALENDAR / WRITE_CALENDAR runtime permission is required because the
 * user explicitly chooses what to do in the calendar app.
 *
 * The intent extras are the CalendarContract column names documented at:
 * https://developer.android.com/reference/android/provider/CalendarContract.Events
 */
object CalendarMirror {

    /**
     * Launches the calendar app with [appointment] data pre-filled.
     * No-op if the device has no calendar app installed.
     *
     * @param context  A valid [Context]; Activity context preferred so the
     *                 system can choose the correct task stack.
     * @param appointment  The appointment to mirror into the calendar.
     */
    fun addToCalendar(context: Context, appointment: AppointmentItem) {
        val beginMs = parseEpochMs(appointment.startTime) ?: return
        val endMs = parseEpochMs(appointment.endTime)
            ?: appointment.durationMinutes?.let { beginMs + it * 60_000L }
            ?: (beginMs + 60 * 60_000L)  // default: 1 hour

        val title = buildTitle(appointment)
        val description = buildDescription(appointment)

        val intent = Intent(Intent.ACTION_INSERT, CalendarContract.Events.CONTENT_URI).apply {
            putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, beginMs)
            putExtra(CalendarContract.EXTRA_EVENT_END_TIME, endMs)
            putExtra(CalendarContract.Events.TITLE, title)
            if (!appointment.location.isNullOrBlank()) {
                putExtra(CalendarContract.Events.EVENT_LOCATION, appointment.location)
            }
            if (description.isNotBlank()) {
                putExtra(CalendarContract.Events.DESCRIPTION, description)
            }
            // Allow all-day flag when duration spans a full day
            putExtra(CalendarContract.EXTRA_EVENT_ALL_DAY, false)
        }

        // Guard: only fire if a calendar app can handle it
        if (intent.resolveActivity(context.packageManager) != null) {
            context.startActivity(intent)
        }
    }

    // ---------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------

    private fun parseEpochMs(iso: String?): Long? {
        if (iso.isNullOrBlank()) return null
        return runCatching {
            ZonedDateTime.parse(iso, DateTimeFormatter.ISO_DATE_TIME).toInstant().toEpochMilli()
        }.getOrElse {
            runCatching {
                // Try local datetime without zone; assume device local zone
                val ldt = java.time.LocalDateTime.parse(iso)
                ldt.atZone(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli()
            }.getOrNull()
        }
    }

    private fun buildTitle(appointment: AppointmentItem): String {
        val parts = listOfNotNull(
            appointment.type?.takeIf { it.isNotBlank() },
            appointment.customerName?.takeIf { it.isNotBlank() },
        )
        return if (parts.isNotEmpty()) parts.joinToString(" — ")
        else appointment.title?.ifBlank { null } ?: "Appointment"
    }

    private fun buildDescription(appointment: AppointmentItem): String {
        return buildString {
            appointment.customerName?.let { appendLine("Customer: $it") }
            appointment.employeeName?.let { appendLine("Technician: $it") }
            appointment.durationMinutes?.let { appendLine("Duration: ${it}min") }
            appointment.notes?.takeIf { it.isNotBlank() }?.let { appendLine(it) }
        }.trimEnd()
    }
}
