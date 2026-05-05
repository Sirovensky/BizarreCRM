package com.bizarreelectronics.crm.util

import android.app.Activity
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.tech.Ndef
import android.os.Bundle
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

/**
 * §17.8 — NFC customer-card tap dispatcher.
 *
 * Tenant-printed NFC cards embed a customer ID in an NDEF text record using
 * the format `"bizarre-customer:<id>"` (e.g. `"bizarre-customer:42"`).
 *
 * ### Integration
 * 1. Call [enable] from `Activity.onResume` to activate foreground dispatch.
 * 2. Call [disable] from `Activity.onPause` to release the adapter.
 * 3. Call [handleIntent] from `Activity.onNewIntent` — returns a [CustomerTap]
 *    on match, null if the tag is unrecognised.
 *
 * ### Permission
 * The manifest declares `<uses-feature android:name="android.hardware.nfc"
 * android:required="false" />` so the app installs on non-NFC devices.
 * [isAvailable] guards UI — callers must check it before showing NFC affordances.
 */
@Singleton
class NfcDispatcher @Inject constructor() {

    private var adapter: NfcAdapter? = null

    /** True when NFC hardware is present and enabled. */
    fun isAvailable(activity: Activity): Boolean {
        val a = NfcAdapter.getDefaultAdapter(activity) ?: return false
        return a.isEnabled
    }

    /**
     * Activate foreground NFC dispatch so the app receives TAG_DISCOVERED
     * intents before other apps. Call from [Activity.onResume].
     */
    fun enable(activity: Activity) {
        adapter = NfcAdapter.getDefaultAdapter(activity) ?: return
        if (adapter?.isEnabled != true) return
        try {
            adapter?.enableForegroundDispatch(
                activity,
                android.app.PendingIntent.getActivity(
                    activity,
                    0,
                    android.content.Intent(activity, activity::class.java)
                        .addFlags(android.content.Intent.FLAG_ACTIVITY_SINGLE_TOP),
                    android.app.PendingIntent.FLAG_MUTABLE,
                ),
                null, // all tag types
                null,
            )
            Timber.d("NfcDispatcher: foreground dispatch enabled")
        } catch (e: Exception) {
            Timber.w(e, "NfcDispatcher: enableForegroundDispatch failed")
        }
    }

    /**
     * Deactivate foreground dispatch. Call from [Activity.onPause].
     */
    fun disable(activity: Activity) {
        runCatching { adapter?.disableForegroundDispatch(activity) }
        Timber.d("NfcDispatcher: foreground dispatch disabled")
    }

    /**
     * Parse an incoming NFC [android.content.Intent] for a customer ID tag.
     *
     * Reads the first NDEF text record from the tag. If the payload matches
     * `"bizarre-customer:<id>"` the customer ID is returned as a [CustomerTap].
     *
     * @param intent The intent received in [Activity.onNewIntent].
     * @return [CustomerTap] with the customer ID, or `null` if not a CRM card.
     */
    fun handleIntent(intent: android.content.Intent): CustomerTap? {
        val tag: Tag = intent.getParcelableExtra(NfcAdapter.EXTRA_TAG) ?: return null
        return try {
            val ndef = Ndef.get(tag) ?: return null
            ndef.connect()
            val message = ndef.ndefMessage
            ndef.close()
            parseNdefMessage(message)
        } catch (e: Exception) {
            Timber.w(e, "NfcDispatcher: tag read failed")
            null
        }
    }

    private fun parseNdefMessage(message: android.nfc.NdefMessage?): CustomerTap? {
        val records = message?.records ?: return null
        for (record in records) {
            if (record.tnf != android.nfc.NdefRecord.TNF_WELL_KNOWN) continue
            if (!record.type.contentEquals(android.nfc.NdefRecord.RTD_TEXT)) continue
            val payload = record.payload ?: continue
            // NDEF text record: first byte = status (language code length), rest = text.
            val langCodeLen = payload[0].toInt() and 0x3F
            val text = String(payload, 1 + langCodeLen, payload.size - 1 - langCodeLen, Charsets.UTF_8)
            if (text.startsWith(CUSTOMER_TAG_PREFIX)) {
                val id = text.removePrefix(CUSTOMER_TAG_PREFIX).trim().toLongOrNull()
                if (id != null) {
                    Timber.d("NfcDispatcher: customer tap id=$id")
                    return CustomerTap(customerId = id, rawText = text)
                }
            }
        }
        return null
    }

    companion object {
        private const val CUSTOMER_TAG_PREFIX = "bizarre-customer:"
    }
}

/**
 * Result of a successful NFC customer-card tap.
 *
 * @param customerId The CRM customer ID embedded in the NDEF record.
 * @param rawText    Full NDEF text payload (for logging / diagnostics).
 */
data class CustomerTap(
    val customerId: Long,
    val rawText: String,
)
