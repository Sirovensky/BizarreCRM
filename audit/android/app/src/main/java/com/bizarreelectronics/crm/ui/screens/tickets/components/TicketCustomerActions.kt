package com.bizarreelectronics.crm.ui.screens.tickets.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Sms
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.util.PhoneIntents

/**
 * Row of three action chips — Call / SMS / Email — for contacting a ticket's customer.
 *
 * Each chip is disabled when the corresponding contact field is absent.
 * Uses [PhoneIntents] to launch system intents without requiring extra permissions.
 *
 * @param phone  customer phone or mobile number; enables Call + SMS chips.
 * @param email  customer email address; enables Email chip.
 * @param onNavigateToSms  optional in-app SMS callback. When non-null, tapping SMS
 *   routes into the BizarreSMS composer instead of the system SMS app.
 */
@Composable
fun TicketCustomerActions(
    phone: String?,
    email: String?,
    modifier: Modifier = Modifier,
    onNavigateToSms: ((String) -> Unit)? = null,
) {
    val context = LocalContext.current
    val canCall = PhoneIntents.canCall(phone)
    val canSms = PhoneIntents.canSms(phone)
    val canEmail = PhoneIntents.canEmail(email)

    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        AssistChip(
            onClick = { if (phone != null) PhoneIntents.call(context, phone) },
            label = { Text("Call") },
            leadingIcon = {
                Icon(
                    Icons.Default.Call,
                    // decorative — "Call" Text announces chip purpose
                    contentDescription = null,
                )
            },
            enabled = canCall,
            colors = AssistChipDefaults.assistChipColors(
                leadingIconContentColor = MaterialTheme.colorScheme.primary,
            ),
        )

        AssistChip(
            onClick = {
                if (phone != null) {
                    if (onNavigateToSms != null) {
                        val normalized = phone
                            .replace(Regex("[^0-9]"), "")
                            .let { digits ->
                                if (digits.length == 11 && digits.startsWith("1")) digits.substring(1)
                                else digits
                            }
                        onNavigateToSms(normalized)
                    } else {
                        PhoneIntents.sms(context, phone)
                    }
                }
            },
            label = { Text("SMS") },
            leadingIcon = {
                Icon(
                    Icons.Default.Sms,
                    contentDescription = null,
                )
            },
            enabled = canSms,
            colors = AssistChipDefaults.assistChipColors(
                leadingIconContentColor = MaterialTheme.colorScheme.secondary,
            ),
        )

        AssistChip(
            onClick = { if (email != null) PhoneIntents.email(context, email) },
            label = { Text("Email") },
            leadingIcon = {
                Icon(
                    Icons.Default.Email,
                    contentDescription = null,
                )
            },
            enabled = canEmail,
            colors = AssistChipDefaults.assistChipColors(
                leadingIconContentColor = MaterialTheme.colorScheme.tertiary,
            ),
        )
    }
}
