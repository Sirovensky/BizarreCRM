package com.bizarreelectronics.crm.ui.screens.tickets.detail.tablet.cards

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.dto.PaymentSummary
import com.bizarreelectronics.crm.data.remote.dto.TicketDetail
import com.bizarreelectronics.crm.data.remote.dto.TicketDevice
import com.bizarreelectronics.crm.data.remote.dto.TicketDevicePart
import java.text.NumberFormat
import java.util.Locale

/**
 * Tablet ticket-detail Quote card.
 *
 * Collapsed: cream total `$XX.XX` only.
 * Expanded: itemised rows (qty / name + sku-meta / price / overflow `⋮`)
 * + qtotals (Subtotal / Discount / Tax / Grand) + qt-pay rows
 * (Deposit / Due on pickup) + cream Checkout CTA at the bottom.
 *
 * Card-internal expand state via [remember]; resets on configuration
 * change (acceptable for v1). Tapping Checkout invokes [onCheckout]
 * with the resolved due-on-pickup amount — host wires the navigation
 * via existing `onCheckout` screen callback in `TicketDetailScreen`.
 *
 * The typeahead add-row for new lines is NOT rendered here; it lands
 * as a sibling card (`QuoteAddRow`) in T-C6.
 *
 * @param ticketDetail authoritative DTO with subtotal / discount /
 *   total / payments. Null while ticket is still loading — collapsed
 *   shell renders a "loading" placeholder.
 * @param devices flattened-parts source. Each device's `parts` list is
 *   concatenated into the quote rows. Empty list shows an empty-state
 *   row with a hint to use the typeahead (T-C6).
 * @param onCheckout fires when the Checkout CTA is tapped — host
 *   forwards to the screen-level `onCheckout` callback (route into
 *   PosCart with this ticket's lines pre-loaded). Null hides the CTA.
 */
@Composable
internal fun QuoteCard(
    ticketDetail: TicketDetail?,
    devices: List<TicketDevice>,
    onCheckout: ((dueAmount: Double) -> Unit)? = null,
) {
    var expanded by remember { mutableStateOf(false) }
    val chevronRotation by animateFloatAsState(
        targetValue = if (expanded) 180f else 0f,
        animationSpec = tween(220),
        label = "quote_chevron",
    )

    val parts: List<TicketDevicePart> = remember(devices) {
        devices.flatMap { it.parts.orEmpty() }
    }
    val itemCount = parts.size
    val total = ticketDetail?.total ?: 0.0
    val subtotal = ticketDetail?.subtotal ?: 0.0
    val discount = ticketDetail?.discount ?: 0.0
    val tax = ticketDetail?.totalTax ?: 0.0
    val payments: List<PaymentSummary> = ticketDetail?.payments.orEmpty()
    val paid = payments.sumOf { it.amount ?: 0.0 }
    val due = (total - paid).coerceAtLeast(0.0)

    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp)) {
            // Header: Quote · N items + chevron
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "Quote · $itemCount item${if (itemCount == 1) "" else "s"}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f),
                )
                IconButton(
                    onClick = { expanded = !expanded },
                    modifier = Modifier
                        .size(36.dp)
                        .semantics {
                            contentDescription = if (expanded) "Collapse quote breakdown"
                            else "Expand quote breakdown"
                        },
                ) {
                    Icon(
                        Icons.Default.ExpandMore,
                        contentDescription = null,
                        modifier = Modifier.rotate(chevronRotation),
                    )
                }
            }

            // Collapsed body — total only (large cream).
            if (!expanded) {
                Text(
                    money(total),
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.padding(top = 4.dp),
                )
            }

            // Expanded body — line rows + totals + deposit/due + Checkout.
            AnimatedVisibility(visible = expanded) {
                Column(modifier = Modifier.padding(top = 6.dp)) {
                    QuoteRows(parts = parts)

                    Column(
                        modifier = Modifier.padding(top = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        TotalsRow("Subtotal", money(subtotal))
                        if (discount > 0.0) TotalsRow(
                            "Discount", "−${money(discount)}",
                            valueColor = MaterialTheme.colorScheme.tertiary,
                        )
                        if (tax > 0.0) TotalsRow("Tax", money(tax))
                        HorizontalDivider(
                            color = MaterialTheme.colorScheme.surfaceVariant,
                            modifier = Modifier.padding(vertical = 4.dp),
                        )
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                "Total",
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.SemiBold,
                            )
                            Text(
                                money(total),
                                style = MaterialTheme.typography.headlineSmall,
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.primary,
                            )
                        }
                    }

                    // Deposit / Due-on-pickup chips.
                    Column(
                        modifier = Modifier.padding(top = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        if (paid > 0.0) {
                            ChipRow("Paid", "${money(paid)} · ${payments.size} payment${if (payments.size == 1) "" else "s"}")
                        }
                        ChipRow(
                            "Due on pickup",
                            money(due),
                            emphasised = due > 0.0,
                        )
                    }

                    // Checkout CTA — full-width cream filled button.
                    if (onCheckout != null && due > 0.0) {
                        Surface(
                            color = MaterialTheme.colorScheme.primary,
                            contentColor = MaterialTheme.colorScheme.onPrimary,
                            shape = RoundedCornerShape(14.dp),
                            onClick = { onCheckout(due) },
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 12.dp)
                                .height(48.dp)
                                .semantics { contentDescription = "Checkout. Charge ${money(due)} now." },
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.Center,
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Icon(
                                    Icons.Default.ShoppingCart,
                                    contentDescription = null,
                                    modifier = Modifier.size(18.dp),
                                )
                                Box(modifier = Modifier.size(width = 10.dp, height = 1.dp))
                                Text(
                                    "Checkout",
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.SemiBold,
                                )
                                Box(modifier = Modifier.size(width = 8.dp, height = 1.dp))
                                Text(
                                    "· ${money(due)}",
                                    style = MaterialTheme.typography.titleMedium,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun QuoteRows(parts: List<TicketDevicePart>) {
    if (parts.isEmpty()) {
        Surface(
            color = MaterialTheme.colorScheme.surfaceVariant,
            shape = RoundedCornerShape(12.dp),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(
                "No quote lines yet — add a part or service via the row below.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(14.dp),
            )
        }
        return
    }

    Surface(
        color = MaterialTheme.colorScheme.surfaceVariant,
        shape = RoundedCornerShape(12.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column {
            parts.forEachIndexed { index, part ->
                if (index > 0) {
                    HorizontalDivider(
                        color = MaterialTheme.colorScheme.surface,
                        modifier = Modifier.padding(horizontal = 12.dp),
                    )
                }
                QuoteRow(part)
            }
        }
    }
}

@Composable
private fun QuoteRow(part: TicketDevicePart) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        // Quantity pill.
        Surface(
            color = MaterialTheme.colorScheme.surface,
            shape = RoundedCornerShape(6.dp),
            modifier = Modifier.size(width = 36.dp, height = 24.dp),
        ) {
            Box(contentAlignment = Alignment.Center) {
                Text(
                    "×${part.quantity ?: 1}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        Column(modifier = Modifier.weight(1f)) {
            Text(
                part.name ?: "(unnamed line)",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
            )
            part.sku?.takeIf { it.isNotBlank() }?.let { sku ->
                Text(
                    sku,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        Text(
            money(part.total ?: ((part.price ?: 0.0) * (part.quantity ?: 1))),
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.onSurface,
        )

        Icon(
            Icons.Default.MoreVert,
            contentDescription = "Line actions",
            modifier = Modifier.size(18.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun TotalsRow(
    label: String,
    value: String,
    valueColor: androidx.compose.ui.graphics.Color = MaterialTheme.colorScheme.onSurface,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            value,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium,
            color = valueColor,
        )
    }
}

@Composable
private fun ChipRow(label: String, value: String, emphasised: Boolean = false) {
    Surface(
        color = if (emphasised) MaterialTheme.colorScheme.primaryContainer
        else MaterialTheme.colorScheme.surfaceVariant,
        contentColor = if (emphasised) MaterialTheme.colorScheme.onPrimaryContainer
        else MaterialTheme.colorScheme.onSurfaceVariant,
        shape = RoundedCornerShape(10.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(label, style = MaterialTheme.typography.bodyMedium)
            Text(value, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
        }
    }
}

private val currencyFmt: NumberFormat = NumberFormat.getCurrencyInstance(Locale.US)
private fun money(value: Double): String = currencyFmt.format(value)
