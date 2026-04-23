package com.bizarreelectronics.crm.util

import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType

/**
 * §2.4 (L302-L303) — Compose-dependent helpers for OTP input fields.
 *
 * Kept in a separate file from [ClipboardUtil] so that ClipboardUtil remains
 * a pure Android (no Compose) utility that can be tested without Compose on
 * the classpath.
 *
 * ### ContentType / autofill semantics
 * `androidx.compose.ui.autofill.ContentType` is declared `internal` in the
 * Compose UI 1.7.x library and therefore cannot be imported from application
 * code. The recommended approach for OTP autofill semantics in this Compose
 * version is to use the `autofillHints` modifier with the Android view-system
 * hint string directly:
 *
 * ```kotlin
 * import android.view.View
 * OutlinedTextField(
 *     modifier = Modifier.semantics {
 *         // Wire up View-level autofill hint so the Android autofill framework
 *         // can fill the field with the incoming SMS OTP.
 *         autofillHints(View.AUTOFILL_HINT_SMS_OTP)
 *     },
 *     keyboardOptions = OtpInput.otpKeyboardOptions(),
 * )
 * ```
 *
 * When Compose upgrades to a version where `ContentType` is public (expected
 * post-1.8), replace the `autofillHints` approach with:
 * ```kotlin
 * Modifier.semantics { contentType = ContentType.SmsOtpCode }
 * ```
 *
 * ### SmsRetriever
 * [smsRetrieverClient] is a stub. The SMS Retriever API requires the
 * `com.google.android.gms:play-services-auth-api-phone` library which is NOT
 * present in `android/app/build.gradle.kts`. Adding it is out of scope for
 * this sub-agent (no dep bumps). When that dependency is added, replace the
 * stub body with:
 *
 * ```kotlin
 * import com.google.android.gms.auth.api.phone.SmsRetriever
 * fun smsRetrieverClient(context: Context) =
 *     SmsRetriever.getClient(context).startSmsRetriever()
 * ```
 *
 * Required gradle coordinate:
 *   `implementation("com.google.android.gms:play-services-auth-api-phone:18.1.0")`
 */
object OtpInput {

    /**
     * Returns [KeyboardOptions] tuned for OTP entry:
     * - numeric password keyboard (no suggestions, digits only)
     * - autoCorrect disabled
     * - IME Done action so the soft keyboard shows a "Done" / "Go" button
     */
    fun otpKeyboardOptions(): KeyboardOptions = KeyboardOptions(
        keyboardType = KeyboardType.NumberPassword,
        autoCorrect = false,
        imeAction = ImeAction.Done,
    )

    /**
     * Returns the Android View autofill hint string for SMS OTP fields.
     *
     * Wire it into a Compose field via `Modifier.semantics { autofillHints(hint) }`:
     *
     * ```kotlin
     * OutlinedTextField(
     *     modifier = Modifier.semantics { autofillHints(OtpInput.SMS_OTP_AUTOFILL_HINT) },
     *     keyboardOptions = OtpInput.otpKeyboardOptions(),
     * )
     * ```
     *
     * Note: The newer `ContentType.SmsOtpCode` API is preferred once
     * `androidx.compose.ui.autofill.ContentType` becomes public (post 1.7.x).
     */
    const val SMS_OTP_AUTOFILL_HINT: String = "smsOTPCode"

    /**
     * Thin wrapper for the SMS Retriever API.
     *
     * STUB — `play-services-auth-api-phone` is not in the project's
     * build.gradle.kts. Returns null with a log-level warning.
     *
     * TODO: add `implementation("com.google.android.gms:play-services-auth-api-phone:18.1.0")`
     *       to android/app/build.gradle.kts, then replace this body with:
     *       `return SmsRetriever.getClient(context).startSmsRetriever()`
     *
     * @return null (stub). When the dep is present, returns the Task<Void>
     *         from SmsRetriever.getClient(context).startSmsRetriever().
     */
    fun smsRetrieverClient(context: android.content.Context): Nothing? {
        android.util.Log.w(
            "OtpInput",
            "smsRetrieverClient() is a stub — play-services-auth-api-phone is not in the build. " +
                "Add implementation(\"com.google.android.gms:play-services-auth-api-phone:18.1.0\")" +
                " to android/app/build.gradle.kts to enable SMS auto-retrieval.",
        )
        return null
    }
}
