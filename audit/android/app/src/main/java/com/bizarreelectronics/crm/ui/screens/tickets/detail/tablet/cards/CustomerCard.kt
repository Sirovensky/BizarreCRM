package com.bizarreelectronics.crm.ui.screens.tickets.detail.tablet.cards

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Message
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.dto.CustomerListItem
import com.bizarreelectronics.crm.ui.screens.tickets.detail.tablet.shared.cookieAvatarShape
import com.bizarreelectronics.crm.util.formatPhoneDisplay

/**
 * Tablet ticket-detail Customer card.
 *
 * Shows a cookie-shape avatar (`MaterialShapes.Cookie9Sided.toShape()`)
 * with the customer's initials, the display name + formatted phone,
 * and inline Call + SMS icon-buttons. Tap-anywhere-else routes into
 * the customer detail screen via [onCardClick].
 *
 * Decision: actions are kept here on tablet (NOT duplicated in the
 * top app bar) so each affordance has exactly one home. Mockup parity
 * with `mockups/android-tablet-ticket-detail.html`.
 *
 * @param customer DTO from `state.ticketDetail?.customer`. Falls back
 *   to [fallbackName] / [fallbackPhone] (from the cached ticket entity)
 *   when customer is still loading or absent.
 * @param fallbackName customer display name from the cached ticket
 *   entity for the loading window.
 * @param fallbackPhone customer phone from the cached ticket entity.
 * @param onCardClick fires when the card body is tapped — host opens
 *   the customer detail screen. Disabled when both customer is null
 *   AND no fallback id is available.
 * @param onCall optional dialer trigger — null hides the Call button.
 * @param onSms optional SMS thread trigger — null hides the SMS button.
 */
@Composable
internal fun CustomerCard(
    customer: CustomerListItem?,
    fallbackName: String?,
    fallbackPhone: String?,
    onCardClick: (() -> Unit)? = null,
    onCall: (() -> Unit)? = null,
    onSms: (() -> Unit)? = null,
) {
    val displayName = remember(customer, fallbackName) {
        customer?.let { c ->
            listOfNotNull(c.firstName, c.lastName).joinToString(" ").ifBlank { null }
        } ?: fallbackName ?: "Unknown customer"
    }
    val phone = remember(customer, fallbackPhone) {
        customer?.phone?.takeIf { it.isNotBlank() }
            ?: customer?.mobile?.takeIf { it.isNotBlank() }
            ?: fallbackPhone
    }
    val initials = remember(displayName) {
        displayName
            .split(' ', '-')
            .filter { it.isNotBlank() }
            .take(2)
            .joinToString("") { it.first().uppercaseChar().toString() }
            .ifEmpty { "?" }
    }

    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
        modifier = Modifier.fillMaxWidth().let { base ->
            if (onCardClick != null) base.clickable(onClick = onCardClick)
                .semantics { contentDescription = "Customer $displayName. Tap to open." }
            else base
        },
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // Cookie-shape avatar — brand cream container, dark on-cream initials.
            Surface(
                color = MaterialTheme.colorScheme.primaryContainer,
                contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
                shape = cookieAvatarShape(),
                modifier = Modifier.size(44.dp),
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Text(
                        initials,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            }

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    displayName,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                if (!phone.isNullOrBlank()) {
                    Text(
                        formatPhoneDisplay(phone),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            if (onCall != null && !phone.isNullOrBlank()) {
                IconButton(onClick = onCall) {
                    Icon(
                        Icons.Default.Phone,
                        contentDescription = "Call $displayName",
                        tint = MaterialTheme.colorScheme.primary,
                    )
                }
            }
            if (onSms != null && !phone.isNullOrBlank()) {
                IconButton(onClick = onSms) {
                    Icon(
                        Icons.AutoMirrored.Filled.Message,
                        contentDescription = "Send SMS to $displayName",
                        tint = MaterialTheme.colorScheme.primary,
                    )
                }
            }
        }
    }
}
