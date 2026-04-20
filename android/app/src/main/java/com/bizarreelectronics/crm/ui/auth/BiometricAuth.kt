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
import javax.inject.Inject
import javax.inject.Singleton

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
     * authenticates, [onError] with a human-readable message otherwise.
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
        onError: (String) -> Unit,
    ) {
        val executor = ContextCompat.getMainExecutor(activity)
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                onSuccess()
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                // Treat user cancellation as a soft error — the UI layer can
                // decide whether to exit the app or fall back to password.
                onError(errString.toString())
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
}
