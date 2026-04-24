package com.bizarreelectronics.crm.ui.screens.pos.components

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.GifBox
import androidx.compose.material.icons.filled.Payments
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.Receipt
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.CallSplit
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.api.PosApi
import com.bizarreelectronics.crm.ui.screens.pos.PosCartState
import com.bizarreelectronics.crm.ui.theme.SuccessGreen
import kotlinx.coroutines.launch
import java.util.Locale
import java.util.UUID

private sealed interface PaymentFlow {
    object None : PaymentFlow
    object Cash : PaymentFlow
    object Card : PaymentFlow
    object GiftCard : PaymentFlow
    object StoreCredit : PaymentFlow
    object Split : PaymentFlow
}

/**
 * POS payment ModalBottomSheet.
 *
 * Rows: Cash / Card (BlockChyp) / Google Pay / Gift Card / Store Credit /
 *       Check / ACH / Split / Invoice later.
 *
 * Plan §16.1 L1804-L1812.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PosPaymentSheet(
    cart: PosCartState,
    posApi: PosApi,
    onSaleComplete: (invoiceId: Long) -> Unit,
    onError: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)
    val scope = rememberCoroutineScope()
    var flow by remember { mutableStateOf<PaymentFlow>(PaymentFlow.None) }
    var isProcessing by remember { mutableStateOf(false) }
    var giftCardCode by remember { mutableStateOf("") }
    var storeCreditToApply by remember { mutableLongStateOf(0L) }
    var showSplitDialog by remember { mutableStateOf(false) }
    var giftCardResult by remember { mutableStateOf<String?>(null) }
    var cardResultText by remember { mutableStateOf<String?>(null) }

    val idempotencyKey = remember { UUID.randomUUID().toString() }

    suspend fun doSale(method: String, amountCents: Long) {
        isProcessing = true
        runCatching {
            posApi.completeSale(
                idempotencyKey = idempotencyKey,
                request = com.bizarreelectronics.crm.data.remote.api.PosSaleRequest(
                    idempotencyKey = idempotencyKey,
                    customerId = cart.customer?.id,
                    lines = cart.lines.map { line ->
                        com.bizarreelectronics.crm.data.remote.api.PosCartLineDto(
                            id = line.id,
                            type = line.type,
                            itemId = line.itemId,
                            name = line.name,
                            qty = line.qty,
                            unitPriceCents = line.unitPriceCents,
                            discountCents = line.discountCents,
                            taxClassId = line.taxClassId,
                            taxRate = line.taxRate,
                        )
                    },
                    cartDiscountCents = cart.discountCents,
                    tipCents = cart.tipCents,
                    paymentMethod = method,
                    paymentAmountCents = amountCents,
                ),
            )
        }.onSuccess { resp ->
            isProcessing = false
            if (resp.success && resp.data != null) {
                onSaleComplete(resp.data.invoiceId)
            } else {
                onError(resp.message ?: "Payment failed")
            }
        }.onFailure { e ->
            isProcessing = false
            onError(e.message ?: "Network error")
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(bottom = 32.dp),
        ) {
            Text(
                "Payment",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(horizontal = 24.dp, vertical = 12.dp),
            )

            // Total banner
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text("Total Due", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "$${String.format(Locale.US, "%.2f", cart.totalCents / 100.0)}",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            when (flow) {
                // ── Method selector ───────────────────────────────────────
                PaymentFlow.None -> {
                    PaymentMethodButton(icon = Icons.Default.Payments, label = "Cash") {
                        flow = PaymentFlow.Cash
                    }
                    PaymentMethodButton(icon = Icons.Default.CreditCard, label = "Card (BlockChyp)") {
                        flow = PaymentFlow.Card
                    }
                    PaymentMethodButton(icon = Icons.Default.PhoneAndroid, label = "Google Pay") {
                        // Google Pay stub — check isReadyToPay() at runtime
                        scope.launch { doSale("google_pay", cart.totalCents) }
                    }
                    PaymentMethodButton(icon = Icons.Default.GifBox, label = "Gift Card") {
                        flow = PaymentFlow.GiftCard
                    }
                    PaymentMethodButton(icon = Icons.Default.Person, label = "Store Credit") {
                        flow = PaymentFlow.StoreCredit
                    }
                    PaymentMethodButton(icon = Icons.Default.Receipt, label = "Check") {
                        scope.launch { doSale("check", cart.totalCents) }
                    }
                    PaymentMethodButton(icon = Icons.Default.Settings, label = "ACH / Bank Transfer") {
                        scope.launch { doSale("ach", cart.totalCents) }
                    }
                    PaymentMethodButton(icon = Icons.Default.CallSplit, label = "Split Tender") {
                        showSplitDialog = true
                    }
                    PaymentMethodButton(icon = Icons.Default.Description, label = "Invoice Later") {
                        scope.launch {
                            isProcessing = true
                            runCatching {
                                posApi.createInvoiceLater(
                                    idempotencyKey = idempotencyKey,
                                    request = com.bizarreelectronics.crm.data.remote.api.PosInvoiceLaterRequest(
                                        idempotencyKey = idempotencyKey,
                                        customerId = cart.customer?.id,
                                        lines = cart.lines.map { line ->
                                            com.bizarreelectronics.crm.data.remote.api.PosCartLineDto(
                                                id = line.id,
                                                type = line.type,
                                                itemId = line.itemId,
                                                name = line.name,
                                                qty = line.qty,
                                                unitPriceCents = line.unitPriceCents,
                                                discountCents = line.discountCents,
                                                taxClassId = line.taxClassId,
                                                taxRate = line.taxRate,
                                            )
                                        },
                                        cartDiscountCents = cart.discountCents,
                                        tipCents = cart.tipCents,
                                    )
                                )
                            }.onSuccess { resp ->
                                isProcessing = false
                                if (resp.success && resp.data != null) {
                                    onSaleComplete(resp.data.invoiceId)
                                } else {
                                    onError(resp.message ?: "Failed to create invoice")
                                }
                            }.onFailure { e ->
                                isProcessing = false
                                onError(e.message ?: "Network error")
                            }
                        }
                    }
                }

                // ── Cash ──────────────────────────────────────────────────
                PaymentFlow.Cash -> {
                    var cashCents by remember { mutableLongStateOf(0L) }
                    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        PosCashKeypad(
                            totalCents = cart.totalCents,
                            onCashEntered = { cashCents = it },
                        )
                        Button(
                            onClick = { scope.launch { doSale("cash", cart.totalCents) } },
                            enabled = cashCents >= cart.totalCents && !isProcessing,
                            modifier = Modifier.fillMaxWidth().height(52.dp),
                        ) {
                            Text("Complete Cash Payment")
                        }
                        OutlinedButton(
                            onClick = { flow = PaymentFlow.None },
                            modifier = Modifier.fillMaxWidth(),
                        ) { Text("Back") }
                    }
                }

                // ── Card (BlockChyp) ──────────────────────────────────────
                PaymentFlow.Card -> {
                    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        if (cardResultText != null) {
                            Text(cardResultText!!, color = SuccessGreen, style = MaterialTheme.typography.bodyMedium)
                        } else {
                            Card(
                                modifier = Modifier.fillMaxWidth(),
                                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
                            ) {
                                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Text("BlockChyp Terminal", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                                    Text(
                                        "Connect BlockChyp terminal to accept card payments.\n\n" +
                                            "TODO: integrate BlockChyp SDK — TransactionClient.charge(request)",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                            if (isProcessing) {
                                LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                                Text("Contacting terminal…", style = MaterialTheme.typography.bodySmall)
                            } else {
                                Button(
                                    onClick = {
                                        // Stub: in production call BlockChyp TransactionClient.charge(...)
                                        scope.launch { doSale("credit_card", cart.totalCents) }
                                    },
                                    modifier = Modifier.fillMaxWidth().height(52.dp),
                                ) { Text("Charge Card — ${String.format(Locale.US, "%.2f", cart.totalCents / 100.0)}") }
                            }
                        }
                        OutlinedButton(onClick = { flow = PaymentFlow.None }, modifier = Modifier.fillMaxWidth()) { Text("Back") }
                    }
                }

                // ── Gift Card ─────────────────────────────────────────────
                PaymentFlow.GiftCard -> {
                    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text("Gift Card Redemption", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                        if (giftCardResult != null) {
                            Text(giftCardResult!!, color = SuccessGreen)
                        } else {
                            OutlinedTextField(
                                value = giftCardCode,
                                onValueChange = { giftCardCode = it },
                                label = { Text("Gift Card Code") },
                                placeholder = { Text("Scan or enter code") },
                                singleLine = true,
                                modifier = Modifier.fillMaxWidth(),
                            )
                            if (isProcessing) {
                                LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                            } else {
                                Button(
                                    onClick = {
                                        scope.launch {
                                            isProcessing = true
                                            runCatching {
                                                posApi.redeemGiftCard(
                                                    com.bizarreelectronics.crm.data.remote.api.PosGiftCardRedeemRequest(
                                                        code = giftCardCode,
                                                        amountCents = cart.totalCents,
                                                    )
                                                )
                                            }.onSuccess { resp ->
                                                isProcessing = false
                                                if (resp.success && resp.data != null) {
                                                    val d = resp.data
                                                    giftCardResult = "Applied: $${String.format(Locale.US, "%.2f", d.appliedCents / 100.0)}" +
                                                        " · Balance remaining: $${String.format(Locale.US, "%.2f", d.remainingCents / 100.0)}"
                                                    if (d.appliedCents >= cart.totalCents) {
                                                        onSaleComplete(0L) // server will create invoice
                                                    }
                                                } else {
                                                    onError(resp.message ?: "Gift card error")
                                                }
                                            }.onFailure { e ->
                                                isProcessing = false
                                                onError(e.message ?: "Network error")
                                            }
                                        }
                                    },
                                    enabled = giftCardCode.isNotBlank(),
                                    modifier = Modifier.fillMaxWidth().height(52.dp),
                                ) { Text("Redeem Gift Card") }
                            }
                        }
                        OutlinedButton(onClick = { flow = PaymentFlow.None }, modifier = Modifier.fillMaxWidth()) { Text("Back") }
                    }
                }

                // ── Store Credit ──────────────────────────────────────────
                PaymentFlow.StoreCredit -> {
                    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text("Store Credit", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                        val balance = cart.customer?.storeCreditCents ?: 0L
                        val maxApply = minOf(balance, cart.totalCents)
                        if (cart.customer == null) {
                            Text("Attach a customer to use store credit.", color = MaterialTheme.colorScheme.error)
                        } else {
                            Text("Available credit: $${String.format(Locale.US, "%.2f", balance / 100.0)}")
                            Text("Apply: $${String.format(Locale.US, "%.2f", maxApply / 100.0)}", color = SuccessGreen)
                            if (!isProcessing) {
                                Button(
                                    onClick = { scope.launch { doSale("store_credit", maxApply) } },
                                    enabled = maxApply > 0,
                                    modifier = Modifier.fillMaxWidth().height(52.dp),
                                ) { Text("Apply Store Credit") }
                            } else {
                                LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                            }
                        }
                        OutlinedButton(onClick = { flow = PaymentFlow.None }, modifier = Modifier.fillMaxWidth()) { Text("Back") }
                    }
                }

                else -> Unit
            }

            if (isProcessing && flow == PaymentFlow.None) {
                LinearProgressIndicator(modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp))
            }
        }
    }

    if (showSplitDialog) {
        PosSplitTenderDialog(
            totalCents = cart.totalCents,
            onComplete = { entries ->
                showSplitDialog = false
                scope.launch {
                    // For split, we complete with the first method as primary
                    val primary = entries.firstOrNull()?.method?.lowercase()?.replace(" ", "_") ?: "cash"
                    doSale("split:${entries.joinToString(",") { "${it.method}:${it.amountCents}" }}", cart.totalCents)
                }
            },
            onDismiss = { showSplitDialog = false },
        )
    }
}

@Composable
private fun PaymentMethodButton(
    icon: ImageVector,
    label: String,
    onClick: () -> Unit,
) {
    Card(
        onClick = onClick,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 3.dp)
            .semantics(mergeDescendants = true) {
                contentDescription = "$label payment method"
                role = Role.Button
            },
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
            Text(label, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
        }
    }
}
