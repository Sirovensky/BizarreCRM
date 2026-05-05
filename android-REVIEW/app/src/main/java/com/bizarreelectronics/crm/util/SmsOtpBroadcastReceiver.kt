package com.bizarreelectronics.crm.util

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.auth.api.phone.SmsRetriever
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.common.api.Status
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/**
 * §2.4 L302 — Event bus that carries auto-retrieved OTP codes to any active
 * Compose collector (TwoFaVerifyStep).
 *
 * [events] is a hot shared flow with no replay — a code is only useful once.
 * Collectors in composition receive the code and fill the TOTP field;
 * collectors that aren't attached simply miss the emission (correct behaviour:
 * the user types manually instead).
 */
object SmsOtpBus {
    private val _events = MutableSharedFlow<String>(replay = 0, extraBufferCapacity = 1)

    /** Hot flow of 6-digit OTP strings extracted from incoming SMS messages. */
    val events = _events.asSharedFlow()

    /**
     * Publishes [code] to all active collectors.
     * Called only from [SmsOtpBroadcastReceiver] on the main thread.
     */
    internal fun publish(code: String) {
        _events.tryEmit(code)
    }
}

/**
 * §2.4 L302 — BroadcastReceiver that processes [SmsRetriever.SMS_RETRIEVED_ACTION]
 * intents delivered by Play Services.
 *
 * On a SUCCESS status the receiver:
 * 1. Extracts the raw SMS body from [SmsRetriever.EXTRA_SMS_MESSAGE].
 * 2. Guards that the body starts with `<#>` (the Google-required OTP prefix).
 * 3. Delegates digit extraction to [OtpParser.extractOtpDigits] with a strict
 *    6..6 range.
 * 4. Publishes the code via [SmsOtpBus] so the active TwoFaVerifyStep can
 *    auto-fill the TOTP field without any UI interaction.
 *
 * On TIMEOUT or any other non-SUCCESS status the receiver logs and no-ops —
 * the user falls back to manual entry which already works.
 *
 * ### Manifest registration
 * This receiver is registered statically in AndroidManifest.xml with
 * `android:exported="true"` and the system permission:
 * ```
 * android:permission="com.google.android.gms.auth.api.phone.permission.SEND"
 * ```
 * That permission ensures only Play Services can deliver the intent — no other
 * app can forge a delivery.
 */
class SmsOtpBroadcastReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != SmsRetriever.SMS_RETRIEVED_ACTION) return

        val extras = intent.extras ?: return
        val status = extras.get(SmsRetriever.EXTRA_STATUS) as? Status ?: return

        when (status.statusCode) {
            CommonStatusCodes.SUCCESS -> handleSuccess(extras)
            CommonStatusCodes.TIMEOUT -> Log.d(TAG, "SMS Retriever timed out — user must enter OTP manually")
            else -> Log.w(TAG, "SMS Retriever error: statusCode=${status.statusCode}")
        }
    }

    // ── Private ──────────────────────────────────────────────────────────────

    private fun handleSuccess(extras: android.os.Bundle) {
        val smsBody = extras.getString(SmsRetriever.EXTRA_SMS_MESSAGE)
        if (smsBody == null) {
            Log.w(TAG, "SUCCESS but EXTRA_SMS_MESSAGE is null")
            return
        }

        // Guard: must start with the Google OTP marker; if it doesn't, the SMS
        // was not formatted for our app (or this retriever session was re-used).
        if (!smsBody.startsWith("<#>")) {
            Log.d(TAG, "SMS does not start with <#> — ignoring (not our OTP format)")
            return
        }

        val code = OtpParser.extractOtpDigits(smsBody, range = 6..6)
        if (code == null) {
            Log.w(TAG, "Could not extract 6-digit OTP from SMS body")
            return
        }

        Log.d(TAG, "OTP extracted from SMS — publishing to SmsOtpBus")
        SmsOtpBus.publish(code)
    }

    companion object {
        private const val TAG = "SmsOtpBroadcastReceiver"
    }
}
