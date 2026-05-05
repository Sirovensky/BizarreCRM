package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.SignedWaiverListData
import com.bizarreelectronics.crm.data.remote.dto.SubmitSignatureData
import com.bizarreelectronics.crm.data.remote.dto.SubmitSignatureRequest
import com.bizarreelectronics.crm.data.remote.dto.WaiverTemplateListData
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path

/**
 * WaiverApi — §4.14 L780-L786 (plan:L780-L786)
 *
 * Retrofit interface for the waiver + signature endpoints.
 *
 * ## 404 contract
 *
 * All three endpoints may return 404 when the server does not yet expose the
 * waiver feature. Callers MUST catch [retrofit2.HttpException] with code 404
 * and treat it as "feature disabled" — hide the Waivers action in
 * [TicketDetailScreen] and return empty lists from the repository layer.
 *
 * ## Endpoints
 *
 * ```
 * GET  /tickets/:id/waivers/required  — applicable templates for this ticket context
 * GET  /tickets/:id/waivers            — list of already-signed waivers for this ticket
 * POST /tickets/:id/signatures         — submit a completed signature
 * ```
 *
 * The signed PDF is generated server-side; Android only POSTs the signature
 * base64 + audit metadata and lets the server assemble and email the PDF (L783).
 */
interface WaiverApi {

    /**
     * Fetch the list of waiver templates required for this ticket (L780).
     *
     * The server decides which templates apply based on ticket context (drop-off,
     * loaner device assigned, TCPA marketing consent status, etc.). Android does
     * not hardcode which templates to show — it renders whatever the server returns.
     *
     * Returns 404 when the waiver feature is not enabled; caller hides the UI entry point.
     *
     * @param ticketId Server ticket ID.
     * @return List of [WaiverTemplateDto] ordered by server preference.
     */
    @GET("tickets/{id}/waivers/required")
    suspend fun getRequiredTemplates(
        @Path("id") ticketId: Long,
    ): ApiResponse<WaiverTemplateListData>

    /**
     * Fetch all signed waivers for this ticket (L782).
     *
     * Used by [WaiverListScreen] to display status (Signed / Pending) for each
     * required template. Returns 404 when the feature is disabled.
     *
     * @param ticketId Server ticket ID.
     * @return List of [SignedWaiverDto].
     */
    @GET("tickets/{id}/waivers")
    suspend fun getSignedWaivers(
        @Path("id") ticketId: Long,
    ): ApiResponse<SignedWaiverListData>

    /**
     * Submit a completed signature (L784).
     *
     * The request body includes the template ID + version, signer's printed name,
     * the signature as a base64-encoded PNG, and a [SignatureAuditDto] containing
     * the device fingerprint and actor user ID (L785).
     *
     * The signature bitmap is ALSO enqueued for multipart upload via
     * [MultipartUploadWorker] after this call succeeds — the server may store
     * the base64 inline or prefer the multipart depending on its implementation.
     *
     * **Never** log the [SubmitSignatureRequest.signatureBase64] field.
     *
     * Returns 404 when the feature is disabled; caller degrades gracefully.
     *
     * @param ticketId Server ticket ID.
     * @param request  Complete signature submission.
     * @return [SubmitSignatureData] with server-assigned ID and optional signature URL.
     */
    @POST("tickets/{id}/signatures")
    suspend fun submitSignature(
        @Path("id") ticketId: Long,
        @Body request: SubmitSignatureRequest,
    ): ApiResponse<SubmitSignatureData>
}
