package com.bizarreelectronics.crm.util

import android.content.Context
import android.provider.ContactsContract
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * §42.1 — Caller-ID: resolve a phone number to a contact display name using
 * the device address book.
 *
 * Privacy rules:
 *  - READ_CONTACTS runtime permission must have been granted; this helper
 *    returns null (not throws) if it has not been granted.
 *  - Only contact names are read — no other PII is accessed.
 *  - The lookup is performed synchronously; callers should invoke from an
 *    IO dispatcher (e.g. inside a coroutine on Dispatchers.IO).
 *
 * The result is used only to display a friendly name in the Calls tab /
 * call detail. It is never written to the server or persisted locally.
 */
@Singleton
class CallerIdLookupHelper @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    /**
     * Look up the contact display name for [phoneNumber].
     *
     * Returns the contact's display name, or null if:
     *   - READ_CONTACTS permission is not granted.
     *   - No contact matches the number.
     *   - The ContentProvider query fails.
     */
    fun lookupName(phoneNumber: String): String? {
        if (!hasReadContactsPermission()) return null
        val normalised = phoneNumber.replace("[^+\\d]".toRegex(), "")
        if (normalised.isBlank()) return null
        return runCatching {
            context.contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                arrayOf(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME),
                "${ContactsContract.CommonDataKinds.Phone.NORMALIZED_NUMBER} = ?",
                arrayOf(normalised),
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    cursor.getString(0).takeIf { it.isNotBlank() }
                } else {
                    null
                }
            }
        }.getOrNull()
    }

    private fun hasReadContactsPermission(): Boolean =
        context.checkSelfPermission(android.Manifest.permission.READ_CONTACTS) ==
            android.content.pm.PackageManager.PERMISSION_GRANTED
}
