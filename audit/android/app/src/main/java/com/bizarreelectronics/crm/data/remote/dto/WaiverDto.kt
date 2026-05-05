package com.bizarreelectronics.crm.data.remote.dto

import com.google.gson.annotations.SerializedName

/**
 * WaiverDto — §4.14 L780-L786 (plan:L780-L786)
 *
 * Data transfer objects for the waiver + signature system. Templates are
 * server-managed; Android fetches and renders them. No hardcoded waiver
 * content exists on the client side.
 *
 * Template types:
 *  - `dropoff`   — standard drop-off liability waiver.
 *  - `loaner`    — loaner device agreement (§43).
 *  - `marketing` — TCPA SMS/email marketing opt-in.
 *  - `other`     — any other template type.
 */

// ─── Template ────────────────────────────────────────────────────────────────

/**
 * Server-managed waiver template.
 *
 * @param id      Stable template identifier (persisted in [AppPreferences.acceptedWaiverVersions]).
 * @param version Monotonically increasing version counter. Android compares this against
 *                the locally stored accepted version to detect re-sign requirements (L786).
 * @param title   Short display title shown in the sheet header.
 * @param body    Markdown body rendered via [MarkdownLiteParser]. Never hardcoded on client.
 * @param type    Context filter: `dropoff | loaner | marketing | other`.
 */
data class WaiverTemplateDto(
    val id: String,
    val version: Int,
    val title: String,
    val body: String,
    val type: String,
)

// ─── Audit ───────────────────────────────────────────────────────────────────

/**
 * Audit metadata attached to every signature submission (L785).
 *
 * Included in the POST body so the server can log the full audit trail
 * without a separate round-trip.
 *
 * @param timestamp         ISO-8601 timestamp of the signing event (client clock).
 * @param ip                Optional client IP included when available.
 * @param deviceFingerprint SHA-256 fingerprint from [DeviceFingerprint.get].
 * @param actorUserId       ID of the logged-in CRM user who collected the signature.
 */
data class SignatureAuditDto(
    val timestamp: String,
    val ip: String? = null,
    @SerializedName("device_fingerprint")
    val deviceFingerprint: String,
    @SerializedName("actor_user_id")
    val actorUserId: Long,
)

// ─── Signed waiver ───────────────────────────────────────────────────────────

/**
 * A completed waiver record returned by `GET /tickets/:id/waivers` (L782).
 *
 * @param id           Server-assigned signed-waiver ID.
 * @param templateId   References [WaiverTemplateDto.id].
 * @param version      Template version that was signed.
 * @param customerId   Customer who signed.
 * @param signerName   Printed name provided by the signer.
 * @param signatureUrl URL to the stored signature image (server-side PDF included).
 * @param signedAt     ISO-8601 timestamp from the server.
 * @param audit        Audit record embedded in the original submission.
 */
data class SignedWaiverDto(
    val id: Long,
    @SerializedName("template_id")
    val templateId: String,
    val version: Int,
    @SerializedName("customer_id")
    val customerId: Long?,
    @SerializedName("signer_name")
    val signerName: String,
    @SerializedName("signature_url")
    val signatureUrl: String?,
    @SerializedName("signed_at")
    val signedAt: String?,
    val audit: SignatureAuditDto?,
)

// ─── Request bodies ───────────────────────────────────────────────────────────

/**
 * Request body for `POST /tickets/:id/signatures` (L784).
 *
 * The signature bitmap is uploaded separately via [MultipartUploadWorker]
 * after this request succeeds. The base64 field carries a compact representation
 * for servers that store it inline; servers may ignore it if they prefer the
 * multipart upload.
 *
 * **Never** log [signatureBase64] — it contains the signature image bytes.
 *
 * @param templateId     Template being signed.
 * @param version        Version of the template that was displayed to the signer.
 * @param signerName     Printed name from the OutlinedTextField in [WaiverSheet].
 * @param signatureBase64 PNG bitmap encoded as base64 (do NOT log).
 * @param audit          Audit metadata (L785).
 */
data class SubmitSignatureRequest(
    @SerializedName("template_id")
    val templateId: String,
    val version: Int,
    @SerializedName("signer_name")
    val signerName: String,
    @SerializedName("signature_base64")
    val signatureBase64: String,
    val audit: SignatureAuditDto,
)

// ─── List wrappers ────────────────────────────────────────────────────────────

/** `GET /tickets/:id/waivers/required` response wrapper. */
data class WaiverTemplateListData(
    val templates: List<WaiverTemplateDto>,
)

/** `GET /tickets/:id/waivers` response wrapper. */
data class SignedWaiverListData(
    val waivers: List<SignedWaiverDto>,
)

/** `POST /tickets/:id/signatures` response wrapper. */
data class SubmitSignatureData(
    val id: Long?,
    @SerializedName("signature_url")
    val signatureUrl: String?,
)
