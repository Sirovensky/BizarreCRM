package com.bizarreelectronics.crm.service

import android.content.Context
import android.nfc.cardemulation.HostApduService
import android.os.Bundle
import dagger.hilt.android.AndroidEntryPoint
import timber.log.Timber
import javax.inject.Inject

/**
 * §17.8 — Host-based Card Emulation (HCE) for loyalty cards.
 *
 * Responds to a SELECT AID command from an NFC reader.  When a compatible
 * reader (e.g. a second Bizarre-CRM instance or a partner loyalty reader)
 * sends SELECT AID [BIZARRE_LOYALTY_AID], this service responds with the
 * tenant-specific customer token stored in SharedPreferences.
 *
 * The token is written by the app during loyalty enrolment (customer taps a
 * QR code → app stores their loyalty ID → next time they tap their phone on
 * an NFC reader, this service responds with the ID).
 *
 * AID: F0 42 49 5A 43 52 4D 01  (ASCII "BIZCRM" with F0 proprietary prefix + 01 version)
 *
 * Manifest registration (AndroidManifest.xml):
 * ```xml
 * <service
 *     android:name=".service.LoyaltyCardHceService"
 *     android:exported="true"
 *     android:permission="android.permission.BIND_NFC_SERVICE">
 *     <intent-filter>
 *         <action android:name="android.nfc.cardemulation.action.HOST_APDU_SERVICE" />
 *     </intent-filter>
 *     <meta-data
 *         android:name="android.nfc.cardemulation.host_apdu_service"
 *         android:resource="@xml/hce_apdu_service" />
 * </service>
 * ```
 *
 * res/xml/hce_apdu_service.xml must declare the AID group.
 *
 * mock-mode wiring: service is registered and responds to APDU exchanges;
 * actual loyalty-token storage + enrolment flow is a future screen.
 * Needs physical NFC hardware (two devices) for end-to-end test.
 */
@AndroidEntryPoint
class LoyaltyCardHceService : HostApduService() {

    @Inject
    lateinit var appContext: Context

    companion object {
        // Proprietary AID: F0 + "BIZCRM" ASCII + version byte
        private val BIZARRE_LOYALTY_AID = byteArrayOf(
            0xF0.toByte(), 0x42, 0x49, 0x5A, 0x43, 0x52, 0x4D, 0x01
        )

        // Standard SELECT AID APDU prefix
        private val SELECT_APDU_HEADER = byteArrayOf(0x00, 0xA4.toByte(), 0x04, 0x00)

        // ISO 7816-4 status words
        private val SW_OK         = byteArrayOf(0x90.toByte(), 0x00)
        private val SW_UNKNOWN    = byteArrayOf(0x6F, 0x00)
        private val SW_CONDITIONS = byteArrayOf(0x69.toByte(), 0x85.toByte())

        private const val PREF_FILE = "loyalty_hce_prefs"
        private const val PREF_TOKEN = "loyalty_token"

        /** Save a loyalty token so [LoyaltyCardHceService] can respond to APDU requests. */
        fun saveLoyaltyToken(context: Context, token: String) {
            context.getSharedPreferences(PREF_FILE, Context.MODE_PRIVATE)
                .edit().putString(PREF_TOKEN, token).apply()
        }

        /** Clear the loyalty token (e.g. on customer sign-out). */
        fun clearLoyaltyToken(context: Context) {
            context.getSharedPreferences(PREF_FILE, Context.MODE_PRIVATE)
                .edit().remove(PREF_TOKEN).apply()
        }

        /** Returns true if a loyalty token is enrolled on this device. */
        fun hasLoyaltyToken(context: Context): Boolean =
            context.getSharedPreferences(PREF_FILE, Context.MODE_PRIVATE)
                .getString(PREF_TOKEN, null) != null
    }

    override fun processCommandApdu(commandApdu: ByteArray, extras: Bundle?): ByteArray {
        Timber.d("LoyaltyCardHceService: received APDU ${commandApdu.toHex()}")

        // Validate SELECT AID command
        if (!commandApdu.startsWith(SELECT_APDU_HEADER)) {
            Timber.d("LoyaltyCardHceService: not a SELECT APDU")
            return SW_UNKNOWN
        }

        // Lc byte = length of AID in command
        val lcIndex = SELECT_APDU_HEADER.size
        if (commandApdu.size <= lcIndex) return SW_UNKNOWN
        val aidLength = commandApdu[lcIndex].toInt() and 0xFF
        val aidStart = lcIndex + 1
        val aidEnd = aidStart + aidLength
        if (commandApdu.size < aidEnd) return SW_UNKNOWN

        val receivedAid = commandApdu.sliceArray(aidStart until aidEnd)
        if (!receivedAid.contentEquals(BIZARRE_LOYALTY_AID)) {
            Timber.d("LoyaltyCardHceService: AID mismatch ${receivedAid.toHex()}")
            return SW_UNKNOWN
        }

        // Retrieve loyalty token from prefs
        val prefs = applicationContext.getSharedPreferences(PREF_FILE, Context.MODE_PRIVATE)
        val token = prefs.getString(PREF_TOKEN, null)
        if (token.isNullOrBlank()) {
            Timber.w("LoyaltyCardHceService: no loyalty token enrolled — returning SW_CONDITIONS")
            return SW_CONDITIONS
        }

        val tokenBytes = token.toByteArray(Charsets.UTF_8)
        Timber.i("LoyaltyCardHceService: responding with loyalty token (${tokenBytes.size} bytes)")
        return tokenBytes + SW_OK
    }

    override fun onDeactivated(reason: Int) {
        Timber.d("LoyaltyCardHceService: deactivated reason=$reason")
    }

    // ─── Companion helpers ────────────────────────────────────────────────────

    private fun ByteArray.startsWith(prefix: ByteArray): Boolean {
        if (this.size < prefix.size) return false
        return prefix.indices.all { this[it] == prefix[it] }
    }

    private fun ByteArray.toHex(): String = joinToString("") { "%02X".format(it) }
}
