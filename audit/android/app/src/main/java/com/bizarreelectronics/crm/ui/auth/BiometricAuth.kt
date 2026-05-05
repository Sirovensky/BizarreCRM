package com.bizarreelectronics.crm.ui.auth

// Biometric dependency is wired in app/build.gradle.kts:
//   implementation("androidx.biometric:biometric:1.2.0-alpha05")
// USE_BIOMETRIC permission is declared in AndroidManifest.xml.

import android.content.Context
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricManager.Authenticators.DEVICE_CREDENTIAL
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import kotlinx.coroutines.suspendCancellableCoroutine
import javax.crypto.Cipher
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume

/**
 * Biometric quick-unlock helper. Wraps AndroidX BiometricPrompt so the CRM can
 * require a fingerprint / face scan before resuming the app from cold start
 * or from the recents screen.
 *
 * Design decisions:
 *  - BIOMETRIC_STRONG OR DEVICE_CREDENTIAL — allows falling back to PIN /
 *    pattern / password on devices that do not have a strong biometric sensor.
 *  - Always checks [canAuthenticate] before showing the prompt so the caller
 *    can silently skip the gate on devices that have no enrolled biometric.
 *  - Feature is OFF by default and must be enabled in Settings. The caller
 *    is responsible for reading the preference and deciding whether to call
 *    [showPrompt].
 *  - [encryptWithBiometric] / [decryptWithBiometric] use a CryptoObject-bound
 *    prompt so that Keystore key usage is hardware-attested to a live biometric
 *    event.  The returned [Cipher] is unwrapped from the AuthenticationResult.
 *
 * Injected as a @Singleton via Hilt so the existing DI graph can use it.
 */
@Singleton
class BiometricAuth @Inject constructor() {

    /**
     * Returns true if the device has enrolled biometrics or a device
     * credential set up and is therefore capable of showing the prompt.
     * Returning false here is NOT an error — it just means the gate should
     * be skipped for this device.
     */
    fun canAuthenticate(context: Context): Boolean {
        val biometricManager = BiometricManager.from(context)
        val result = biometricManager.canAuthenticate(BIOMETRIC_STRONG or DEVICE_CREDENTIAL)
        return result == BiometricManager.BIOMETRIC_SUCCESS
    }

    /**
     * Shows the system biometric prompt. Runs [onSuccess] if the user
     * authenticates, [onError] with a typed [BiometricFailure] otherwise.
     *
     * Gracefully handles `ERROR_NO_BIOMETRICS` and `ERROR_HW_UNAVAILABLE` by
     * delivering [BiometricFailure.Disabled] instead of a generic error string,
     * allowing callers to silently skip the biometric path without user-visible
     * noise.
     *
     * The callbacks never mutate state themselves — they fire on the main
     * thread so the caller is free to update Compose state, navigate, or
     * show a snackbar without additional context switching.
     */
    fun showPrompt(
        activity: FragmentActivity,
        title: String = "Unlock BizarreCRM",
        subtitle: String = "Use your fingerprint or face to continue",
        onSuccess: () -> Unit,
        onError: (BiometricFailure) -> Unit,
    ) {
        val executor = ContextCompat.getMainExecutor(activity)
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                onSuccess()
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                val failure = when (errorCode) {
                    BiometricPrompt.ERROR_NO_BIOMETRICS,
                    BiometricPrompt.ERROR_HW_UNAVAILABLE,
                    BiometricPrompt.ERROR_HW_NOT_PRESENT,
                    -> BiometricFailure.Disabled

                    BiometricPrompt.ERROR_USER_CANCELED,
                    BiometricPrompt.ERROR_NEGATIVE_BUTTON,
                    -> BiometricFailure.UserCancelled

                    else -> BiometricFailure.SystemError(errorCode, errString.toString())
                }
                onError(failure)
            }

            override fun onAuthenticationFailed() {
                // Fired on a non-matching scan. Intentionally not a hard
                // error — BiometricPrompt keeps the sheet open for retries.
            }
        }
        val prompt = BiometricPrompt(activity, executor, callback)
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setSubtitle(subtitle)
            .setAllowedAuthenticators(BIOMETRIC_STRONG or DEVICE_CREDENTIAL)
            .build()
        prompt.authenticate(info)
    }

    /**
     * Shows a BiometricPrompt with [cipher] (ENCRYPT_MODE) as a [CryptoObject] and returns
     * the authenticated [Cipher] on success, or `null` if the user cancelled or biometry is
     * unavailable. The returned cipher has already been used for one encrypt operation by the
     * OS; pass it directly to [BiometricCredentialStore.store].
     *
     * Coroutine-friendly — suspends until the prompt is dismissed.
     */
    suspend fun encryptWithBiometric(
        activity: FragmentActivity,
        cipher: Cipher,
        title: String = "Save login with biometrics",
        subtitle: String = "Confirm identity to store your credentials securely",
    ): Cipher? = suspendCancellableCoroutine { cont ->
        val executor = ContextCompat.getMainExecutor(activity)
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                cont.resume(result.cryptoObject?.cipher)
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                cont.resume(null)
            }

            override fun onAuthenticationFailed() {
                // Non-matching scan — prompt remains open; no resume yet.
            }
        }
        val prompt = BiometricPrompt(activity, executor, callback)
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setSubtitle(subtitle)
            .setAllowedAuthenticators(BIOMETRIC_STRONG)
            .setNegativeButtonText("Cancel")
            .build()
        prompt.authenticate(info, BiometricPrompt.CryptoObject(cipher))
    }

    /**
     * Shows a BiometricPrompt with [cipher] (DECRYPT_MODE, initialised with [iv]) as a
     * [CryptoObject] and returns the authenticated [Cipher] on success, or `null` on
     * user-cancel / hardware unavailability.
     *
     * Coroutine-friendly — suspends until the prompt is dismissed.
     */
    suspend fun decryptWithBiometric(
        activity: FragmentActivity,
        cipher: Cipher,
        iv: ByteArray,
        title: String = "Sign in with biometrics",
        subtitle: String = "Confirm your identity to retrieve stored credentials",
    ): Cipher? = suspendCancellableCoroutine { cont ->
        val executor = ContextCompat.getMainExecutor(activity)
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                cont.resume(result.cryptoObject?.cipher)
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                cont.resume(null)
            }

            override fun onAuthenticationFailed() {
                // Non-matching scan — prompt remains open.
            }
        }
        val prompt = BiometricPrompt(activity, executor, callback)
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setSubtitle(subtitle)
            .setAllowedAuthenticators(BIOMETRIC_STRONG)
            .setNegativeButtonText("Use password instead")
            .build()
        prompt.authenticate(info, BiometricPrompt.CryptoObject(cipher))
    }
}

/**
 * Typed failure discriminant for [BiometricAuth.showPrompt].
 *
 *  - [Disabled] — hardware missing or no enrolled biometrics. Callers should silently skip
 *    the biometric path and fall back to password entry without displaying an error.
 *  - [UserCancelled] — user tapped Cancel / negative button. Show no banner; let them proceed.
 *  - [SystemError] — unexpected OS error. May be shown to the user as a transient message.
 */
sealed class BiometricFailure {
    data object Disabled : BiometricFailure()
    data object UserCancelled : BiometricFailure()
    data class SystemError(val code: Int, val message: String) : BiometricFailure()
}
