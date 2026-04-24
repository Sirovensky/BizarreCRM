package com.bizarreelectronics.crm.data.remote.dto

import com.google.gson.annotations.SerializedName

data class LoginRequest(
    val username: String,
    val password: String
)

data class LoginResponse(
    @SerializedName("challengeToken")
    val challengeToken: String?,
    @SerializedName("requiresPasswordSetup")
    val requiresPasswordSetup: Boolean? = false,
    @SerializedName("totpEnabled")
    val totpEnabled: Boolean? = false,
    @SerializedName("requires2faSetup")
    val requires2faSetup: Boolean? = false,
    @SerializedName("qrCode")
    val qrCode: String? = null,
    @SerializedName("qr")
    val qr: String? = null,
)

/**
 * §2.4 L298 — Response from POST /auth/login/2fa-setup.
 *
 * Server returns:
 *   - qr            : data:image/png;base64,... for display in an ImageView
 *   - secret        : raw base32 TOTP secret (for manual entry / copyable text)
 *   - manualEntry   : human-readable formatted key (e.g. "ABCD EFGH …")
 *   - challengeToken: fresh (or same) challenge token to use in the verify call
 */
data class TwoFaSetupResponse(
    @SerializedName("qr")
    val qr: String? = null,
    @SerializedName("qrCode")
    val qrCode: String? = null,
    @SerializedName("secret")
    val secret: String? = null,
    @SerializedName("manualEntry")
    val manualEntry: String? = null,
    @SerializedName("challengeToken")
    val challengeToken: String? = null,
)

data class TwoFactorRequest(
    val challengeToken: String,
    val code: String
)

data class TwoFactorResponse(
    @SerializedName("accessToken")
    val accessToken: String,
    @SerializedName("refreshToken")
    val refreshToken: String?,
    val user: UserDto,
    val backupCodes: List<String>?,
)

data class SetPasswordRequest(
    val challengeToken: String,
    val password: String
)

data class RefreshResponse(
    @SerializedName("accessToken")
    val accessToken: String
)

data class UserDto(
    val id: Long,
    val username: String,
    @SerializedName("first_name")
    val firstName: String?,
    @SerializedName("last_name")
    val lastName: String?,
    val email: String?,
    val role: String,
    @SerializedName("avatar_url")
    val avatarUrl: String?
)

// RegisterDeviceRequest removed — /auth/register-device does not exist on server

// §2.8 — Password reset + backup-code recovery DTOs

data class ForgotPasswordRequest(
    val email: String,
)

data class ResetPasswordRequest(
    val token: String,
    val password: String,
)

/** §2.8 backup-code recovery — server takes email + backupCode + newPassword */
data class BackupCodeRecoveryRequest(
    val email: String,
    @SerializedName("backupCode")
    val backupCode: String,
    @SerializedName("newPassword")
    val newPassword: String,
)

/** Generic server message wrapper used by forgot-password, reset-password, and recovery */
data class MessageResponse(
    val message: String?,
)

// §2.5 — Switch user (shared device) DTOs.
// Endpoint: POST /auth/switch-user
// Request body: { pin }  — SECURITY: pin is NEVER logged.
// Response data: { accessToken, user }

data class SwitchUserRequest(
    @SerializedName("pin") val pin: String,
)

data class SwitchUserResponse(
    @SerializedName("accessToken") val accessToken: String,
    @SerializedName("user") val user: UserDto,
)

/**
 * §2.7-L327 — Response from POST /api/v1/signup (tenant / shop creation).
 *
 * Android-side contract (server-side TODO: SIGNUP-AUTO-LOGIN-TOKENS):
 *   - [accessToken]  : when present, the server issued a valid session immediately
 *                      after creating the shop. Android MUST store it via
 *                      `AuthPreferences.saveUser()` and skip the login step entirely.
 *   - [refreshToken] : optional companion token; stored when present.
 *   - [user]         : populated alongside [accessToken]; null when the server does not
 *                      auto-issue a session (legacy / not-yet-deployed flag).
 *   - [message]      : human-readable confirmation text; always present on success.
 *
 * Fallback: when [accessToken] is null (server predates this feature or the feature
 * flag is off), Android falls back to `POST /auth/login` with the registered
 * credentials and pre-fills username from `admin_email` / `username`.
 */
data class SetupResponse(
    @SerializedName("accessToken")
    val accessToken: String? = null,
    @SerializedName("refreshToken")
    val refreshToken: String? = null,
    @SerializedName("user")
    val user: UserDto? = null,
    @SerializedName("message")
    val message: String? = null,
)

/**
 * §2.1 — Response from GET /auth/setup-status.
 *
 * Server returns exactly two fields:
 *   - needsSetup:    true when no active users exist (first-run wizard required)
 *   - isMultiTenant: true when the server is running in SaaS/multi-tenant mode
 *
 * Verified against packages/server/src/routes/auth.routes.ts line 435-445.
 */
data class SetupStatusResponse(
    @SerializedName("needsSetup")
    val needsSetup: Boolean,
    @SerializedName("isMultiTenant")
    val isMultiTenant: Boolean? = null,
)

/**
 * §2.19 L427 — Response from POST /auth/account/2fa/recovery-codes/regenerate.
 *
 * Server returns the freshly-generated recovery codes, when they were generated,
 * and optionally how many remain (for display in the Idle state before regenerate).
 *
 * 404 → server predates this endpoint; ViewModel maps to NotSupported state.
 */
data class RecoveryCodesResponse(
    @SerializedName("codes")
    val codes: List<String>,
    @SerializedName("generatedAt")
    val generatedAt: String? = null,
    @SerializedName("remaining")
    val remaining: Int? = null,
)

/**
 * §2.18 L418 — A single 2FA factor as returned by GET /auth/2fa/factors.
 *
 * Supported [type] values: "totp", "sms", "hardware_key", "passkey".
 * [isPrimary] marks the factor used by default during login verification.
 * [enrolledAt] is an ISO-8601 string (may be null for legacy records).
 * [label] is a human-readable description set at enroll time (e.g. phone number for SMS).
 *
 * 404 from the endpoint means the server predates this feature; ViewModel maps to NotSupported.
 */
data class TwoFactorFactorDto(
    @SerializedName("type")
    val type: String,
    @SerializedName("enrolledAt")
    val enrolledAt: String? = null,
    @SerializedName("label")
    val label: String? = null,
    @SerializedName("isPrimary")
    val isPrimary: Boolean = false,
)

/**
 * §2.20 L442 — SSO discovery and token-exchange DTOs.
 *
 * SAML vs OIDC note: the distinction is handled entirely on the server.
 * Android sees only the [authUrl] (the IdP redirect URL) and exchanges the
 * resulting authorization code via [SsoTokenExchangeRequest]. Whether the
 * server validates a SAML assertion or an OIDC id_token behind that is
 * deferred to server-side implementation.
 *
 * L444 — Certificate rotation: TODO follow-up. When the IdP rotates its
 * signing certificate the server must re-fetch OIDC metadata / SAML metadata
 * and update its trust store. Android is unaffected (it only touches tokens,
 * never raw certs). Future tracking: server-side background task that polls
 * IdP metadata every 24 h and logs a WARN when the cert changes.
 */

/**
 * A single SSO provider entry from GET /auth/sso/providers.
 *
 * [id]      — opaque provider identifier sent back in [SsoTokenExchangeRequest.provider].
 * [name]    — display name shown to the user in the provider-picker sheet (e.g. "Google Workspace").
 * [authUrl] — the IdP authorization URL that Chrome Custom Tabs must navigate to.
 * [iconUrl] — optional URL for the provider's branded icon; UI falls back to a generic icon.
 */
data class SsoProvider(
    @SerializedName("id")      val id: String,
    @SerializedName("name")    val name: String,
    @SerializedName("authUrl") val authUrl: String,
    @SerializedName("iconUrl") val iconUrl: String? = null,
)

/**
 * Response from GET /auth/sso/providers.
 *
 * 404 → this tenant has not configured any SSO providers.
 * The ViewModel maps 404 to an empty list and hides the "Sign in with SSO" button.
 */
data class SsoDiscoveryResponse(
    @SerializedName("providers")
    val providers: List<SsoProvider>,
)

/**
 * Body for POST /auth/sso/token-exchange.
 *
 * Sent after the SSO callback delivers `code` + `state` via the
 * `bizarrecrm://sso/callback` deep link. The server verifies [state] against
 * its own session-bound value before exchanging [code] for tokens.
 *
 * SECURITY: [state] mismatch (CSRF check) results in a 400; the ViewModel
 * surfaces "Sign-in link mismatch. Try again." to the user.
 */
data class SsoTokenExchangeRequest(
    @SerializedName("provider") val provider: String,
    @SerializedName("code")     val code: String,
    @SerializedName("state")    val state: String,
)

/**
 * §2.21 L454 — Magic-link DTOs.
 *
 * POST /auth/magic-link/request — sends a one-time sign-in link to the user's email.
 *   Body: { email }
 *   Response: MessageResponse { message }
 *   404 → tenant has disabled magic-link login; caller hides the button.
 *
 * POST /auth/magic-link/exchange — exchanges the token from the link for session tokens.
 *   Body: { token, deviceFingerprint }
 *   Response: MagicLinkExchangeResponse { accessToken, refreshToken, user,
 *             requires_2fa?, expiresAt? }
 *   Same-device (fingerprint matches) → tokens issued immediately.
 *   Different device → requires_2fa = true; caller pushes TwoFaVerify step.
 *   404 → tenant has disabled magic-link login.
 */
data class MagicLinkRequest(
    @SerializedName("email") val email: String,
)

data class MagicLinkTokenExchange(
    @SerializedName("token")             val token: String,
    @SerializedName("deviceFingerprint") val deviceFingerprint: String,
)

/**
 * Response from POST /auth/magic-link/exchange.
 *
 * [accessToken] + [refreshToken] + [user] are present when the exchange is complete
 * (same-device or server skips 2FA for magic links).
 *
 * [requires2fa] = true when the server wants a second factor before issuing tokens
 * (different-device scenario). In this case the client must push [SetupStep.TWO_FA_VERIFY]
 * with [challengeToken] forwarded as the challenge.
 *
 * [expiresAt] — ISO-8601 string; when present the exchange UI shows a countdown.
 * [tenantName] — optional tenant display name for the phishing-defense preview card.
 */
data class MagicLinkExchangeResponse(
    @SerializedName("accessToken")   val accessToken: String? = null,
    @SerializedName("refreshToken")  val refreshToken: String? = null,
    @SerializedName("user")          val user: UserDto? = null,
    @SerializedName("requires_2fa")  val requires2fa: Boolean = false,
    @SerializedName("challengeToken") val challengeToken: String? = null,
    @SerializedName("expires_at")    val expiresAt: String? = null,
    @SerializedName("tenantName")    val tenantName: String? = null,
)

// ── §2.15 L387-L388 — Forgot-PIN email reset DTOs ──────────────────────────

/**
 * Body for POST /auth/forgot-pin/request.
 *
 * The server dispatches a PIN-reset link to [email]. 404 → feature disabled
 * on this self-hosted tenant (email server may be absent); callers surface the
 * admin-fallback message rather than an error.
 *
 * KDoc: email server may be absent on self-hosted tenants — tolerate 404 gracefully.
 */
data class ForgotPinRequest(
    @SerializedName("email") val email: String,
)

/**
 * Body for POST /auth/forgot-pin/confirm.
 *
 * [token] — opaque reset token from the link delivered to the user's inbox.
 * [newPin] — the replacement PIN chosen by the user (4-6 digits, validated
 *            client-side against PinBlocklist before this call is made).
 *
 * SECURITY: [newPin] is NEVER logged.
 */
data class ForgotPinConfirm(
    @SerializedName("token") val token: String,
    @SerializedName("newPin") val newPin: String,
)

/**
 * §2.15 L388 — manager-triggered reset-link dispatch.
 *
 * Body for POST /employees/:id/forgot-pin/trigger.
 * No fields required — the server reads the employee ID from the path and
 * uses the employee's stored email. Empty body keeps Retrofit happy.
 */
class ForgotPinTriggerRequest

/**
 * §2.21 L454 — Stub field added to the tenant-info response.
 *
 * When GET /tenants/me returns [magicLinksEnabled] = false the "Email me a link"
 * button is hidden on the credentials step. The field defaults to true so that
 * self-hosted servers that predate this field still show the button (opt-out model).
 *
 * §2.22 — [passkeyEnabled] = true when the tenant has passkeys enabled on the server.
 * The "Use passkey" button on the credentials step is shown only when this is true.
 * Defaults to false (opt-in model) so servers that predate this field hide the button.
 *
 * Reuses the existing [TenantsApi] / [TenantSupportDto] path; this is a separate
 * DTO fetched from GET /tenants/me (not /tenants/me/support-contact).
 */
data class TenantMeResponse(
    @SerializedName("magic_links_enabled") val magicLinksEnabled: Boolean = true,
    @SerializedName("passkey_enabled") val passkeyEnabled: Boolean = false,
)

// ── §2.22 FIDO2 / WebAuthn DTOs ────────────────────────────────────────────

/**
 * WebAuthn L2 — PublicKeyCredentialCreationOptions.
 *
 * Shape matches the JSON produced by most WebAuthn server libraries (simplewebauthn,
 * fido2-lib, etc.) and is passed directly as the `requestJson` argument to
 * CreatePublicKeyCredentialRequest.
 *
 * [challengeJson] is the raw JSON string from POST /auth/passkey/register/begin;
 * PasskeyManager passes it as-is to CredentialManager — no manual parsing needed.
 */
data class PasskeyRegisterBeginResponse(
    /**
     * Raw WebAuthn PublicKeyCredentialCreationOptions JSON.
     * Contains `challenge`, `rp`, `user`, `pubKeyCredParams`, `timeout`,
     * `attestation`, and `excludeCredentials` per the WebAuthn L2 spec.
     */
    @SerializedName("challengeJson") val challengeJson: String,
)

/**
 * WebAuthn L2 — AuthenticatorAttestationResponse.
 *
 * Sent to POST /auth/passkey/register/finish after the system credential sheet
 * resolves. The [responseJson] is the raw JSON from
 * CreatePublicKeyCredentialResponse.registrationResponseJson or
 * PublicKeyCredential.authenticationResponseJson depending on the credential type.
 */
data class PasskeyRegisterFinishRequest(
    @SerializedName("responseJson") val responseJson: String,
)

/**
 * WebAuthn L2 — PublicKeyCredentialRequestOptions.
 *
 * Shape matches the JSON from POST /auth/passkey/login/begin.
 * Passed as the `requestJson` argument to GetPublicKeyCredentialOption.
 */
data class PasskeyLoginBeginResponse(
    /**
     * Raw WebAuthn PublicKeyCredentialRequestOptions JSON.
     * Contains `challenge`, `timeout`, `rpId`, `allowCredentials`, and
     * `userVerification` per the WebAuthn L2 spec.
     */
    @SerializedName("challengeJson") val challengeJson: String,
)

/**
 * Sent to POST /auth/passkey/login/finish after PasskeyManager.signInWithPasskey resolves.
 *
 * [responseJson] is the raw JSON from GetCredentialResponse (the assertion response).
 * The server validates the signature and issues { accessToken, refreshToken, user }.
 */
data class PasskeyLoginFinishRequest(
    @SerializedName("responseJson") val responseJson: String,
)

/**
 * A single enrolled passkey as returned by GET /auth/passkey/list.
 *
 * [id]         — opaque credential ID; used by DELETE /auth/passkey/{id}.
 * [deviceName] — human-readable label set at enrollment (e.g. "Pixel 8 Pro").
 * [createdAt]  — ISO-8601 creation timestamp (may be null for older records).
 */
data class PasskeyCredentialInfo(
    @SerializedName("id") val id: String,
    @SerializedName("deviceName") val deviceName: String = "",
    @SerializedName("createdAt") val createdAt: String? = null,
)

/**
 * §2.11 — Active session as returned by GET /auth/sessions.
 *
 * Fields mirror the server's session record. [current] is true for the
 * session associated with the current access token — the revoke button
 * is disabled for that row to avoid self-lockout.
 *
 * 404 from the endpoint means the server predates this feature; the
 * ViewModel maps it to an empty list with a footer note.
 */
data class ActiveSessionDto(
    @SerializedName("id")
    val id: String,
    @SerializedName("device")
    val device: String? = null,
    @SerializedName("ip")
    val ip: String? = null,
    @SerializedName("userAgent")
    val userAgent: String? = null,
    @SerializedName("createdAt")
    val createdAt: String? = null,
    @SerializedName("lastSeenAt")
    val lastSeenAt: String? = null,
    @SerializedName("current")
    val current: Boolean = false,
)
