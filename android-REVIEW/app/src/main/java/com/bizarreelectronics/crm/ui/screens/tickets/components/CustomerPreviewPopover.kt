package com.bizarreelectronics.crm.ui.screens.tickets.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Message
import androidx.compose.material3.Divider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties
import com.bizarreelectronics.crm.data.local.db.entities.CustomerEntity
import com.bizarreelectronics.crm.util.PhoneIntents
import kotlinx.coroutines.delay

// -----------------------------------------------------------------------
// CustomerPreviewPopover — tapped from customer avatar in ticket row
// -----------------------------------------------------------------------

/**
 * Compose [Popup] showing a quick customer summary card with Call / SMS / Email actions.
 * Auto-dismisses after 3 seconds of inactivity or on outside tap.
 *
 * @param customer         The [CustomerEntity] to display. Popover is suppressed when null.
 * @param recentTicketCount Count of recent tickets for this customer (from caller).
 * @param onDismiss        Called when the popover should close.
 */
@Composable
fun CustomerPreviewPopover(
    customer: CustomerEntity?,
    recentTicketCount: Int = 0,
    onDismiss: () -> Unit,
) {
    if (customer == null) return

    val context = LocalContext.current

    // 3-second auto-dismiss
    LaunchedEffect(customer.id) {
        delay(3_000L)
        onDismiss()
    }

    Popup(
        onDismissRequest = onDismiss,
        properties = PopupProperties(focusable = true),
    ) {
        Surface(
            shape = MaterialTheme.shapes.medium,
            shadowElevation = 8.dp,
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
            modifier = Modifier
                .width(280.dp)
                .semantics { contentDescription = "Customer preview for ${customerDisplayName(customer)}" },
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                // Name
                Text(
                    text = customerDisplayName(customer),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurface,
                )

                Spacer(modifier = Modifier.height(4.dp))

                // Phone
                val phone = customer.phone ?: customer.mobile
                if (!phone.isNullOrBlank()) {
                    Text(
                        text = phone,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }

                // Email
                if (!customer.email.isNullOrBlank()) {
                    Text(
                        text = customer.email,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }

                // Recent tickets count
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = "Recent tickets ($recentTicketCount)",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary,
                )

                Divider(modifier = Modifier.padding(vertical = 10.dp))

                // Quick actions
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceEvenly,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    if (PhoneIntents.canCall(phone)) {
                        IconButton(
                            onClick = {
                                PhoneIntents.call(context, phone!!)
                                onDismiss()
                            },
                            modifier = Modifier.semantics { contentDescription = "Call ${customerDisplayName(customer)}" },
                        ) {
                            Icon(
                                Icons.Default.Call,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary,
                            )
                        }
                    }

                    if (PhoneIntents.canSms(phone)) {
                        IconButton(
                            onClick = {
                                PhoneIntents.sms(context, phone!!)
                                onDismiss()
                            },
                            modifier = Modifier.semantics { contentDescription = "SMS ${customerDisplayName(customer)}" },
                        ) {
                            Icon(
                                Icons.Default.Message,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.secondary,
                            )
                        }
                    }

                    if (PhoneIntents.canEmail(customer.email)) {
                        IconButton(
                            onClick = {
                                PhoneIntents.email(context, customer.email!!)
                                onDismiss()
                            },
                            modifier = Modifier.semantics { contentDescription = "Email ${customerDisplayName(customer)}" },
                        ) {
                            Icon(
                                Icons.Default.Email,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.tertiary,
                            )
                        }
                    }
                }
            }
        }
    }
}

// -----------------------------------------------------------------------
// Helper
// -----------------------------------------------------------------------

private fun customerDisplayName(customer: CustomerEntity): String {
    val first = customer.firstName?.trim().orEmpty()
    val last = customer.lastName?.trim().orEmpty()
    return when {
        first.isNotEmpty() && last.isNotEmpty() -> "$first $last"
        first.isNotEmpty() -> first
        last.isNotEmpty() -> last
        customer.organization?.isNotBlank() == true -> customer.organization
        else -> "Unknown"
    }
}
