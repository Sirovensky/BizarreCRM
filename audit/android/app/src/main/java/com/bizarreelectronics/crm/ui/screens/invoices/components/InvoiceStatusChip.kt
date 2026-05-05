package com.bizarreelectronics.crm.ui.screens.invoices.components

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.local.db.entities.InvoiceEntity
import com.bizarreelectronics.crm.ui.theme.ErrorRed
import com.bizarreelectronics.crm.ui.theme.SuccessGreen
import com.bizarreelectronics.crm.ui.theme.WarningAmber
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

/**
 * Derived payment/overdue state for a single invoice row.
 *
 * Computed from InvoiceEntity fields — no server round-trip required.
 */
sealed class InvoiceChipState {
    /** Invoice has outstanding balance and the due date is in the past. */
    data class Overdue(val daysLate: Long) : InvoiceChipState()
    /** Partially paid (0 < amountPaid < total). */
    data class PartiallyPaid(val percentPaid: Int) : InvoiceChipState()
    /** Fully paid. */
    data object Paid : InvoiceChipState()
    /** Draft / void or other non-payment state. */
    data class Other(val label: String) : InvoiceChipState()
}

/**
 * Derives [InvoiceChipState] from an [InvoiceEntity].
 *
 * Priority order:
 *  1. Voided → Other("Void")
 *  2. Draft   → Other("Draft")
 *  3. Paid    → Paid
 *  4. Overdue (amountDue > 0 + dueOn in the past) → Overdue(daysLate)
 *  5. Partial (0 < amountPaid < total)             → PartiallyPaid(%)
 *  6. Fallback                                     → Other(status)
 */
fun invoiceChipStateFor(invoice: InvoiceEntity): InvoiceChipState {
    val status = invoice.status.trim().lowercase()
    if (status == "voided" || status == "void") return InvoiceChipState.Other("Void")
    if (status == "draft") return InvoiceChipState.Other("Draft")
    if (invoice.amountDue <= 0L) return InvoiceChipState.Paid

    // Check overdue
    val dueOn = invoice.dueOn
    if (dueOn != null) {
        runCatching {
            val due = LocalDate.parse(dueOn.take(10), DateTimeFormatter.ISO_LOCAL_DATE)
            val today = LocalDate.now()
            if (due.isBefore(today)) {
                val days = ChronoUnit.DAYS.between(due, today)
                return InvoiceChipState.Overdue(days)
            }
        }
    }

    // Partial
    if (invoice.amountPaid > 0L && invoice.total > 0L) {
        val pct = ((invoice.amountPaid.toDouble() / invoice.total.toDouble()) * 100).toInt().coerceIn(1, 99)
        return InvoiceChipState.PartiallyPaid(pct)
    }

    return InvoiceChipState.Other(invoice.status.replaceFirstChar { it.uppercase() })
}

/**
 * Compact status chip rendered inline in an invoice list row.
 *
 * Color mapping:
 *  - Overdue        → red   (errorContainer / onErrorContainer)
 *  - PartiallyPaid  → amber (WarningAmber tint)
 *  - Paid           → green (SuccessGreen tint)
 *  - Other          → neutral (surfaceVariant / onSurfaceVariant)
 */
@Composable
fun InvoiceStatusChip(
    chipState: InvoiceChipState,
    modifier: Modifier = Modifier,
) {
    val (containerColor, textColor, label) = chipColors(chipState)
    Surface(
        modifier = modifier,
        shape = MaterialTheme.shapes.small,
        color = containerColor,
    ) {
        Text(
            text = label,
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
            style = MaterialTheme.typography.labelSmall,
            color = textColor,
            fontWeight = FontWeight.Medium,
        )
    }
}

private data class ChipVisual(val bg: Color, val fg: Color, val label: String)

@Composable
private fun chipColors(state: InvoiceChipState): ChipVisual {
    val scheme = MaterialTheme.colorScheme
    return when (state) {
        is InvoiceChipState.Overdue -> ChipVisual(
            bg = scheme.errorContainer,
            fg = scheme.onErrorContainer,
            label = "Overdue ${state.daysLate}d",
        )
        is InvoiceChipState.PartiallyPaid -> ChipVisual(
            bg = WarningAmber.copy(alpha = 0.18f),
            fg = WarningAmber,
            label = "Paid ${state.percentPaid}%",
        )
        is InvoiceChipState.Paid -> ChipVisual(
            bg = SuccessGreen.copy(alpha = 0.16f),
            fg = SuccessGreen,
            label = "Paid",
        )
        is InvoiceChipState.Other -> ChipVisual(
            bg = scheme.surfaceVariant,
            fg = scheme.onSurfaceVariant,
            label = state.label,
        )
    }
}
