package com.bizarreelectronics.crm.ui.screens.tickets.create.steps

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.dto.CustomerListItem
import com.bizarreelectronics.crm.ui.screens.tickets.RepairCartItem
import com.bizarreelectronics.crm.ui.screens.tickets.TicketCreateSubStep
import java.text.NumberFormat
import java.util.Locale

private val reviewCurrencyFmt: NumberFormat = NumberFormat.getCurrencyInstance(Locale.US)
private fun reviewFmt(v: Double) = reviewCurrencyFmt.format(v)

/**
 * Step 7 — Review & create.
 *
 * Summarises all fields collected in steps 1-6 and provides:
 * - Edit-step jump chips for each section.
 * - "Create ticket" primary CTA that posts to `POST /tickets` via [onSubmit].
 * - Idempotency key is generated once in the ViewModel and reused on retry.
 * - Inline validation error when cart is empty or customer missing.
 *
 * Validation: [canSubmit] = cart non-empty AND (customer != null OR isWalkIn).
 */
@Composable
fun ReviewStepScreen(
    selectedCustomer: CustomerListItem?,
    isWalkIn: Boolean,
    cartItems: List<RepairCartItem>,
    taxRate: Double,
    cartDiscount: Double,
    cartDiscountType: String,
    depositAmount: Double,
    assigneeName: String?,
    urgency: String,
    dueDate: String?,
    intakePhotoCount: Int,
    isSubmitting: Boolean,
    onJumpToStep: (TicketCreateSubStep) -> Unit,
    onSubmit: () -> Unit,
    modifier: Modifier = Modifier,
) {
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
    val total by remember(taxable, taxRate) {
        derivedStateOf { taxable + taxable * taxRate }
    }

    val customerName = when {
        isWalkIn -> "Walk-in"
        selectedCustomer != null -> listOfNotNull(selectedCustomer.firstName, selectedCustomer.lastName).joinToString(" ").ifBlank { "Unknown" }
        else -> "No customer"
    }
    val canSubmit = cartItems.isNotEmpty() && (selectedCustomer != null || isWalkIn)

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // ── Customer ───────────────────────────────────────────────────
        item(key = "customer_section") {
            ReviewSection(
                title = "Customer",
                onEdit = { onJumpToStep(TicketCreateSubStep.CUSTOMER) },
            ) {
                Text(customerName, style = MaterialTheme.typography.bodyMedium)
                selectedCustomer?.phone?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall)
                }
            }
        }

        // ── Devices / services ─────────────────────────────────────────
        item(key = "devices_section") {
            ReviewSection(
                title = "Devices & Services (${cartItems.size})",
                onEdit = { onJumpToStep(TicketCreateSubStep.SERVICES) },
            ) {
                cartItems.forEach { item ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text(item.deviceName, style = MaterialTheme.typography.bodyMedium)
                            item.serviceName?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
                        }
                        Text(reviewFmt(item.lineTotal), style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }

        // ── Diagnostic ─────────────────────────────────────────────────
        item(key = "diag_section") {
            ReviewSection(
                title = "Diagnostic",
                onEdit = { onJumpToStep(TicketCreateSubStep.DIAGNOSTIC) },
            ) {
                Text("$intakePhotoCount photo(s) attached", style = MaterialTheme.typography.bodySmall)
            }
        }

        // ── Pricing ────────────────────────────────────────────────────
        item(key = "pricing_section") {
            ReviewSection(
                title = "Pricing",
                onEdit = { onJumpToStep(TicketCreateSubStep.PRICING) },
            ) {
                Text("Subtotal: ${reviewFmt(subtotal)}", style = MaterialTheme.typography.bodySmall)
                if (discountAmount > 0) Text("Discount: -${reviewFmt(discountAmount)}", style = MaterialTheme.typography.bodySmall)
                Text("Total: ${reviewFmt(total)}", style = MaterialTheme.typography.bodyMedium)
                if (depositAmount > 0) Text("Deposit: ${reviewFmt(depositAmount)}", style = MaterialTheme.typography.bodySmall)
            }
        }

        // ── Assignee ───────────────────────────────────────────────────
        item(key = "assignee_section") {
            ReviewSection(
                title = "Assignee",
                onEdit = { onJumpToStep(TicketCreateSubStep.ASSIGNEE) },
            ) {
                Text(assigneeName ?: "Unassigned", style = MaterialTheme.typography.bodyMedium)
                Text("Urgency: $urgency", style = MaterialTheme.typography.bodySmall)
                dueDate?.let { Text("Due: $it", style = MaterialTheme.typography.bodySmall) }
            }
        }

        // ── Submit CTA ─────────────────────────────────────────────────
        item(key = "cta") {
            if (!canSubmit) {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer),
                ) {
                    Text(
                        if (cartItems.isEmpty()) "Add at least one device/service before creating."
                        else "Select a customer or choose Walk-in.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onErrorContainer,
                        modifier = Modifier.padding(12.dp),
                    )
                }
            }
            Button(
                onClick = onSubmit,
                enabled = canSubmit && !isSubmitting,
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (isSubmitting) {
                    CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                    Spacer(Modifier.width(8.dp))
                }
                Text(if (isSubmitting) "Creating…" else "Create Ticket")
            }
        }
    }
}

// ── Private sub-composables ─────────────────────────────────────────────────

@Composable
private fun ReviewSection(
    title: String,
    onEdit: () -> Unit,
    content: @Composable ColumnScope.() -> Unit,
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(title, style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
                IconButton(onClick = onEdit, modifier = Modifier.size(32.dp)) {
                    Icon(Icons.Default.Edit, contentDescription = "Edit $title", modifier = Modifier.size(18.dp))
                }
            }
            content()
        }
    }
}
