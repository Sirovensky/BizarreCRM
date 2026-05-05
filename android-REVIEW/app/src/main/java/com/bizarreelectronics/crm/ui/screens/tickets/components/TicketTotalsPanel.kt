package com.bizarreelectronics.crm.ui.screens.tickets.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.local.db.entities.TicketEntity
import com.bizarreelectronics.crm.data.remote.dto.PaymentSummary
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.theme.SuccessGreen
import com.bizarreelectronics.crm.util.formatAsMoney
import com.bizarreelectronics.crm.util.toCentsOrZero

/**
 * Financial summary panel for a ticket.
 *
 * Displays subtotal / tax / discount / deposit / balance rows. All money values
 * are sourced from [TicketEntity] (Long cents) for precision — never from API
 * Double fields directly. A separator + bold Total row anchors the bottom.
 *
 * @param ticket     Room entity providing cent-accurate money fields.
 * @param payments   Server-side payment list for computing the deposit/paid amount.
 */
@Composable
fun TicketTotalsPanel(
    ticket: TicketEntity,
    payments: List<PaymentSummary>,
    modifier: Modifier = Modifier,
) {
    val depositCents = payments.sumOf { (it.amount ?: 0.0).toCentsOrZero() }
    val balanceCents = (ticket.total - depositCents).coerceAtLeast(0L)

    BrandCard(modifier = modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                "Payment Summary",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(modifier = Modifier.height(8.dp))

            if (ticket.subtotal != 0L && ticket.subtotal != ticket.total) {
                TotalsRow("Subtotal", ticket.subtotal.formatAsMoney())
            }
            if (ticket.discount > 0L) {
                TotalsRow(
                    label = "Discount",
                    value = "-${ticket.discount.formatAsMoney()}",
                    valueColor = SuccessGreen,
                )
            }
            if (ticket.totalTax > 0L) {
                TotalsRow("Tax", ticket.totalTax.formatAsMoney())
            }

            HorizontalDivider(
                modifier = Modifier.padding(vertical = 6.dp),
                color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
            )

            Row(modifier = Modifier.fillMaxWidth()) {
                Text(
                    "Total",
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    ticket.total.formatAsMoney(),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                )
            }

            if (depositCents > 0L) {
                Spacer(modifier = Modifier.height(4.dp))
                TotalsRow(
                    label = "Paid / Deposit",
                    value = "-${depositCents.formatAsMoney()}",
                    valueColor = SuccessGreen,
                )
                HorizontalDivider(
                    modifier = Modifier.padding(vertical = 6.dp),
                    color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
                )
                Row(modifier = Modifier.fillMaxWidth()) {
                    Text(
                        "Balance Due",
                        modifier = Modifier.weight(1f),
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                        color = if (balanceCents > 0L) MaterialTheme.colorScheme.error
                        else SuccessGreen,
                    )
                    Text(
                        balanceCents.formatAsMoney(),
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Bold,
                        color = if (balanceCents > 0L) MaterialTheme.colorScheme.error
                        else SuccessGreen,
                    )
                }
            }
        }
    }
}

@Composable
private fun TotalsRow(
    label: String,
    value: String,
    valueColor: androidx.compose.ui.graphics.Color = MaterialTheme.colorScheme.onSurface,
) {
    Row(modifier = Modifier.fillMaxWidth()) {
        Text(
            label,
            modifier = Modifier.weight(1f),
            style = MaterialTheme.typography.bodyMedium,
        )
        Text(
            value,
            style = MaterialTheme.typography.bodyMedium,
            color = valueColor,
        )
    }
}
