package com.bizarreelectronics.crm.util

import android.content.Context
import android.os.Build

/**
 * DeviceFingerprint — §4.14 L785 (plan:L785)
 *
 * Thin audit wrapper over [DeviceBinding.fingerprint] that enriches the signature
 * audit record with human-readable device model and manufacturer information.
 *
 * ## Security invariant
 *
 * The raw ANDROID_ID and the SHA-256 fingerprint are NEVER logged. Model and
 * manufacturer fields are included because they are public hardware metadata and
 * add useful context to the audit trail without exposing PII.
 *
 * ## Usage
 *
 * ```kotlin
 * val fp = DeviceFingerprint.get(context)
 * val audit = SignatureAuditDto(
 *     timestamp  = Instant.now().toString(),
 *     deviceFingerprint = fp.fingerprint,
 *     actorUserId = session.userId,
 * )
 * ```
 *
 * [FingerprintInfo.summary] is a single-line string suitable for logging and
 * audit display: `"sha256=<64hex> model=<Manufacturer Model>"`.
 */
object DeviceFingerprint {

    /**
     * Rich fingerprint data for the current device.
     *
     * @param fingerprint SHA-256 hex string from [DeviceBinding.fingerprint].
     * @param model       [Build.MODEL] — human-readable device name (e.g. "Pixel 9 Pro").
     * @param manufacturer [Build.MANUFACTURER] — OEM name (e.g. "Google").
     */
    data class FingerprintInfo(
        val fingerprint: String,
        val model: String,
        val manufacturer: String,
    ) {
        /**
         * Single-line audit summary. Safe to log — no PII; fingerprint is hashed.
         *
         * Example: `"sha256=a1b2c3... model=Google Pixel 9 Pro"`
         */
        val summary: String
            get() = "sha256=${fingerprint.take(16)}… model=$manufacturer $model"
    }

    /**
     * Compute the device fingerprint for audit purposes.
     *
     * Delegates the ANDROID_ID → SHA-256 computation to [DeviceBinding.fingerprint]
     * and appends [Build.MANUFACTURER] + [Build.MODEL] for human-readable audit context.
     *
     * **Do not log the full [FingerprintInfo.fingerprint] value** — use
     * [FingerprintInfo.summary] which truncates to the first 16 hex characters.
     *
     * @param context Application or activity context.
     * @return [FingerprintInfo] with fingerprint, model, and manufacturer.
     */
    fun get(context: Context): FingerprintInfo = FingerprintInfo(
        fingerprint = DeviceBinding.fingerprint(context),
        model = Build.MODEL,
        manufacturer = Build.MANUFACTURER,
    )
}
