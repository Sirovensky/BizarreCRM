package com.bizarreelectronics.crm.util

import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.util.Base64
import android.util.Log
import com.google.android.gms.auth.api.phone.SmsRetriever
import com.google.android.gms.tasks.Task
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.Arrays

/**
 * §2.4 L302 — Thin wrapper around the Google Play SMS Retriever API.
 *
 * The SMS Retriever API retrieves a targeted SMS message **without** requiring
 * the `READ_SMS` permission. The server must format the OTP message as:
 *
 * ```
 * <#> Your Bizarre CRM code is 123456
 * <app-hash>
 * ```
 *
 * where `<app-hash>` is the 11-character hash produced by [getAppHash].
 *
 * ### Server-side contract
 * The SMS body must:
 * 1. Begin with `<#> ` (including the trailing space) — this is the Google-required
 *    prefix that signals to Play Services that this SMS is an automated OTP.
 * 2. Contain the 6-digit TOTP code anywhere in the body.
 * 3. End with a newline followed by the 11-character app hash (no extra trailing chars).
 *
 * Example template (substitute `{{CODE}}` and `{{HASH}}`):
 * ```
 * <#> Your Bizarre CRM verification code is {{CODE}}
 * {{HASH}}
 * ```
 *
 * The retriever session lasts **5 minutes**. If no matching SMS arrives within
 * that window, Play Services delivers a timeout status and the user falls back
 * to manual entry (already functional in TwoFaVerifyStep).
 */
object SmsRetrieverHelper {

    private const val TAG = "SmsRetrieverHelper"

    /**
     * Starts the SMS Retriever session for [activity].
     *
     * This must be called from a foreground Activity (not a Service or
     * Application context). The returned [Task] resolves immediately when Play
     * Services accepts the request; the actual SMS is delivered later via
     * [SmsOtpBroadcastReceiver].
     *
     * Call this once per 2FA verify composition — Play Services tracks the
     * active session internally and ignores duplicate starts within the 5-minute
     * window.
     *
     * @return the Task returned by [SmsRetriever.getClient]; you may attach
     *         listeners to it to detect start failures, but the happy-path
     *         result is delivered through [SmsOtpBus].
     */
    fun startRetriever(activity: Activity): Task<Void> {
        Log.d(TAG, "Starting SMS Retriever session")
        return SmsRetriever.getClient(activity).startSmsRetriever()
    }

    /**
     * Computes the 11-character app hash used in the SMS OTP template.
     *
     * The hash is derived from the app's signing certificate(s) using the same
     * algorithm documented by Google's AppSignatureHelper sample:
     * SHA-256(packageName + signing-cert) → Base64 → first 11 chars.
     *
     * **Logged at DEBUG level only** so that the value is accessible during
     * development without leaking to production log aggregators.
     *
     * Pass this value to your server team so they can construct the correct SMS
     * template suffix. The hash is deterministic per-signing-key — it differs
     * between debug (debug.keystore) and release (production keystore) builds.
     *
     * @return 11-character app hash string, or an empty string if the hash
     *         cannot be computed (e.g. PackageManager unavailable).
     */
    fun getAppHash(context: Context): String {
        return try {
            val packageName = context.packageName
            val signatures = getSignatures(context, packageName)
            val hash = signatures.firstNotNullOfOrNull { sig ->
                computeHash(packageName, sig)
            } ?: ""
            Log.d(TAG, "App hash for SMS OTP template: $hash (package=$packageName)")
            hash
        } catch (e: Exception) {
            Log.e(TAG, "Failed to compute app hash", e)
            ""
        }
    }

    // ── Private helpers ──────────────────────────────────────────────────────

    @Suppress("DEPRECATION")
    private fun getSignatures(context: Context, packageName: String): Array<android.content.pm.Signature> {
        val pm = context.packageManager
        return if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
            val info = pm.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
            info.signingInfo?.apkContentsSigners ?: emptyArray()
        } else {
            val info = pm.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
            info.signatures ?: emptyArray()
        }
    }

    private fun computeHash(packageName: String, signature: android.content.pm.Signature): String? {
        return try {
            val digest = MessageDigest.getInstance("SHA-256")
            val input = "$packageName ${signature.toCharsString()}"
            val hashBytes = digest.digest(input.toByteArray(StandardCharsets.UTF_8))
            val base64 = Base64.encodeToString(hashBytes, Base64.NO_PADDING or Base64.NO_WRAP)
            // SMS Retriever hashes are the first 11 characters of the Base64-encoded SHA-256
            base64.take(11)
        } catch (e: Exception) {
            Log.e(TAG, "computeHash failed", e)
            null
        }
    }
}
