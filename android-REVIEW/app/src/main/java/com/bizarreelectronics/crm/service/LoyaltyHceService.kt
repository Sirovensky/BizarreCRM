package com.bizarreelectronics.crm.service

import android.nfc.cardemulation.HostApduService
import android.os.Bundle
import timber.log.Timber

/**
 * §17.8 — Host-based Card Emulation (HCE) service for Bizarre loyalty cards.
 *
 * This service allows the Android device to act as a contactless card when
 * the customer taps their phone to a compatible POS reader. It emulates an
 * ISO 7816-4 application identified by [LOYALTY_AID].
 *
 * ### Protocol (ISO 7816-4 APDU)
 * 1. Reader sends `SELECT AID` (CLA=00, INS=A4, P1=04, P2=00, Lc=7, AID=...):
 *    - Service responds with `9000` (success).
 * 2. Reader sends `GET LOYALTY DATA` (CLA=80, INS=CA, P1=01, P2=00):
 *    - Service responds with a 3-byte token prefix + `9000`.
 *    - Full redemption is handled server-side via the token.
 * 3. Any unrecognised command → `6D00` (INS not supported).
 *
 * ### Manifest declaration (in AndroidManifest.xml)
 * ```xml
 * <service
 *     android:name=".service.LoyaltyHceService"
 *     android:exported="true"
 *     android:permission="android.permission.BIND_NFC_SERVICE">
 *     <intent-filter>
 *         <action android:name="android.nfc.cardemulation.action.HOST_APDU_SERVICE"/>
 *     </intent-filter>
 *     <meta-data
 *         android:name="android.nfc.cardemulation.host_apdu_service"
 *         android:resource="@xml/loyalty_apdu_service"/>
 * </service>
 * ```
 *
 * ### AID registration (res/xml/loyalty_apdu_service.xml)
 * The AID `F0 42 49 5A 4C 4F 59 00` spells `F0BIZLOY\0` — Bizarre Loyalty.
 * Registered in the `payment` category so it appears in Android Wallet.
 *
 * ### Current status
 * Full loyalty-point redemption requires `POST /loyalty/redeem` with a
 * session token issued by the server during check-in.  The service emits
 * a stub token (`BIZLOY-DEMO`) until the server endpoint is wired.
 *
 * @see [NfcDispatcher] for the complementary reader path (card → phone lookup).
 */
class LoyaltyHceService : HostApduService() {

    override fun processCommandApdu(commandApdu: ByteArray, extras: Bundle?): ByteArray {
        if (commandApdu.size < 4) {
            Timber.w("LoyaltyHceService: APDU too short (${commandApdu.size} bytes)")
            return STATUS_UNKNOWN_ERROR
        }

        val cla = commandApdu[0]
        val ins = commandApdu[1]
        val p1  = commandApdu[2]
        val p2  = commandApdu[3]

        Timber.d("LoyaltyHceService: CLA=%02X INS=%02X P1=%02X P2=%02X", cla, ins, p1, p2)

        return when {
            // SELECT AID (ISO 7816-4: CLA=00 INS=A4 P1=04 P2=00)
            cla == 0x00.toByte() && ins == 0xA4.toByte() && p1 == 0x04.toByte() -> {
                if (isLoyaltyAid(commandApdu)) {
                    Timber.i("LoyaltyHceService: AID selected — loyalty card active")
                    STATUS_SUCCESS
                } else {
                    Timber.d("LoyaltyHceService: unknown AID, rejecting")
                    STATUS_NOT_FOUND
                }
            }

            // GET LOYALTY DATA (proprietary: CLA=80 INS=CA P1=01)
            cla == 0x80.toByte() && ins == 0xCA.toByte() && p1 == 0x01.toByte() -> {
                // Stub token — replace with real server-issued session token
                // once POST /loyalty/redeem is implemented.
                val token = STUB_LOYALTY_TOKEN.toByteArray(Charsets.US_ASCII)
                Timber.i("LoyaltyHceService: returning stub loyalty token")
                token + STATUS_SUCCESS
            }

            else -> {
                Timber.d("LoyaltyHceService: unsupported INS=%02X", ins)
                STATUS_INS_NOT_SUPPORTED
            }
        }
    }

    override fun onDeactivated(reason: Int) {
        val msg = when (reason) {
            DEACTIVATION_LINK_LOSS -> "link loss"
            DEACTIVATION_DESELECTED -> "deselected"
            else -> "reason=$reason"
        }
        Timber.d("LoyaltyHceService: deactivated ($msg)")
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    private fun isLoyaltyAid(apdu: ByteArray): Boolean {
        val lcOffset = 4
        if (apdu.size <= lcOffset) return false
        val lc = apdu[lcOffset].toInt() and 0xFF
        val aidStart = lcOffset + 1
        if (apdu.size < aidStart + lc) return false
        val aid = apdu.copyOfRange(aidStart, aidStart + lc)
        return aid.contentEquals(LOYALTY_AID)
    }

    companion object {
        /**
         * Bizarre Loyalty AID: `F0 42 49 5A 4C 4F 59 00`
         * (`F0` = proprietary prefix; `BIZLOY` in ASCII; `00` = version 0).
         */
        val LOYALTY_AID: ByteArray = byteArrayOf(
            0xF0.toByte(), 0x42, 0x49, 0x5A, 0x4C, 0x4F, 0x59, 0x00,
        )

        private val STATUS_SUCCESS          = byteArrayOf(0x90.toByte(), 0x00)
        private val STATUS_NOT_FOUND        = byteArrayOf(0x6A.toByte(), 0x82.toByte())
        private val STATUS_INS_NOT_SUPPORTED = byteArrayOf(0x6D.toByte(), 0x00)
        private val STATUS_UNKNOWN_ERROR    = byteArrayOf(0x6F.toByte(), 0x00)

        /** Stub token — replace with server-issued redemption token. */
        private const val STUB_LOYALTY_TOKEN = "BIZLOY-DEMO"
    }
}
