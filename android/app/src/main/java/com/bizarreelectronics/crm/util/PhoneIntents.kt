package com.bizarreelectronics.crm.util

import android.content.Context
import android.content.Intent
import android.net.Uri

/**
 * Helpers for launching system phone/SMS intents from ticket screens.
 *
 * Each function is a pure intent builder — no side effects beyond launching the
 * intent. Callers are responsible for ensuring the phone/email is non-null before
 * calling (the composable layer gates visibility via enabled flags).
 *
 * [call] uses ACTION_DIAL (not ACTION_CALL) so the user confirms the call — no
 * CALL_PHONE permission needed.
 */
object PhoneIntents {

    /** Open the phone dialer pre-filled with [phone]. Never auto-dials. */
    fun call(context: Context, phone: String) {
        // Uri.fromParts URL-encodes the SSP so spaces, parens, and slashes in
        // formatted numbers like "+1 (555) 555-1234" don't truncate the dialer
        // input on the system side.
        val intent = Intent(Intent.ACTION_DIAL, Uri.fromParts("tel", phone.trim(), null))
        context.startActivity(intent)
    }

    /**
     * Open the SMS composer pre-filled with [phone].
     *
     * Uses the `smsto:` URI scheme (widely supported) rather than `sms:` so
     * the system will prefer a messaging app over the dialer.
     */
    fun sms(context: Context, phone: String) {
        val intent = Intent(Intent.ACTION_SENDTO, Uri.fromParts("smsto", phone.trim(), null))
        context.startActivity(intent)
    }

    /**
     * Open the email composer pre-filled with [email].
     *
     * Uses ACTION_SENDTO with a `mailto:` URI so only email clients are
     * offered — generic SEND would include sharing targets. Uri.fromParts
     * URL-encodes the SSP so `+` in plus-tag addresses ("user+tag@x.com")
     * doesn't decode to a space.
     */
    fun email(context: Context, email: String) {
        val intent = Intent(Intent.ACTION_SENDTO, Uri.fromParts("mailto", email.trim(), null))
        context.startActivity(intent)
    }

    /** Returns true when [phone] is non-null and non-blank. */
    fun canCall(phone: String?): Boolean = !phone.isNullOrBlank()

    /** Same as [canCall] — SMS availability matches call availability. */
    fun canSms(phone: String?): Boolean = !phone.isNullOrBlank()

    /** Returns true when [email] is non-null, non-blank, and contains '@'. */
    fun canEmail(email: String?): Boolean = !email.isNullOrBlank() && email.contains('@')
}
