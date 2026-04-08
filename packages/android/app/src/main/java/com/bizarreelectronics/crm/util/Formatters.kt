package com.bizarreelectronics.crm.util

import java.text.NumberFormat
import java.time.Duration
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale

object PhoneFormatter {
    fun format(phone: String?): String {
        if (phone.isNullOrBlank()) return ""
        val digits = phone.replace(Regex("[^0-9]"), "")
        return when {
            digits.length == 10 -> "(${digits.substring(0, 3)}) ${digits.substring(3, 6)}-${digits.substring(6)}"
            digits.length == 11 && digits.startsWith("1") -> "(${digits.substring(1, 4)}) ${digits.substring(4, 7)}-${digits.substring(7)}"
            else -> phone
        }
    }

    fun normalize(phone: String?): String {
        if (phone.isNullOrBlank()) return ""
        val digits = phone.replace(Regex("[^0-9]"), "")
        return if (digits.length == 11 && digits.startsWith("1")) digits.substring(1) else digits
    }
}

object CurrencyFormatter {
    private val format = NumberFormat.getCurrencyInstance(Locale.US)

    fun format(amount: Double): String = format.format(amount)
    fun formatShort(amount: Double): String = "$${String.format("%.2f", amount)}"
}

object DateFormatter {
    private val isoParser = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")
    private val isoParserT = DateTimeFormatter.ISO_LOCAL_DATE_TIME // handles "2026-04-04T17:30:00"

    private fun parseDateTime(iso: String): LocalDateTime {
        // Try space-separated first (server default), then T-separated (ISO standard)
        return try {
            LocalDateTime.parse(iso, isoParser)
        } catch (_: Exception) {
            LocalDateTime.parse(iso.take(19), isoParserT)
        }
    }
    private val displayDate = DateTimeFormatter.ofPattern("MMM d, yyyy")
    private val displayDateTime = DateTimeFormatter.ofPattern("MMM d, h:mm a")
    private val displayTime = DateTimeFormatter.ofPattern("h:mm a")

    fun formatDate(iso: String?): String {
        if (iso.isNullOrBlank()) return ""
        return try {
            parseDateTime(iso).format(displayDate)
        } catch (_: Exception) {
            try {
                LocalDate.parse(iso.take(10)).format(displayDate)
            } catch (_: Exception) {
                iso
            }
        }
    }

    fun formatDateTime(iso: String?): String {
        if (iso.isNullOrBlank()) return ""
        return try {
            parseDateTime(iso).format(displayDateTime)
        } catch (_: Exception) {
            iso
        }
    }

    fun formatRelative(iso: String?): String {
        if (iso.isNullOrBlank()) return ""
        return try {
            val dt = parseDateTime(iso)
            val now = LocalDateTime.now()
            val minutes = ChronoUnit.MINUTES.between(dt, now)
            val hours = ChronoUnit.HOURS.between(dt, now)
            val days = ChronoUnit.DAYS.between(dt, now)

            when {
                minutes < 1 -> "just now"
                minutes < 60 -> "${minutes}m ago"
                hours < 24 -> "${hours}h ago"
                days < 7 -> "${days}d ago"
                else -> dt.format(displayDate)
            }
        } catch (_: Exception) {
            iso
        }
    }
}
