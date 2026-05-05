package com.bizarreelectronics.crm.ui.screens.customers.components

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.MergeType
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.Receipt
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Sms
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp

/**
 * Scrollable row of quick-action chips for the customer detail Info tab (plan:L896).
 *
 * Actions: Call / SMS / Email / New ticket / New invoice / Share vCard / Merge / Delete.
 * Destructive actions (Delete) are role-gated by the caller via [canDelete].
 *
 * @param phone          Primary phone number, or null to disable Call/SMS.
 * @param email          Email address, or null to disable Email chip.
 * @param canDelete      When false, the Delete chip is hidden (role gate).
 * @param onCall         Handled by caller (opens system dialer).
 * @param onSms          Handled by caller (opens SMS or in-app SMS).
 * @param onEmail        Handled by caller (opens email client).
 * @param onNewTicket    Navigate to create ticket pre-seeded with this customer.
 * @param onNewInvoice   Navigate to create invoice pre-seeded with this customer.
 * @param onShare        Share vCard intent.
 * @param onMerge        Open merge-customer flow (future).
 * @param onDelete       Open delete-customer confirm dialog.
 */
@Composable
fun CustomerQuickActions(
    phone: String?,
    email: String?,
    canDelete: Boolean = true,
    onCall: (() -> Unit)? = null,
    onSms: (() -> Unit)? = null,
    onEmail: (() -> Unit)? = null,
    onNewTicket: (() -> Unit)? = null,
    onNewInvoice: (() -> Unit)? = null,
    onShare: (() -> Unit)? = null,
    onMerge: (() -> Unit)? = null,
    onDelete: (() -> Unit)? = null,
) {
    val context = LocalContext.current

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (phone != null) {
            QuickChip(
                label = "Call",
                icon = Icons.Default.Phone,
                onClick = onCall ?: {
                    context.startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:$phone")))
                },
            )
            QuickChip(
                label = "SMS",
                icon = Icons.Default.Sms,
                onClick = onSms ?: {
                    context.startActivity(Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:$phone")))
                },
            )
        }
        if (email != null) {
            QuickChip(
                label = "Email",
                icon = Icons.Default.Email,
                onClick = onEmail ?: {
                    context.startActivity(
                        Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:$email"))
                    )
                },
            )
        }
        if (onNewTicket != null) {
            QuickChip(label = "New ticket", icon = Icons.Default.Add, onClick = onNewTicket)
        }
        if (onNewInvoice != null) {
            QuickChip(label = "New invoice", icon = Icons.Default.Receipt, onClick = onNewInvoice)
        }
        if (onShare != null) {
            QuickChip(label = "Share", icon = Icons.Default.Share, onClick = onShare)
        }
        if (onMerge != null) {
            QuickChip(label = "Merge", icon = Icons.Default.MergeType, onClick = onMerge)
        }
        if (canDelete && onDelete != null) {
            QuickChip(
                label = "Delete",
                icon = Icons.Default.Delete,
                onClick = onDelete,
                destructive = true,
            )
        }
        // Trailing spacer so last chip isn't flush against the edge
        Spacer(modifier = Modifier.width(8.dp))
    }
}

@Composable
private fun QuickChip(
    label: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    onClick: () -> Unit,
    destructive: Boolean = false,
) {
    val containerColor = if (destructive) {
        MaterialTheme.colorScheme.errorContainer
    } else {
        MaterialTheme.colorScheme.surfaceVariant
    }
    val contentColor = if (destructive) {
        MaterialTheme.colorScheme.onErrorContainer
    } else {
        MaterialTheme.colorScheme.onSurfaceVariant
    }

    AssistChip(
        onClick = onClick,
        label = { Text(label, style = MaterialTheme.typography.labelMedium) },
        leadingIcon = {
            Icon(
                icon,
                contentDescription = null,
                modifier = Modifier.size(AssistChipDefaults.IconSize),
                tint = contentColor,
            )
        },
        colors = AssistChipDefaults.assistChipColors(
            containerColor = containerColor,
            labelColor = contentColor,
        ),
    )
}
