package com.bizarreelectronics.crm.ui.screens.tickets.create.steps

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.screens.tickets.RepairCartItem
import java.text.NumberFormat
import java.util.Locale

private val currencyFmt: NumberFormat = NumberFormat.getCurrencyInstance(Locale.US)
private fun fmt(v: Double) = currencyFmt.format(v)

/** Threshold above which a discount reason is required. */
private const val DISCOUNT_REASON_THRESHOLD = 10.0

/**
 * Step 5 — Pricing summary & adjustments.
 *
 * Provides:
 * - Per-cart-item line totals (labor + parts).
 * - Cart-level discount (% or $) with reason required above [DISCOUNT_REASON_THRESHOLD].
 * - Live subtotal / tax / total recalculation via [derivedStateOf].
 * - Deposit toggle with amount field ("Collect now" or "Mark pending").
 *
 * Validation: always valid — pricing fields are pre-filled from service selection.
 */
@Composable
fun PricingStepScreen(
    cartItems: List<RepairCartItem>,
    taxRate: Double,
    cartDiscount: Double,
    cartDiscountType: String,
    cartDiscountReason: String,
    depositAmount: Double,
    collectDepositNow: Boolean,
    onCartDiscountChange: (Double, String) -> Unit,
    onCartDiscountReasonChange: (String) -> Unit,
    onDepositChange: (Double, Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    // Live-computed totals
    val subtotal by remember(cartItems) {
        derivedStateOf { cartItems.sumOf { it.lineTotal } }
    }
    val discountAmount by remember(cartDiscount, cartDiscountType, subtotal) {
        derivedStateOf {
            if (cartDiscountType == "percent") subtotal * (cartDiscount / 100.0)
            else cartDiscount
        }
    }
    val taxable by remember(subtotal, discountAmount) {
        derivedStateOf { (subtotal - discountAmount).coerceAtLeast(0.0) }
    }
    val taxAmount by remember(taxable, taxRate) {
        derivedStateOf { taxable * taxRate }
    }
    val total by remember(taxable, taxAmount) {
        derivedStateOf { taxable + taxAmount }
    }

    var discountInput by remember(cartDiscount) { mutableStateOf(if (cartDiscount > 0) cartDiscount.toString() else "") }
    var depositInput by remember(depositAmount) { mutableStateOf(if (depositAmount > 0) depositAmount.toString() else "") }

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // ── Line items ─────────────────────────────────────────────────
        item(key = "lines_header") {
            Text("Line items", style = MaterialTheme.typography.titleSmall)
        }
        items(cartItems, key = { "line_${it.id}" }) { item ->
            LineItemRow(item = item)
        }

        // ── Discount row ───────────────────────────────────────────────
        item(key = "discount") {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Discount", style = MaterialTheme.typography.titleSmall)
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    OutlinedTextField(
                        value = discountInput,
                        onValueChange = { raw ->
                            discountInput = raw
                            val parsed = raw.toDoubleOrNull() ?: 0.0
                            onCartDiscountChange(parsed, cartDiscountType)
                        },
                        modifier = Modifier.weight(1f),
                        label = { Text("Amount") },
                        prefix = { Text(if (cartDiscountType == "dollar") "$" else "") },
                        suffix = { Text(if (cartDiscountType == "percent") "%" else "") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        singleLine = true,
                    )
                    DiscountTypeToggle(
                        type = cartDiscountType,
                        onToggle = { newType ->
                            onCartDiscountChange(cartDiscount, newType)
                        },
                    )
                }
                if (cartDiscount > DISCOUNT_REASON_THRESHOLD) {
                    OutlinedTextField(
                        value = cartDiscountReason,
                        onValueChange = onCartDiscountReasonChange,
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("Reason (required for discount > ${"$%.0f".format(DISCOUNT_REASON_THRESHOLD)})") },
                        singleLine = true,
                    )
                }
            }
        }

        // ── Totals summary ─────────────────────────────────────────────
        item(key = "totals") {
            TotalsSummary(
                subtotal = subtotal,
                discountAmount = discountAmount,
                taxRate = taxRate,
                taxAmount = taxAmount,
                total = total,
            )
        }

        // ── Deposit toggle ─────────────────────────────────────────────
        item(key = "deposit") {
            DepositRow(
                depositInput = depositInput,
                collectDepositNow = collectDepositNow,
                onDepositInputChange = { raw ->
                    depositInput = raw
                    val parsed = raw.toDoubleOrNull() ?: 0.0
                    onDepositChange(parsed, collectDepositNow)
                },
                onCollectNowToggle = { onDepositChange(depositAmount, !collectDepositNow) },
            )
        }
    }
}

// ── Private sub-composables ─────────────────────────────────────────────────

@Composable
private fun LineItemRow(item: RepairCartItem) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Column(Modifier.weight(1f)) {
            Text(item.deviceName, style = MaterialTheme.typography.bodyMedium)
            item.serviceName?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
        }
        Text(fmt(item.lineTotal), style = MaterialTheme.typography.bodyMedium)
    }
    HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
}

@Composable
private fun DiscountTypeToggle(type: String, onToggle: (String) -> Unit) {
    Row {
        listOf("percent" to "%", "dollar" to "$").forEach { (value, label) ->
            FilterChip(
                selected = type == value,
                onClick = { onToggle(value) },
                label = { Text(label) },
            )
            Spacer(Modifier.width(4.dp))
        }
    }
}

@Composable
private fun TotalsSummary(
    subtotal: Double,
    discountAmount: Double,
    taxRate: Double,
    taxAmount: Double,
    total: Double,
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            TotalsLine("Subtotal", fmt(subtotal))
            if (discountAmount > 0) TotalsLine("Discount", "- ${fmt(discountAmount)}", isHighlight = true)
            TotalsLine("Tax (${"%.2f".format(taxRate * 100)}%)", fmt(taxAmount))
            HorizontalDivider()
            TotalsLine("Total", fmt(total), isStrong = true)
        }
    }
}

@Composable
private fun TotalsLine(label: String, value: String, isStrong: Boolean = false, isHighlight: Boolean = false) {
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(
            label,
            style = if (isStrong) MaterialTheme.typography.titleMedium else MaterialTheme.typography.bodyMedium,
        )
        Text(
            value,
            style = if (isStrong) MaterialTheme.typography.titleMedium else MaterialTheme.typography.bodyMedium,
            color = if (isHighlight) MaterialTheme.colorScheme.error else LocalContentColor.current,
        )
    }
}

@Composable
private fun DepositRow(
    depositInput: String,
    collectDepositNow: Boolean,
    onDepositInputChange: (String) -> Unit,
    onCollectNowToggle: () -> Unit,
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Deposit", style = MaterialTheme.typography.titleSmall)
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                OutlinedTextField(
                    value = depositInput,
                    onValueChange = onDepositInputChange,
                    modifier = Modifier.weight(1f),
                    label = { Text("Deposit amount") },
                    prefix = { Text("$") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    singleLine = true,
                )
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Switch(
                    checked = collectDepositNow,
                    onCheckedChange = { onCollectNowToggle() },
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    if (collectDepositNow) "Collect now (inline POS)" else "Mark as pending",
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
        }
    }
}
