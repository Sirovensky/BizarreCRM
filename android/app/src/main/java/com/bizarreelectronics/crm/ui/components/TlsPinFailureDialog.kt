package com.bizarreelectronics.crm.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogProperties

/**
 * Non-dismissable alert shown when OkHttp CertificatePinner rejects the server
 * certificate chain (ActionPlan §2.12 L359). The only legitimate user action is
 * either to contact the admin (copy support contact to clipboard) or to
 * terminate the app.
 *
 * This dialog is NEVER auto-dismissed. Tapping the scrim does nothing.
 *
 * Caller shows this dialog when [ApiClient] or its authenticator surfaces a
 * `javax.net.ssl.SSLPeerUnverifiedException` stemming from the pinner. Detection
 * lives outside this component; the dialog only renders the decision.
 *
 * @param hostname              The hostname whose certificate failed pinning, displayed
 *                              to the user so they can relay it to the admin.
 * @param supportContactEmail   Optional support email shown in the dialog body.
 *                              May be null when the tenant-config endpoint was unreachable.
 * @param onCopyDetails         Invoked when the user taps "Copy details for admin".
 *                              Caller should copy hostname + error summary to the clipboard.
 * @param onSignOut             Invoked when the user taps "Sign out". The only safe
 *                              action remaining — caller wires to auth navigation.
 * @param modifier              Applied to the [AlertDialog] root.
 * @param reduceMotion          Reserved for future use. This dialog renders immediately
 *                              with no entrance animation regardless of this value.
 *                              Callers should derive from
 *                              [com.bizarreelectronics.crm.util.ReduceMotion].
 */
@Composable
fun TlsPinFailureDialog(
    hostname: String,
    supportContactEmail: String?,       // optional, nullable when tenant-config endpoint unreachable
    onCopyDetails: () -> Unit,          // copies hostname + error summary for admin
    onSignOut: () -> Unit,              // optional exit — only safe action left
    modifier: Modifier = Modifier,
    @Suppress("UNUSED_PARAMETER")
    reduceMotion: Boolean = false,      // no animation in this dialog; param reserved for consistency
) {
    // TODO(i18n): Extract all string literals to string resources.
    val iconDescription = "Security lock — certificate pin mismatch"
    val dialogDescription = buildString {
        append("Critical security error. ")
        append("Certificate pin mismatch for $hostname. ")
        append("This server's certificate doesn't match the pinned certificate. ")
        append("Contact your admin.")
        if (supportContactEmail != null) {
            append(" Support email: $supportContactEmail.")
        }
    }

    AlertDialog(
        onDismissRequest = { /* no-op: non-dismissable by design */ },
        properties = DialogProperties(
            dismissOnBackPress = false,
            dismissOnClickOutside = false,
        ),
        modifier = modifier.semantics {
            liveRegion = LiveRegionMode.Assertive   // critical — announce immediately
            contentDescription = dialogDescription
        },
        icon = {
            Icon(
                imageVector = Icons.Default.Lock,
                contentDescription = iconDescription,
                tint = MaterialTheme.colorScheme.onErrorContainer,
                modifier = Modifier.size(ICON_SIZE_DP.dp),
            )
        },
        title = {
            // TODO(i18n)
            Text(
                text = "Certificate pin mismatch",
                style = MaterialTheme.typography.headlineSmall,
                color = MaterialTheme.colorScheme.onSurface,
            )
        },
        text = {
            androidx.compose.foundation.layout.Column(
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                // §2.12 L359 exact copy:
                // TODO(i18n)
                Text(
                    text = "This server\u2019s certificate doesn\u2019t match the pinned certificate. " +
                        "Contact your admin.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )

                Text(
                    // TODO(i18n)
                    text = "Host: $hostname",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )

                if (supportContactEmail != null) {
                    Text(
                        // TODO(i18n)
                        text = "Support: $supportContactEmail",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        },
        // Container tinted with errorContainer to reinforce the critical-error context.
        containerColor = MaterialTheme.colorScheme.errorContainer,
        dismissButton = {
            TextButton(onClick = onCopyDetails) {
                // TODO(i18n)
                Text(
                    text = "Copy details for admin",
                    color = MaterialTheme.colorScheme.onErrorContainer,
                )
            }
        },
        confirmButton = {
            Row(
                horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Button(
                    onClick = onSignOut,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.error,
                        contentColor = MaterialTheme.colorScheme.onError,
                    ),
                ) {
                    // TODO(i18n)
                    Text("Sign out")
                }
            }
        },
    )
}

// ---------------------------------------------------------------------------
// Private constants
// ---------------------------------------------------------------------------

/** Size of the lock icon inside the dialog header, in dp. */
private const val ICON_SIZE_DP = 32
