package com.bizarreelectronics.crm.ui.screens.customers.components

import android.Manifest
import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import android.provider.ContactsContract
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext

/**
 * Simplified contact picker result — only the fields needed for customer creation.
 */
data class ImportedContact(
    val displayName: String?,
    val phone: String?,
    val email: String?,
)

/**
 * Reads a contact URI from the Contacts provider (plan:L886).
 * Returns [ImportedContact] or null when no data is available.
 */
fun readContactFromUri(context: Context, uri: Uri): ImportedContact? {
    val cr: ContentResolver = context.contentResolver
    val contactId = uri.lastPathSegment ?: return null

    var displayName: String? = null
    var phone: String? = null
    var email: String? = null

    // Display name
    cr.query(uri, arrayOf(ContactsContract.Contacts.DISPLAY_NAME), null, null, null)
        ?.use { c ->
            if (c.moveToFirst()) {
                displayName = c.getString(0)
            }
        }

    // Phone
    val phoneUri = ContactsContract.CommonDataKinds.Phone.CONTENT_URI
    cr.query(
        phoneUri,
        arrayOf(ContactsContract.CommonDataKinds.Phone.NUMBER),
        "${ContactsContract.CommonDataKinds.Phone.CONTACT_ID} = ?",
        arrayOf(contactId),
        null,
    )?.use { c ->
        if (c.moveToFirst()) {
            phone = c.getString(0)
        }
    }

    // Email
    val emailUri = ContactsContract.CommonDataKinds.Email.CONTENT_URI
    cr.query(
        emailUri,
        arrayOf(ContactsContract.CommonDataKinds.Email.DATA),
        "${ContactsContract.CommonDataKinds.Email.CONTACT_ID} = ?",
        arrayOf(contactId),
        null,
    )?.use { c ->
        if (c.moveToFirst()) {
            email = c.getString(0)
        }
    }

    return ImportedContact(displayName, phone, email)
}

/**
 * Contact import entry-point (plan:L886).
 *
 * Handles the full READ_CONTACTS runtime permission request + rationale dialog,
 * then launches the system contact picker via [ActivityResultContracts.PickContact].
 * On selection calls [onContactPicked] with the parsed contact data.
 *
 * Runtime READ_CONTACTS permission is already declared in AndroidManifest.xml
 * (commit 9408f0d). This composable prompts for it at the use-site with a rationale.
 *
 * Returns a lambda — call it to start the flow.
 */
@Composable
fun rememberCustomerContactImport(
    onContactPicked: (ImportedContact) -> Unit,
): () -> Unit {
    val context = LocalContext.current
    var showRationale by remember { mutableStateOf(false) }
    var pendingPick by remember { mutableStateOf(false) }

    val contactPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickContact(),
    ) { uri ->
        pendingPick = false
        if (uri != null) {
            val contact = readContactFromUri(context, uri)
            if (contact != null) {
                onContactPicked(contact)
            }
        }
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission(),
    ) { granted ->
        if (granted) {
            contactPickerLauncher.launch(null)
        }
    }

    if (showRationale) {
        AlertDialog(
            onDismissRequest = { showRationale = false },
            title = { Text("Contacts access needed") },
            text = {
                Text(
                    "Allow Bizarre CRM to read your contacts so you can import a contact as a new customer."
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    showRationale = false
                    permissionLauncher.launch(Manifest.permission.READ_CONTACTS)
                }) { Text("Allow") }
            },
            dismissButton = {
                TextButton(onClick = { showRationale = false }) { Text("Not now") }
            },
        )
    }

    return {
        // Check permission state at call time via PackageManager
        val pm = context.packageManager
        val permResult = pm.checkPermission(
            Manifest.permission.READ_CONTACTS,
            context.packageName,
        )
        if (permResult == android.content.pm.PackageManager.PERMISSION_GRANTED) {
            contactPickerLauncher.launch(null)
        } else {
            showRationale = true
        }
    }
}
