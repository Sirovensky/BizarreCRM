package com.bizarreelectronics.crm.util

import android.content.Context
import android.provider.Settings
import java.security.MessageDigest

/**
 * Device-binding utilities for the biometric credential store.
 *
 * ## Purpose
 *
 * Credentials encrypted by [BiometricCredentialStore] are additionally bound to the originating
 * device via a SHA-256 fingerprint of the ANDROID_ID + package name. When [retrieve] decrypts the
 * stored payload it compares the embedded fingerprint against the current device fingerprint; a
 * mismatch means the ciphertext was restored from a backup on a different device and the stored
 * credentials are rejected ([RetrieveResult.DeviceChanged]).
 *
 * ## Backup-export theft prevention
 *
 * Android Auto-Backup is disabled for the encrypted DB and EncryptedSharedPreferences via
 * `backup_rules.xml`. Even if a backup were somehow restored to a different device, the Android
 * Keystore key that wraps the AES-GCM encryption is bound to the originating device's hardware
 * security module and is NOT exported with the backup. Decryption would therefore fail at the
 * Keystore level regardless of this fingerprint check; the fingerprint check is a belt-and-
 * suspenders defence that provides an explicit, user-readable rejection rather than a silent
 * crypto error.
 *
 * ## ANDROID_ID stability
 *
 * `Settings.Secure.ANDROID_ID` is stable for the lifetime of a device-app pair (same user,
 * same app). It changes on factory reset. Factory reset is treated the same as a device change —
 * the user will simply be asked to re-enable biometric login after re-installing.
 *
 * ## Logging invariant
 *
 * The raw ANDROID_ID and the fingerprint are never written to Logcat.
 */
object DeviceBinding {

    /**
     * Returns the raw ANDROID_ID for this device+user pair, or an empty string on the rare
     * devices where it is not available.
     *
     * **Do not log this value** — it is a stable device identifier.
     */
    fun androidId(context: Context): String =
        Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID).orEmpty()

    /**
     * Returns a lower-hex SHA-256 fingerprint of `"$androidId:$packageName"`.
     *
     * The fingerprint is deterministic for the same device+package pair and differs for any other
     * device or (hypothetically) a different package name. It is safe to store alongside
     * ciphertext — it reveals nothing about the ANDROID_ID itself.
     *
     * @param context Android context used to read ANDROID_ID and the package name.
     * @return 64-character lower-hex string (256 bits of output from SHA-256).
     */
    fun fingerprint(context: Context): String {
        val id = androidId(context)
        val pkg = context.packageName
        val raw = "$id:$pkg".toByteArray(Charsets.UTF_8)
        val digest = MessageDigest.getInstance("SHA-256").digest(raw)
        return digest.joinToString("") { b -> "%02x".format(b) }
    }
}
