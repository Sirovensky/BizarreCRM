package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.PublicTicketData
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.Path

/**
 * §55 — Public tracking portal API.
 *
 * No authentication required: these endpoints are intentionally unauthenticated
 * so customers can check repair status without an account. The server gates access
 * with a per-ticket [tracking_token] (32-char random hex, min-entropy enforced
 * server-side at MIN_TRACKING_TOKEN_LEN = 32).
 *
 * Server routes (tracking.routes.ts):
 *   GET /api/v1/track/portal/:orderId    — full portal data (status, devices, history)
 *   GET /api/v1/track/token/:token       — direct look-up by tracking token
 *
 * Both are 404-tolerant — callers must handle null data gracefully.
 *
 * Token is supplied in `Authorization: Bearer <token>` per SEC-H27.
 * The deprecated `?token=` query-param path is intentionally NOT used here
 * since this is a new Android client and should always use the header path.
 */
interface PublicTrackingApi {

    /**
     * Fetch full customer-visible portal data for a ticket identified by
     * [orderId] (e.g. "T-0042"). Requires [trackingToken] in the
     * `Authorization: Bearer` header.
     *
     * Returns [PublicTicketData] on success. 404 when token/orderId mismatch.
     * 429 when the server rate-limits the IP.
     */
    @GET("track/portal/{orderId}")
    suspend fun getPortalTicket(
        @Path("orderId") orderId: String,
        @Header("Authorization") authorization: String,
    ): ApiResponse<PublicTicketData>

    /**
     * Fetch ticket data by bare tracking token (used when the deep-link carries
     * only the token and no orderId — e.g. a QR code pointing to
     * `bizarrecrm://track/token/<token>`).
     *
     * 404 when the token does not match any active ticket.
     */
    @GET("track/token/{token}")
    suspend fun getTicketByToken(
        @Path("token") token: String,
    ): ApiResponse<PublicTicketData>
}
