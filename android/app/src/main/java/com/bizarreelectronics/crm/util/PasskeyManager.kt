package com.bizarreelectronics.crm.util

import android.app.Activity
import android.os.Build
import androidx.credentials.CreatePublicKeyCredentialRequest
import androidx.credentials.CreatePublicKeyCredentialResponse
import androidx.credentials.CredentialManager
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetCredentialResponse
import androidx.credentials.GetPublicKeyCredentialOption
import androidx.credentials.exceptions.CreateCredentialCancellationException
import androidx.credentials.exceptions.CreateCredentialException
import androidx.credentials.exceptions.CreateCredentialNoCreateOptionException
import androidx.credentials.exceptions.CreateCredentialUnsupportedException
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.NoCredentialException
import timber.log.Timber

/**
 * §2.22 — PasskeyManager: single entry point for FIDO2 / WebAuthn passkey operations.
 *
 * Wraps [CredentialManager] to provide a clean, typed interface for:
 *  1. Passkey enrollment  — [enrollPasskey]: create flow (register/begin → create → finish).
 *  2. Passkey sign-in     — [signInWithPasskey]: get flow (login/begin → get → finish).
 *
 * ## Hardware-key (§2.23)
 * CredentialManager's FIDO2 implementation transparently supports hardware security keys
 * (e.g. YubiKey via NFC/USB-C) as just another FIDO2 authenticator transport.
 * No additional Android-side code is needed — a hardware key appears in the system
 * credential-picker sheet automatically. KDoc note is sufficient per plan §2.23.
 *
 * ## Cross-device sync (L468)
 * When a passkey is created via CredentialManager it is automatically synced to
 * Google Password Manager (where the user's Google account is set up for sync).
 * No explicit sync code is required on the Android side beyond invoking the creation flow.
 *
 * ## iOS interop (L471)
 * Out of scope for this wave. Passkeys created on Android are stored in the FIDO2
 * credential database; Apple cross-device support is handled at the server RP layer.
 *
 * ## Password breakglass (L468/L469)
 * Password login remains available as a breakglass path at all times.
 * "Remove password" (disabling password entirely) requires a dedicated server endpoint
 * and is deferred as a follow-up. The UI retains the password form on the credentials
 * step; the "Use passkey" button is an additive alternative, not a replacement.
 *
 * ## API level guard
 * CredentialManager requires API 28+. All public methods check
 * [Build.VERSION.SDK_INT] >= 28 before invoking system APIs and return
 * [PasskeyOutcome.Unsupported] on older devices.
 */
object PasskeyManager {

    private const val TAG = "PasskeyManager"

    /**
     * Typed result discriminator for all passkey operations.
     *
     * Callers should `when` on this sealed class to drive UI state:
     *  - [Success]        — operation completed; carry the response object.
     *  - [Cancelled]      — user tapped "Cancel" in the system credential sheet.
     *  - [NoCredentials]  — no matching passkey found on this device for login.
     *  - [Unsupported]    — device API < 28 or CredentialManager unavailable.
     *  - [Error]          — unexpected failure; [message] contains a loggable description.
     */
    sealed class PasskeyOutcome<out T> {
        data class Success<T>(val data: T) : PasskeyOutcome<T>()
        data object Cancelled : PasskeyOutcome<Nothing>()
        data object NoCredentials : PasskeyOutcome<Nothing>()
        data object Unsupported : PasskeyOutcome<Nothing>()
        data class Error(val message: String, val cause: Throwable? = null) : PasskeyOutcome<Nothing>()
    }

    /**
     * Creates a new passkey for the current user.
     *
     * Caller flow:
     *  1. POST /auth/passkey/register/begin → obtain [challengeJson] (WebAuthn
     *     PublicKeyCredentialCreationOptions as a JSON string).
     *  2. Call [enrollPasskey] with that JSON.
     *  3. On [PasskeyOutcome.Success], POST the response to /auth/passkey/register/finish.
     *
     * @param activity  Foreground [Activity] required by CredentialManager to anchor
     *                  the system credential UI.
     * @param challengeJson  WebAuthn PublicKeyCredentialCreationOptions JSON from the server.
     *                       Must include `challenge`, `rp`, `user`, `pubKeyCredParams`.
     * @return [PasskeyOutcome.Success] carrying [CreatePublicKeyCredentialResponse], or a
     *         failure variant.
     */
    suspend fun enrollPasskey(
        activity: Activity,
        challengeJson: String,
    ): PasskeyOutcome<CreatePublicKeyCredentialResponse> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            Timber.tag(TAG).w("Passkey enrollment not supported: API %d < 28", Build.VERSION.SDK_INT)
            return PasskeyOutcome.Unsupported
        }
        return try {
            val credentialManager = CredentialManager.create(activity)
            val request = CreatePublicKeyCredentialRequest(requestJson = challengeJson)
            val response = credentialManager.createCredential(
                context = activity,
                request = request,
            ) as CreatePublicKeyCredentialResponse
            PasskeyOutcome.Success(response)
        } catch (e: CreateCredentialCancellationException) {
            Timber.tag(TAG).d("Passkey enrollment cancelled by user")
            PasskeyOutcome.Cancelled
        } catch (e: CreateCredentialNoCreateOptionException) {
            Timber.tag(TAG).w(e, "No credential create option available")
            PasskeyOutcome.NoCredentials
        } catch (e: CreateCredentialUnsupportedException) {
            Timber.tag(TAG).w(e, "CreateCredential unsupported on this device")
            PasskeyOutcome.Unsupported
        } catch (e: CreateCredentialException) {
            Timber.tag(TAG).e(e, "CreateCredential failed: %s", e.type)
            PasskeyOutcome.Error(message = "Enrollment failed: ${e.type}", cause = e)
        } catch (e: Exception) {
            Timber.tag(TAG).e(e, "Unexpected error during passkey enrollment")
            PasskeyOutcome.Error(message = e.message ?: "Unknown error", cause = e)
        }
    }

    /**
     * Authenticates the user with an existing passkey (or hardware security key).
     *
     * Caller flow:
     *  1. POST /auth/passkey/login/begin → obtain [challengeJson] (WebAuthn
     *     PublicKeyCredentialRequestOptions as a JSON string).
     *  2. Call [signInWithPasskey] with that JSON.
     *  3. On [PasskeyOutcome.Success], POST the response to /auth/passkey/login/finish
     *     which returns { accessToken, refreshToken, user }.
     *
     * ## Hardware key (§2.23)
     * The system credential sheet automatically includes registered hardware security
     * keys (FIDO2 USB-C / NFC). The user taps their key when prompted — no additional
     * Android code path is required.
     *
     * @param activity       Foreground [Activity] for the CredentialManager UI.
     * @param challengeJson  WebAuthn PublicKeyCredentialRequestOptions JSON from the server.
     * @return [PasskeyOutcome.Success] carrying [GetCredentialResponse], or a failure variant.
     */
    suspend fun signInWithPasskey(
        activity: Activity,
        challengeJson: String,
    ): PasskeyOutcome<GetCredentialResponse> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            Timber.tag(TAG).w("Passkey sign-in not supported: API %d < 28", Build.VERSION.SDK_INT)
            return PasskeyOutcome.Unsupported
        }
        return try {
            val credentialManager = CredentialManager.create(activity)
            val option = GetPublicKeyCredentialOption(requestJson = challengeJson)
            val request = GetCredentialRequest(credentialOptions = listOf(option))
            val response = credentialManager.getCredential(
                context = activity,
                request = request,
            )
            PasskeyOutcome.Success(response)
        } catch (e: GetCredentialCancellationException) {
            Timber.tag(TAG).d("Passkey sign-in cancelled by user")
            PasskeyOutcome.Cancelled
        } catch (e: NoCredentialException) {
            Timber.tag(TAG).d("No passkey found on this device")
            PasskeyOutcome.NoCredentials
        } catch (e: GetCredentialException) {
            Timber.tag(TAG).e(e, "GetCredential failed: %s", e.type)
            PasskeyOutcome.Error(message = "Sign-in failed: ${e.type}", cause = e)
        } catch (e: Exception) {
            Timber.tag(TAG).e(e, "Unexpected error during passkey sign-in")
            PasskeyOutcome.Error(message = e.message ?: "Unknown error", cause = e)
        }
    }

    /**
     * Returns true when CredentialManager passkey support is available on this device.
     * Callers use this to show/hide the "Use passkey" button before any network call.
     */
    fun isSupported(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
}
