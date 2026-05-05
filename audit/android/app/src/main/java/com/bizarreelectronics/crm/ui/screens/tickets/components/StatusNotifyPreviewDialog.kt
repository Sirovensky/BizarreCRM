package com.bizarreelectronics.crm.ui.screens.tickets.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp

/**
 * Notification spec returned by the server for a status transition.
 *
 * Server is expected to populate `notifications` on [TicketStatusItem] (404-tolerant:
 * callers only show the dialog when the list is non-empty).
 *
 * @param channel   "sms" | "email"
 * @param recipient Resolved recipient address (phone / email) after variable substitution.
 * @param body      Rendered notification body (variables already resolved by the server).
 */
data class NotificationSpec(
    val channel: String,
    val recipient: String?,
    val body: String,
)

/**
 * StatusNotifyPreviewDialog — §4.7 L742 (plan:L742)
 *
 * Shown **before** the PATCH status call when the target [TicketStatusItem]
 * has `notifications` configured for this transition. Presents a preview of
 * each SMS / email body so the technician can confirm before sending.
 *
 * Three outcomes:
 * - **Send** — caller patches status AND fires `POST /sms/send` (or `/emails`)
 *   for each [NotificationSpec].
 * - **Skip** — caller patches status only; no notifications sent.
 * - **Cancel** — no PATCH, no notifications.
 *
 * Variables are resolved server-side before this dialog is shown; the preview
 * text is rendered verbatim.
 *
 * @param newStatusName  Display name for the target status.
 * @param notifications  Non-empty list of specs to preview.
 * @param onSend         User tapped "Send" — apply status change + send notifications.
 * @param onSkip         User tapped "Skip" — apply status change, skip notifications.
 * @param onCancel       User dismissed — do nothing.
 */
@Composable
fun StatusNotifyPreviewDialog(
    newStatusName: String,
    notifications: List<NotificationSpec>,
    onSend: () -> Unit,
    onSkip: () -> Unit,
    onCancel: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onCancel,
        title = {
            Text("Notify customer?")
        },
        text = {
            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(
                    "Moving to \"$newStatusName\" will trigger the following notification(s):",
                    style = MaterialTheme.typography.bodyMedium,
                )

                for (spec in notifications) {
                    NotificationPreviewCard(spec)
                }
            }
        },
        confirmButton = {
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                TextButton(onClick = onCancel) { Text("Cancel") }
                TextButton(onClick = onSkip) { Text("Skip") }
                TextButton(onClick = onSend) {
                    Text(
                        "Send",
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
            }
        },
    )
}

@Composable
private fun NotificationPreviewCard(spec: NotificationSpec) {
    val channelLabel = when (spec.channel.lowercase()) {
        "sms" -> "SMS"
        "email" -> "Email"
        else -> spec.channel.replaceFirstChar { it.uppercase() }
    }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant,
        ),
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    channelLabel,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.primary,
                )
                if (!spec.recipient.isNullOrBlank()) {
                    Text(
                        spec.recipient,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Spacer(modifier = Modifier.height(6.dp))
            Text(
                spec.body,
                style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
