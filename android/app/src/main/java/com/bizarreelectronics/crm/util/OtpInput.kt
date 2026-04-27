package com.bizarreelectronics.crm.util

import android.app.Activity
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
 * ### ContentType / autofill semantics (session 2026-04-26)
 * `ContentType.SmsOtpCode` became accessible in Compose UI 1.8 (BOM 2026.04.01).
 * Wire it into OTP fields via:
 * ```kotlin
 * import androidx.compose.ui.autofill.ContentType
 * OutlinedTextField(
 *     modifier = Modifier.semantics { contentType = ContentType.SmsOtpCode },
 *     keyboardOptions = OtpInput.otpKeyboardOptions(),
 * )
 * ```
 * Legacy `autofillHints(View.AUTOFILL_HINT_SMS_OTP)` still works as a fallback
 * for older devices; both can be applied simultaneously.
 *
 * ### SmsRetriever
 * [smsRetrieverClient] delegates to [SmsRetrieverHelper.startRetriever], which
 * requires `play-services-auth-api-phone` — already present in
 * `android/app/build.gradle.kts`. Call this when the 2FA verify step is
 * composed to enable automatic code fill from incoming SMS messages.
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
     * Prefer `ContentType.SmsOtpCode` on Compose UI 1.8+ devices (see class KDoc).
     */
    const val SMS_OTP_AUTOFILL_HINT: String = "smsOTPCode"

    /**
     * Starts the SMS Retriever session so Android auto-fills the OTP code when
     * the server SMS arrives.
     *
     * Must be called from a foreground [Activity]. The result code is delivered
     * asynchronously through [SmsOtpBus]; the returned Task can be discarded if
     * the caller doesn't need start-failure notifications.
     *
     * Call once per 2FA verify composition. Play Services ignores duplicate
     * starts within the active 5-minute session window.
     */
    fun smsRetrieverClient(activity: Activity) =
        SmsRetrieverHelper.startRetriever(activity)
}
