package com.bizarreelectronics.crm.ui.screens.communications

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.Receipt
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/**
 * §12.2 — Entity reference picker for the SMS composer.
 *
 * Surfaced when the user taps the "Insert link" icon button. Shows three
 * categories of entities: tickets, invoices, and payment links attached to
 * the current thread's customer. Tapping a row inserts a formatted reference
 * text token into the compose field at the current cursor position.
 *
 * Token format (plain text, no server short-URL needed):
 *   • Ticket   → "Ticket #<id> – <subject>"
 *   • Invoice  → "Invoice #<id> – $<total>"
 *   • Payment  → "Pay here: <url>"
 *
 * Full short-URL generation (e.g. sms.bizarrecrm.app/p/<token>) is deferred
 * until the server exposes a URL-shortener endpoint. The plain-text format is
 * functional and TCPA-safe.
 */

sealed class SmsEntityRef {
    data class TicketRef(val id: Long, val subject: String) : SmsEntityRef()
    data class InvoiceRef(val id: Long, val total: String) : SmsEntityRef()
    data class PaymentLinkRef(val id: Long, val url: String, val amount: String) : SmsEntityRef()
}

/** Formats a [SmsEntityRef] as a plain-text token ready to insert into an SMS body. */
fun SmsEntityRef.toInsertText(): String = when (this) {
    is SmsEntityRef.TicketRef -> "Ticket #$id – $subject"
    is SmsEntityRef.InvoiceRef -> "Invoice #$id – $total"
    is SmsEntityRef.PaymentLinkRef -> "Pay $amount here: $url"
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SmsEntityPickerSheet(
    tickets: List<SmsEntityRef.TicketRef>,
    invoices: List<SmsEntityRef.InvoiceRef>,
    paymentLinks: List<SmsEntityRef.PaymentLinkRef>,
    onEntitySelected: (SmsEntityRef) -> Unit,
    onDismiss: () -> Unit,
) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp),
        ) {
            Text(
                "Insert link",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(Modifier.height(8.dp))
            HorizontalDivider()

            val hasContent = tickets.isNotEmpty() || invoices.isNotEmpty() || paymentLinks.isNotEmpty()

            if (!hasContent) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(120.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        "No tickets, invoices or payment links for this customer.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            } else {
                LazyColumn(
                    contentPadding = PaddingValues(vertical = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    if (tickets.isNotEmpty()) {
                        item { EntitySectionHeader(title = "Tickets") }
                        items(tickets, key = { "ticket_${it.id}" }) { ref ->
                            EntityRow(
                                icon = { Icon(Icons.Default.Description, contentDescription = null) },
                                primary = "Ticket #${ref.id}",
                                secondary = ref.subject,
                                a11y = "Insert ticket ${ref.id}: ${ref.subject}",
                                onClick = { onEntitySelected(ref) },
                            )
                        }
                    }
                    if (invoices.isNotEmpty()) {
                        item { EntitySectionHeader(title = "Invoices") }
                        items(invoices, key = { "invoice_${it.id}" }) { ref ->
                            EntityRow(
                                icon = { Icon(Icons.Default.Receipt, contentDescription = null) },
                                primary = "Invoice #${ref.id}",
                                secondary = ref.total,
                                a11y = "Insert invoice ${ref.id}: ${ref.total}",
                                onClick = { onEntitySelected(ref) },
                            )
                        }
                    }
                    if (paymentLinks.isNotEmpty()) {
                        item { EntitySectionHeader(title = "Payment links") }
                        items(paymentLinks, key = { "payment_${it.id}" }) { ref ->
                            EntityRow(
                                icon = { Icon(Icons.Default.Link, contentDescription = null) },
                                primary = "Payment link – ${ref.amount}",
                                secondary = ref.url,
                                a11y = "Insert payment link ${ref.amount}: ${ref.url}",
                                onClick = { onEntitySelected(ref) },
                            )
                        }
                    }
                    item { Spacer(Modifier.height(16.dp)) }
                }
            }
        }
    }
}

@Composable
private fun EntitySectionHeader(title: String) {
    Text(
        title,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(vertical = 6.dp),
    )
}

@Composable
private fun EntityRow(
    icon: @Composable () -> Unit,
    primary: String,
    secondary: String,
    a11y: String,
    onClick: () -> Unit,
) {
    OutlinedCard(
        onClick = onClick,
        modifier = Modifier
            .fillMaxWidth()
            .semantics {
                contentDescription = a11y
                role = Role.Button
            },
    ) {
        ListItem(
            leadingContent = {
                CompositionLocalProvider(
                    LocalContentColor provides MaterialTheme.colorScheme.onSurfaceVariant,
                ) { icon() }
            },
            headlineContent = {
                Text(
                    primary,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                )
            },
            supportingContent = {
                Text(
                    secondary,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                )
            },
        )
    }
}
