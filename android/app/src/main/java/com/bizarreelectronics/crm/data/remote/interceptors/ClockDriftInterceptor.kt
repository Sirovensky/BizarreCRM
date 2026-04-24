package com.bizarreelectronics.crm.data.remote.interceptors

import com.bizarreelectronics.crm.util.ClockDrift
import okhttp3.Interceptor
import okhttp3.Response
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import javax.inject.Inject
import javax.inject.Singleton

/**
 * OkHttp interceptor that reads the HTTP `Date` response header and forwards
 * the parsed server time to [ClockDrift] so it can track the offset between
 * the device clock and the CRM server clock.
 *
 * Design decisions:
 * - Completely silent on any parse failure — a missing or malformed `Date`
 *   header must never crash the app or prevent the response from reaching
 *   the caller.
 * - The [SimpleDateFormat] is created per-call (not shared as a field) to
 *   avoid the well-known thread-safety issue with [SimpleDateFormat] when
 *   multiple OkHttp threads call the interceptor concurrently.
 * - Only response headers are inspected; the request is never modified.
 *
 * HTTP date format per RFC 7231 §7.1.1.1:
 *   `Sun, 06 Nov 1994 08:49:37 GMT`
 */
@Singleton
class ClockDriftInterceptor @Inject constructor(
    private val clockDrift: ClockDrift,
) : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        val response = chain.proceed(chain.request())
        parseServerDate(response.header(HEADER_DATE))?.let { serverEpochMs ->
            clockDrift.recordServerDate(serverEpochMs)
        }
        return response
    }

    /**
     * Parses an HTTP-date string (RFC 7231 §7.1.1.1 IMF-fixdate) and returns
     * the epoch milliseconds, or null if the string is absent, blank, or
     * unparseable.
     *
     * A new [SimpleDateFormat] is constructed each invocation to ensure
     * thread safety under concurrent OkHttp dispatcher threads.
     */
    private fun parseServerDate(dateHeader: String?): Long? {
        if (dateHeader.isNullOrBlank()) return null
        return try {
            val sdf = SimpleDateFormat(HTTP_DATE_FORMAT, Locale.US).apply {
                timeZone = TimeZone.getTimeZone("GMT")
            }
            sdf.parse(dateHeader)?.time
        } catch (_: Exception) {
            // Malformed Date header — silently ignore, do not update drift.
            null
        }
    }

    companion object {
        private const val HEADER_DATE = "Date"

        /**
         * RFC 7231 IMF-fixdate: `EEE, dd MMM yyyy HH:mm:ss z`
         * Example: `Sun, 06 Nov 1994 08:49:37 GMT`
         */
        private const val HTTP_DATE_FORMAT = "EEE, dd MMM yyyy HH:mm:ss z"
    }
}
