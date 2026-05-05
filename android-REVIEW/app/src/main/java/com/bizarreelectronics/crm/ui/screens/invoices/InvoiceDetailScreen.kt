package com.bizarreelectronics.crm.ui.screens.invoices

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.theme.BrandMono
import com.bizarreelectronics.crm.util.HapticEvent
import com.bizarreelectronics.crm.util.LocalAppHapticController
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.entities.InvoiceEntity
import com.bizarreelectronics.crm.data.remote.api.InvoiceApi
import com.bizarreelectronics.crm.data.remote.dto.CreditNoteRequest
import com.bizarreelectronics.crm.data.remote.dto.InvoiceDetail
import com.bizarreelectronics.crm.data.remote.dto.InvoiceLineItem
import com.bizarreelectronics.crm.data.remote.dto.InvoicePayment
import com.bizarreelectronics.crm.data.remote.dto.IssueRefundRequest
import com.bizarreelectronics.crm.data.remote.dto.RecordPaymentRequest
import com.bizarreelectronics.crm.data.remote.dto.VoidInvoiceRequest
import com.bizarreelectronics.crm.data.repository.InvoiceRepository
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.BrandPrimaryButton
import com.bizarreelectronics.crm.ui.components.shared.BrandStatusBadge
import com.bizarreelectronics.crm.ui.components.shared.BrandTextButton
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ConfirmDialog
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import java.text.NumberFormat
import java.util.Locale
import com.bizarreelectronics.crm.ui.screens.invoices.components.InvoiceLineItemsTable
import com.bizarreelectronics.crm.ui.screens.invoices.components.InvoiceSendActions
import com.bizarreelectronics.crm.ui.screens.invoices.components.sendSms
import com.bizarreelectronics.crm.ui.screens.invoices.components.sendEmail
import com.bizarreelectronics.crm.ui.screens.invoices.components.shareText
import com.bizarreelectronics.crm.ui.screens.invoices.components.printInvoice
import com.bizarreelectronics.crm.ui.theme.SuccessGreen
import com.bizarreelectronics.crm.util.DateFormatter
import com.bizarreelectronics.crm.util.formatAsMoney
import com.bizarreelectronics.crm.util.toDollars
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import javax.inject.Inject

data class InvoiceDetailUiState(
    val invoice: InvoiceEntity? = null,
    // Online detail fields available when device is connected (phone, email, etc.)
    val onlineDetail: InvoiceDetail? = null,
    val lineItems: List<InvoiceLineItem> = emptyList(),
    val payments: List<InvoicePayment> = emptyList(),
    val onlineDetailMessage: String? = null,
    val isLoading: Boolean = true,
    val error: String? = null,
    val actionMessage: String? = null,
    val isActionInProgress: Boolean = false,
    // Bumps by 1 after each successful payment so the UI can close the dialog
    // via a LaunchedEffect keyed on this counter — NOT during the click handler
    // (that caused U1's race where the dialog closed before the mutation finished).
    val paymentSuccessCounter: Int = 0,
    // Server URL used by InvoiceSendActions for SMS/email/share/print links.
    val serverUrl: String? = null,
    // Credit-note success counter — bumps on successful POST, closes the dialog.
    val creditNoteSuccessCounter: Int = 0,
)

@HiltViewModel
class InvoiceDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val invoiceRepository: InvoiceRepository,
    private val invoiceApi: InvoiceApi,
) : ViewModel() {

    private val invoiceId: Long = savedStateHandle.get<String>("id")?.toLongOrNull() ?: 0L

    private val _state = MutableStateFlow(InvoiceDetailUiState())
    val state = _state.asStateFlow()

    init {
        loadInvoice()
    }

    fun loadInvoice() {
        // Collect entity from repository (cached + background refresh)
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            invoiceRepository.getInvoice(invoiceId)
                .catch { e ->
                    _state.value = _state.value.copy(
                        isLoading = false,
                        error = e.message ?: "Failed to load invoice",
                    )
                }
                .collectLatest { entity ->
                    _state.value = _state.value.copy(
                        invoice = entity,
                        isLoading = false,
                    )
                }
        }
        // Fetch line items and payments from API (online-only)
        loadOnlineDetails()
    }

    private fun loadOnlineDetails() {
        viewModelScope.launch {
            try {
                val response = invoiceApi.getInvoice(invoiceId)
                val detail = response.data?.invoice
                _state.value = _state.value.copy(
                    onlineDetail = detail,
                    lineItems = detail?.lineItems ?: emptyList(),
                    payments = detail?.payments ?: emptyList(),
                    onlineDetailMessage = null,
                )
            } catch (_: Exception) {
                _state.value = _state.value.copy(
                    onlineDetail = null,
                    lineItems = emptyList(),
                    payments = emptyList(),
                    onlineDetailMessage = "Line items available when online",
                )
            }
        }
    }

    /**
     * §7.4 — Record a payment against this invoice.
     *
     * @param amount        Dollar amount to record (must be > 0 and ≤ amountDue).
     * @param method        Payment method key (e.g. "cash", "credit_card", "check").
     * @param notes         Optional free-text note attached to the payment record.
     * @param reference     Optional reference string (check #, card last-4, txn ID).
     */
    fun recordPayment(
        amount: Double,
        method: String,
        notes: String? = null,
        reference: String? = null,
    ) {
        // U1 fix: hard guard against re-entry so that a double-tap while the
        // coroutine is in flight can't enqueue a second POST /payments.
        if (_state.value.isActionInProgress) return
        viewModelScope.launch {
            _state.value = _state.value.copy(isActionInProgress = true)
            try {
                val request = RecordPaymentRequest(
                    amount = amount,
                    method = method,
                    notes = notes?.takeIf { it.isNotBlank() },
                    transactionId = reference?.takeIf { it.isNotBlank() },
                )
                invoiceApi.recordPayment(invoiceId, request)
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Payment of $${"%.2f".format(amount)} recorded",
                    paymentSuccessCounter = _state.value.paymentSuccessCounter + 1,
                )
                // AND-20260414-M8: refresh the InvoiceEntity through the
                // repository so list screens + this detail's Room flow pick up
                // the new status/amountPaid/amountDue immediately. Previously
                // only line items + payments were reloaded, so the entity
                // cache stayed stale and the badge/bottom bar lied.
                runCatching { invoiceRepository.refreshInvoiceDetail(invoiceId) }
                loadOnlineDetails()
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Failed to record payment. You must be online for financial operations.",
                )
            }
        }
    }

    fun voidInvoice() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isActionInProgress = true)
            try {
                invoiceApi.voidInvoice(invoiceId)
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Invoice voided",
                )
                // AND-20260414-M8: same as payment — refresh the entity so the
                // Voided status lands on the Room flow before the user sees stale UI.
                runCatching { invoiceRepository.refreshInvoiceDetail(invoiceId) }
                loadOnlineDetails()
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Failed to void invoice. You must be online for financial operations.",
                )
            }
        }
    }

    fun issueRefund(amount: Double, reason: String?) {
        if (_state.value.isActionInProgress) return
        viewModelScope.launch {
            _state.value = _state.value.copy(isActionInProgress = true)
            try {
                val request = IssueRefundRequest(invoiceId = invoiceId, amount = amount, reason = reason)
                invoiceApi.issueRefund(request)
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Refund of $${"%.2f".format(amount)} issued.",
                )
                runCatching { invoiceRepository.refreshInvoiceDetail(invoiceId) }
                loadOnlineDetails()
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    // 404 → endpoint not deployed yet — surface gracefully.
                    actionMessage = "Refund endpoint unavailable. Try again when the server is updated.",
                )
            }
        }
    }

    fun cloneInvoice() {
        if (_state.value.isActionInProgress) return
        viewModelScope.launch {
            _state.value = _state.value.copy(isActionInProgress = true)
            try {
                invoiceApi.cloneInvoice(invoiceId)
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Invoice cloned as a new Draft.",
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Clone endpoint unavailable. Try again when the server is updated.",
                )
            }
        }
    }

    /**
     * POST /invoices/:id/credit-note — creates a credit-note invoice.
     * Server requires amount > 0 and a non-blank reason.
     * Callers close the dialog via [creditNoteSuccessCounter] LaunchedEffect.
     */
    fun createCreditNote(amount: Double, reason: String) {
        if (_state.value.isActionInProgress) return
        viewModelScope.launch {
            _state.value = _state.value.copy(isActionInProgress = true)
            try {
                val request = CreditNoteRequest(amount = amount, reason = reason)
                invoiceApi.createCreditNote(invoiceId, request)
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Credit note of $${"%.2f".format(amount)} created.",
                    creditNoteSuccessCounter = _state.value.creditNoteSuccessCounter + 1,
                )
                runCatching { invoiceRepository.refreshInvoiceDetail(invoiceId) }
                loadOnlineDetails()
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Credit note endpoint unavailable. Try again when the server is updated.",
                )
            }
        }
    }

    /**
     * POST /invoices/:id/void with an optional reason string.
     * Replaces the existing [voidInvoice] call when a reason is provided.
     * Keeps [voidInvoice] for back-compat.
     */
    fun voidInvoiceWithReason(reason: String?) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isActionInProgress = true)
            try {
                if (reason.isNullOrBlank()) {
                    invoiceApi.voidInvoice(invoiceId)
                } else {
                    invoiceApi.voidInvoiceWithReason(invoiceId, VoidInvoiceRequest(reason = reason))
                }
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Invoice voided.",
                )
                runCatching { invoiceRepository.refreshInvoiceDetail(invoiceId) }
                loadOnlineDetails()
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Failed to void invoice. You must be online for financial operations.",
                )
            }
        }
    }

    fun clearActionMessage() {
        _state.value = _state.value.copy(actionMessage = null)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InvoiceDetailScreen(
    invoiceId: Long,
    onBack: () -> Unit,
    onNavigateToTicket: ((Long) -> Unit)? = null,
    viewModel: InvoiceDetailViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val invoice = state.invoice

    val context = androidx.compose.ui.platform.LocalContext.current

    // U13 fix: rememberSaveable so rotations / dialog dismissals don't reset these.
    var showPaymentDialog by rememberSaveable { mutableStateOf(false) }
    var showVoidConfirm by rememberSaveable { mutableStateOf(false) }
    var showRefundDialog by rememberSaveable { mutableStateOf(false) }
    var showOverflowMenu by remember { mutableStateOf(false) }
    var paymentAmount by rememberSaveable { mutableStateOf("") }
    var paymentMethod by rememberSaveable { mutableStateOf("cash") }
    // §7.4 — notes + reference fields added to payment dialog
    var paymentNotes by rememberSaveable { mutableStateOf("") }
    var paymentReference by rememberSaveable { mutableStateOf("") }
    var showMethodDropdown by remember { mutableStateOf(false) }
    var refundAmount by rememberSaveable { mutableStateOf("") }
    var refundReason by rememberSaveable { mutableStateOf("") }
    // Credit note dialog state
    var showCreditNoteDialog by rememberSaveable { mutableStateOf(false) }
    var creditNoteAmount by rememberSaveable { mutableStateOf("") }
    var creditNoteReason by rememberSaveable { mutableStateOf("") }
    // Send-to-customer confirm dialog
    var showSendConfirm by rememberSaveable { mutableStateOf(false) }
    var pendingSendType by rememberSaveable { mutableStateOf("") } // "sms" | "email"
    // Void with reason state
    var voidReason by rememberSaveable { mutableStateOf("") }

    val snackbarHostState = remember { SnackbarHostState() }
    val hapticCtrl = LocalAppHapticController.current

    // U1 fix: dialog is closed from a LaunchedEffect keyed on the VM's success
    // counter, never from the click handler. This guarantees the dialog stays
    // open until the mutation actually succeeds.
    // §69.1 — Payment success → CONFIRM + extended 60ms pulse.
    LaunchedEffect(state.paymentSuccessCounter) {
        if (state.paymentSuccessCounter > 0) {
            hapticCtrl?.fire(HapticEvent.PaymentSuccess)
            showPaymentDialog = false
            paymentAmount = ""
            paymentMethod = "cash"
            // §7.4 — clear new fields on payment success
            paymentNotes = ""
            paymentReference = ""
        }
    }

    // Close credit-note dialog on success
    LaunchedEffect(state.creditNoteSuccessCounter) {
        if (state.creditNoteSuccessCounter > 0) {
            showCreditNoteDialog = false
            creditNoteAmount = ""
            creditNoteReason = ""
        }
    }

    val paymentMethods = listOf("cash", "credit_card", "debit_card", "check", "zelle", "venmo", "paypal", "other")
    val paymentMethodLabels = mapOf(
        "cash" to "Cash",
        "credit_card" to "Credit Card",
        "debit_card" to "Debit Card",
        "check" to "Check",
        "zelle" to "Zelle",
        "venmo" to "Venmo",
        "paypal" to "PayPal",
        "other" to "Other",
    )

    LaunchedEffect(state.actionMessage) {
        state.actionMessage?.let { message ->
            snackbarHostState.showSnackbar(message)
            viewModel.clearActionMessage()
        }
    }

    // Payment dialog
    if (showPaymentDialog) {
        AlertDialog(
            onDismissRequest = {
                showPaymentDialog = false
                paymentAmount = ""
                paymentMethod = "cash"
                // §7.4 — clear new fields on dialog dismiss
                paymentNotes = ""
                paymentReference = ""
            },
            containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
            title = { Text("Record Payment", style = MaterialTheme.typography.titleMedium) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    // Convert stored cents back to a Double dollars value for
                    // comparison against the user's text-field input.
                    val amountDue = (invoice?.amountDue ?: 0L).toDollars()
                    val parsedAmount = paymentAmount.toDoubleOrNull()
                    // U10 fix: explicitly surface "must be > 0" and "<= amountDue" errors.
                    val amountError: String? = when {
                        paymentAmount.isBlank() -> null
                        parsedAmount == null -> "Enter a valid amount"
                        parsedAmount <= 0.0 -> "Amount must be greater than $0.00"
                        parsedAmount > amountDue -> "Amount cannot exceed $${"%.2f".format(amountDue)}"
                        else -> null
                    }

                    OutlinedTextField(
                        value = paymentAmount,
                        onValueChange = { value ->
                            if (value.isEmpty() || value.matches(Regex("^\\d*\\.?\\d{0,2}$"))) {
                                paymentAmount = value
                            }
                        },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("Amount") },
                        // CROSS32-ext: unified money-input affordance — $ leadingIcon
                        // + "0.00" placeholder to match ticket wizard / inventory /
                        // expense create sites. Tenant currency is USD-only today;
                        // non-USD hardening tracked as CROSS32-i18n.
                        leadingIcon = {
                            Text(
                                "$",
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        },
                        placeholder = { Text("0.00") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        singleLine = true,
                        isError = amountError != null,
                        supportingText = {
                            if (amountError != null) {
                                Text(amountError, color = MaterialTheme.colorScheme.error)
                            }
                        },
                    )

                    // Pre-fill with amount due
                    if (paymentAmount.isEmpty() && invoice != null && invoice.amountDue > 0) {
                        val dueDollars = invoice.amountDue.toDollars()
                        BrandTextButton(
                            onClick = { paymentAmount = "%.2f".format(dueDollars) },
                        ) {
                            Text("Fill remaining: ${invoice.amountDue.formatAsMoney()}")
                        }
                    }

                    Box {
                        OutlinedTextField(
                            value = paymentMethodLabels[paymentMethod] ?: paymentMethod,
                            onValueChange = {},
                            modifier = Modifier.fillMaxWidth(),
                            label = { Text("Method") },
                            readOnly = true,
                            trailingIcon = {
                                IconButton(onClick = { showMethodDropdown = true }) {
                                    Icon(Icons.Default.ArrowDropDown, contentDescription = "Select method")
                                }
                            },
                        )
                        DropdownMenu(
                            expanded = showMethodDropdown,
                            onDismissRequest = { showMethodDropdown = false },
                        ) {
                            paymentMethods.forEach { method ->
                                DropdownMenuItem(
                                    text = { Text(paymentMethodLabels[method] ?: method) },
                                    onClick = {
                                        paymentMethod = method
                                        showMethodDropdown = false
                                    },
                                )
                            }
                        }
                    }

                    // §7.4 — Reference field: check number, card last-4, txn ID.
                    // Shown for non-cash methods where a reference is meaningful.
                    val showReferenceField = paymentMethod in listOf(
                        "check", "credit_card", "debit_card", "zelle", "venmo", "paypal", "other",
                    )
                    if (showReferenceField) {
                        val referencePlaceholder = when (paymentMethod) {
                            "check"       -> "Check number"
                            "credit_card",
                            "debit_card"  -> "Card last 4 digits"
                            "zelle",
                            "venmo",
                            "paypal"      -> "Transaction ID"
                            else          -> "Reference / ID"
                        }
                        OutlinedTextField(
                            value = paymentReference,
                            onValueChange = { paymentReference = it },
                            modifier = Modifier.fillMaxWidth(),
                            label = { Text("Reference (optional)") },
                            placeholder = { Text(referencePlaceholder) },
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Text),
                        )
                    }

                    // §7.4 — Notes field: free-text annotation on the payment record.
                    OutlinedTextField(
                        value = paymentNotes,
                        onValueChange = { paymentNotes = it },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("Notes (optional)") },
                        placeholder = { Text("e.g. \"Left in cash drawer\"") },
                        singleLine = false,
                        maxLines = 3,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Text),
                    )

                    // §7.4 — Cash change calculator: shown when cash amount > balance due.
                    // Allows staff to enter the tendered amount and see the change owed.
                    if (paymentMethod == "cash") {
                        val amountDueDollars = (invoice?.amountDue ?: 0L).toDollars()
                        val parsedForChange = paymentAmount.toDoubleOrNull()
                        if (parsedForChange != null && parsedForChange > amountDueDollars && amountDueDollars > 0.0) {
                            val change = parsedForChange - amountDueDollars
                            Surface(
                                modifier = Modifier.fillMaxWidth(),
                                color = MaterialTheme.colorScheme.secondaryContainer,
                                shape = MaterialTheme.shapes.small,
                            ) {
                                Row(
                                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Text(
                                        text = "Change due",
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = MaterialTheme.colorScheme.onSecondaryContainer,
                                    )
                                    Text(
                                        text = "\$${String.format("%.2f", change)}",
                                        style = MaterialTheme.typography.titleMedium.copy(
                                            fontWeight = FontWeight.Bold,
                                        ),
                                        color = MaterialTheme.colorScheme.onSecondaryContainer,
                                    )
                                }
                            }
                        }
                    }
                }
            },
            confirmButton = {
                // Convert stored cents back to dollars for comparison with the
                // user-typed amount; see the matching comment in the dialog body.
                val amountDue = (invoice?.amountDue ?: 0L).toDollars()
                val parsedAmount = paymentAmount.toDoubleOrNull()
                // §7.4 — cash payments allow amount > amountDue (change given back);
                // other methods must not exceed the balance due.
                val isAmountValid = parsedAmount != null &&
                    parsedAmount > 0.0 &&
                    (paymentMethod == "cash" || parsedAmount <= amountDue)
                // Effective amount credited = min(entered, amountDue) for cash.
                val effectiveAmount = if (paymentMethod == "cash" && parsedAmount != null && parsedAmount > amountDue) {
                    amountDue
                } else {
                    parsedAmount ?: 0.0
                }
                TextButton(
                    onClick = {
                        // U1 fix: we no longer close the dialog here. We call
                        // recordPayment, and a LaunchedEffect closes the dialog
                        // ONLY after the mutation succeeds.
                        if (isAmountValid && !state.isActionInProgress) {
                            viewModel.recordPayment(
                                amount = effectiveAmount,
                                method = paymentMethod,
                                notes = paymentNotes.takeIf { it.isNotBlank() },
                                reference = paymentReference.takeIf { it.isNotBlank() },
                            )
                        }
                    },
                    // U1 fix: disable while the mutation is in flight so a
                    // double-tap cannot enqueue a second payment.
                    enabled = isAmountValid && !state.isActionInProgress,
                ) {
                    if (state.isActionInProgress) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(16.dp),
                            strokeWidth = 2.dp,
                            color = MaterialTheme.colorScheme.onPrimary,
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Recording...")
                    } else {
                        Text("Record")
                    }
                }
            },
            dismissButton = {
                TextButton(
                    onClick = {
                        showPaymentDialog = false
                        paymentAmount = ""
                        paymentMethod = "cash"
                        // §7.4 — clear new fields on cancel
                        paymentNotes = ""
                        paymentReference = ""
                    },
                    colors = ButtonDefaults.textButtonColors(
                        contentColor = MaterialTheme.colorScheme.secondary, // teal
                    ),
                ) {
                    Text("Cancel")
                }
            },
        )
    }

    // Refund dialog
    if (showRefundDialog) {
        val totalPaidDollars = (invoice?.amountPaid ?: 0L).toDollars()
        AlertDialog(
            onDismissRequest = { showRefundDialog = false; refundAmount = "" },
            containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
            title = { Text("Issue Refund", style = MaterialTheme.typography.titleMedium) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    val parsedRefund = refundAmount.toDoubleOrNull()
                    val refundError: String? = when {
                        refundAmount.isBlank() -> null
                        parsedRefund == null -> "Enter a valid amount"
                        parsedRefund <= 0.0 -> "Amount must be greater than $0.00"
                        parsedRefund > totalPaidDollars -> "Cannot exceed amount paid ($${"%.2f".format(totalPaidDollars)})"
                        else -> null
                    }
                    OutlinedTextField(
                        value = refundAmount,
                        onValueChange = { v ->
                            if (v.isEmpty() || v.matches(Regex("^\\d*\\.?\\d{0,2}$"))) refundAmount = v
                        },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("Refund amount") },
                        leadingIcon = { Text("$", color = MaterialTheme.colorScheme.onSurfaceVariant) },
                        placeholder = { Text("0.00") },
                        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        singleLine = true,
                        isError = refundError != null,
                        supportingText = {
                            if (refundError != null) Text(refundError, color = MaterialTheme.colorScheme.error)
                        },
                    )
                    OutlinedTextField(
                        value = refundReason,
                        onValueChange = { refundReason = it },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("Reason (optional)") },
                        singleLine = true,
                    )
                }
            },
            confirmButton = {
                val parsedRefund = refundAmount.toDoubleOrNull()
                val isValid = parsedRefund != null && parsedRefund > 0.0 && parsedRefund <= totalPaidDollars
                TextButton(
                    onClick = {
                        if (isValid && parsedRefund != null) {
                            viewModel.issueRefund(parsedRefund, refundReason.ifBlank { null })
                            showRefundDialog = false
                            refundAmount = ""
                            refundReason = ""
                        }
                    },
                    enabled = isValid && !state.isActionInProgress,
                ) { Text("Issue Refund") }
            },
            dismissButton = {
                TextButton(onClick = { showRefundDialog = false; refundAmount = "" }) { Text("Cancel") }
            },
        )
    }

    // Void confirmation — migrated to ConfirmDialog(isDestructive = true)
    if (showVoidConfirm) {
        ConfirmDialog(
            title = "Void Invoice",
            message = "Are you sure you want to void this invoice? This will restore stock and mark all payments as voided. This action cannot be undone.",
            confirmLabel = "Void Invoice",
            onConfirm = {
                showVoidConfirm = false
                viewModel.voidInvoiceWithReason(voidReason.ifBlank { null })
            },
            onDismiss = {
                showVoidConfirm = false
                voidReason = ""
            },
            isDestructive = true,
        )
    }

    // Credit note dialog
    if (showCreditNoteDialog) {
        val invoiceTotal = (invoice?.total ?: 0L).toDollars()
        AlertDialog(
            onDismissRequest = {
                showCreditNoteDialog = false
                creditNoteAmount = ""
                creditNoteReason = ""
            },
            containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
            title = { Text("Credit Note", style = MaterialTheme.typography.titleMedium) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    val parsedAmt = creditNoteAmount.toDoubleOrNull()
                    val amtError: String? = when {
                        creditNoteAmount.isBlank() -> null
                        parsedAmt == null -> "Enter a valid amount"
                        parsedAmt <= 0.0 -> "Amount must be greater than \$0.00"
                        parsedAmt > invoiceTotal -> "Cannot exceed invoice total ($${"%.2f".format(invoiceTotal)})"
                        else -> null
                    }
                    OutlinedTextField(
                        value = creditNoteAmount,
                        onValueChange = { v ->
                            if (v.isEmpty() || v.matches(Regex("^\\d*\\.?\\d{0,2}$"))) creditNoteAmount = v
                        },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("Amount") },
                        leadingIcon = { Text("\$", color = MaterialTheme.colorScheme.onSurfaceVariant) },
                        placeholder = { Text("0.00") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        singleLine = true,
                        isError = amtError != null,
                        supportingText = {
                            if (amtError != null) Text(amtError, color = MaterialTheme.colorScheme.error)
                        },
                    )
                    OutlinedTextField(
                        value = creditNoteReason,
                        onValueChange = { creditNoteReason = it },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("Reason *") },
                        singleLine = true,
                        isError = creditNoteReason.isBlank() && creditNoteAmount.isNotBlank(),
                        supportingText = {
                            if (creditNoteReason.isBlank() && creditNoteAmount.isNotBlank()) {
                                Text("Reason is required", color = MaterialTheme.colorScheme.error)
                            }
                        },
                    )
                }
            },
            confirmButton = {
                val parsedAmt = creditNoteAmount.toDoubleOrNull()
                val isValid = parsedAmt != null && parsedAmt > 0.0 &&
                    parsedAmt <= invoiceTotal && creditNoteReason.isNotBlank()
                TextButton(
                    onClick = {
                        if (isValid && parsedAmt != null && !state.isActionInProgress) {
                            viewModel.createCreditNote(parsedAmt, creditNoteReason)
                        }
                    },
                    enabled = isValid && !state.isActionInProgress,
                ) {
                    if (state.isActionInProgress) {
                        CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Creating…")
                    } else {
                        Text("Create Note")
                    }
                }
            },
            dismissButton = {
                TextButton(
                    onClick = {
                        showCreditNoteDialog = false
                        creditNoteAmount = ""
                        creditNoteReason = ""
                    },
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.secondary),
                ) { Text("Cancel") }
            },
        )
    }

    // Send-to-customer confirm dialog
    if (showSendConfirm) {
        val typeLabel = if (pendingSendType == "sms") "SMS" else "email"
        val phone = state.onlineDetail?.customerPhone
        val email = state.onlineDetail?.customerEmail
        val invNum = invoice?.orderId?.ifBlank { invoice.id.toString() } ?: ""
        ConfirmDialog(
            title = "Send invoice by $typeLabel?",
            message = "Send invoice $invNum to ${state.onlineDetail?.customerName ?: "customer"} by $typeLabel? A message with a payment link will be sent.",
            confirmLabel = "Send",
            onConfirm = {
                showSendConfirm = false
                if (pendingSendType == "sms") {
                    val link = if (!state.serverUrl.isNullOrBlank()) "${state.serverUrl}/invoices/$invNum" else null
                    sendSms(context, phone, invNum, link)
                } else {
                    val link = if (!state.serverUrl.isNullOrBlank()) "${state.serverUrl}/invoices/$invNum" else null
                    sendEmail(context, email, invNum, link)
                }
                pendingSendType = ""
            },
            onDismiss = { showSendConfirm = false; pendingSendType = "" },
        )
    }

    Scaffold(
        // D5-8: keep the payment-amount and reference inputs visible when the
        // soft keyboard opens on the record-payment dialog path.
        modifier = Modifier.imePadding(),
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            BrandTopAppBar(
                title = invoice?.orderId?.ifBlank { "INV-$invoiceId" } ?: "INV-$invoiceId",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                },
                actions = {
                    if (invoice != null && !invoice.status.equals("Voided", ignoreCase = true)) {
                        IconButton(onClick = { showVoidConfirm = true }) {
                            Icon(
                                Icons.Default.Block,
                                contentDescription = "Void",
                                tint = MaterialTheme.colorScheme.error,
                            )
                        }
                    }
                    // Overflow menu: Refund / Clone / Send / Share / Print
                    Box {
                        IconButton(onClick = { showOverflowMenu = true }) {
                            Icon(Icons.Default.MoreVert, contentDescription = "More actions")
                        }
                        DropdownMenu(
                            expanded = showOverflowMenu,
                            onDismissRequest = { showOverflowMenu = false },
                        ) {
                            if (invoice != null && invoice.amountPaid > 0) {
                                DropdownMenuItem(
                                    text = { Text("Issue Refund") },
                                    leadingIcon = { Icon(Icons.Default.Undo, contentDescription = null) },
                                    onClick = { showOverflowMenu = false; showRefundDialog = true },
                                )
                                DropdownMenuItem(
                                    text = { Text("Credit Note") },
                                    leadingIcon = { Icon(Icons.Default.NoteAdd, contentDescription = null) },
                                    onClick = { showOverflowMenu = false; showCreditNoteDialog = true },
                                )
                            }
                            DropdownMenuItem(
                                text = { Text("Clone Invoice") },
                                leadingIcon = { Icon(Icons.Default.ContentCopy, contentDescription = null) },
                                onClick = {
                                    showOverflowMenu = false
                                    viewModel.cloneInvoice()
                                },
                            )
                            HorizontalDivider()
                            val invNum = invoice?.orderId ?: invoiceId.toString()
                            // Phone/email from online detail (available when connected); null disables the action.
                            val phone = state.onlineDetail?.customerPhone
                            val email = state.onlineDetail?.customerEmail
                            val url = state.serverUrl
                            DropdownMenuItem(
                                text = { Text("Send SMS") },
                                leadingIcon = { Icon(Icons.Default.Sms, contentDescription = null) },
                                onClick = {
                                    showOverflowMenu = false
                                    pendingSendType = "sms"
                                    showSendConfirm = true
                                },
                                enabled = !phone.isNullOrBlank(),
                            )
                            DropdownMenuItem(
                                text = { Text("Send Email") },
                                leadingIcon = { Icon(Icons.Default.Email, contentDescription = null) },
                                onClick = {
                                    showOverflowMenu = false
                                    pendingSendType = "email"
                                    showSendConfirm = true
                                },
                                enabled = !email.isNullOrBlank(),
                            )
                            DropdownMenuItem(
                                text = { Text("Share") },
                                leadingIcon = { Icon(Icons.Default.Share, null) },
                                onClick = {
                                    showOverflowMenu = false
                                    val link = if (!url.isNullOrBlank()) "$url/invoices/$invNum" else null
                                    shareText(context, invNum, link)
                                },
                            )
                            DropdownMenuItem(
                                text = { Text("Print") },
                                leadingIcon = { Icon(Icons.Default.Print, null) },
                                onClick = {
                                    showOverflowMenu = false
                                    val link = if (!url.isNullOrBlank()) "$url/invoices/$invNum" else null
                                    printInvoice(context, invNum, link)
                                },
                            )
                        }
                    }
                },
            )
        },
        bottomBar = {
            val amountDueCents = invoice?.amountDue ?: 0L
            if (amountDueCents > 0 && invoice?.status?.equals("Voided", ignoreCase = true) != true) {
                BottomAppBar {
                    // CROSS48-adopt-more: bottom-sticky Record Payment CTA
                    // migrated to BrandPrimaryButton so the primary filled
                    // hierarchy matches every other screen's dominant action.
                    BrandPrimaryButton(
                        onClick = { showPaymentDialog = true },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp),
                        enabled = !state.isActionInProgress,
                    ) {
                        // decorative — Button's "Record Payment (…)" Text supplies the accessible name
                        Icon(Icons.Default.Payment, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Record Payment (${amountDueCents.formatAsMoney()} due)")
                    }
                }
            }
        },
    ) { padding ->
        when {
            state.isLoading -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            }
            state.error != null -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    ErrorState(
                        message = state.error ?: "Error loading invoice",
                        onRetry = { viewModel.loadInvoice() },
                    )
                }
            }
            invoice != null -> {
                InvoiceDetailContent(
                    invoice = invoice,
                    onlineDetail = state.onlineDetail,
                    lineItems = state.lineItems,
                    payments = state.payments,
                    onlineDetailMessage = state.onlineDetailMessage,
                    serverUrl = state.serverUrl,
                    padding = padding,
                    onNavigateToTicket = onNavigateToTicket,
                )
            }
        }
    }
}

@Composable
private fun InvoiceDetailContent(
    invoice: InvoiceEntity,
    onlineDetail: com.bizarreelectronics.crm.data.remote.dto.InvoiceDetail?,
    lineItems: List<InvoiceLineItem>,
    payments: List<InvoicePayment>,
    onlineDetailMessage: String?,
    serverUrl: String?,
    padding: PaddingValues,
    onNavigateToTicket: ((Long) -> Unit)? = null,
) {
    val context = androidx.compose.ui.platform.LocalContext.current

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // ── §7.2 Header — invoice number (SelectionContainer), status chip, due date, balance-due chip
        item {
            BrandCard(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        // Invoice number in monospace, selectable for copy
                        SelectionContainer {
                            Text(
                                invoice.orderId.ifBlank { "INV-${invoice.id}" },
                                style = MaterialTheme.typography.titleMedium.copy(
                                    fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
                                ),
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.onSurface,
                            )
                        }
                        BrandStatusBadge(
                            label = invoice.status.replaceFirstChar { it.uppercase() },
                            status = invoice.status,
                        )
                    }
                    // Created date (canonical CROSS46 format)
                    Text(
                        "Created: ${DateFormatter.formatAbsolute(invoice.createdAt).ifBlank { invoice.createdAt.take(10) }}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    // Due date chip
                    if (!invoice.dueOn.isNullOrBlank()) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            Icon(
                                Icons.Default.CalendarToday,
                                contentDescription = "Due date",
                                modifier = Modifier.size(14.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Text(
                                "Due: ${invoice.dueOn.take(10)}",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                    // Balance-due chip — only shown when there is an outstanding balance
                    if (invoice.amountDue > 0L) {
                        val formatter = NumberFormat.getCurrencyInstance(Locale.US)
                        Surface(
                            shape = MaterialTheme.shapes.small,
                            color = MaterialTheme.colorScheme.errorContainer,
                        ) {
                            Text(
                                "Balance due: ${formatter.format(invoice.amountDue / 100.0)}",
                                modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onErrorContainer,
                                fontWeight = FontWeight.SemiBold,
                            )
                        }
                    }
                    if (invoice.ticketId != null && onNavigateToTicket != null) {
                        Text(
                            "From ticket #${invoice.ticketId}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.clickable { onNavigateToTicket(invoice.ticketId) },
                        )
                    }
                }
            }
        }

        // ── §7.2 Customer card — name, phone, email, quick-actions
        item {
            val customerName = onlineDetail?.customerName ?: invoice.customerName ?: "Unknown Customer"
            val customerPhone = onlineDetail?.customerPhone
            val customerEmail = onlineDetail?.customerEmail
            val hasContactInfo = !customerPhone.isNullOrBlank() || !customerEmail.isNullOrBlank()
            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(
                            Icons.Default.Person,
                            contentDescription = null,
                            modifier = Modifier.size(18.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            customerName,
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier.weight(1f),
                        )
                    }
                    if (!customerPhone.isNullOrBlank()) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            Icon(Icons.Default.Phone, contentDescription = null, modifier = Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(customerPhone, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    if (!customerEmail.isNullOrBlank()) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            Icon(Icons.Default.Email, contentDescription = null, modifier = Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(customerEmail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    if (hasContactInfo) {
                        // Quick-action row
                        Row(
                            modifier = Modifier.padding(top = 4.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            if (!customerPhone.isNullOrBlank()) {
                                FilledTonalButton(
                                    onClick = {
                                        val invNum = invoice.orderId.ifBlank { invoice.id.toString() }
                                        val link = if (!serverUrl.isNullOrBlank()) "$serverUrl/invoices/$invNum" else null
                                        sendSms(context, customerPhone, invNum, link)
                                    },
                                ) {
                                    Icon(Icons.Default.Sms, contentDescription = "Send SMS", modifier = Modifier.size(16.dp))
                                    Spacer(modifier = Modifier.width(4.dp))
                                    Text("SMS", style = MaterialTheme.typography.labelSmall)
                                }
                                FilledTonalButton(
                                    onClick = {
                                        val intent = android.content.Intent(android.content.Intent.ACTION_DIAL, android.net.Uri.parse("tel:$customerPhone"))
                                        runCatching { context.startActivity(intent) }
                                    },
                                ) {
                                    Icon(Icons.Default.Call, contentDescription = "Call customer", modifier = Modifier.size(16.dp))
                                    Spacer(modifier = Modifier.width(4.dp))
                                    Text("Call", style = MaterialTheme.typography.labelSmall)
                                }
                            }
                            if (!customerEmail.isNullOrBlank()) {
                                FilledTonalButton(
                                    onClick = {
                                        val invNum = invoice.orderId.ifBlank { invoice.id.toString() }
                                        val link = if (!serverUrl.isNullOrBlank()) "$serverUrl/invoices/$invNum" else null
                                        sendEmail(context, customerEmail, invNum, link)
                                    },
                                ) {
                                    Icon(Icons.Default.Email, contentDescription = "Send email", modifier = Modifier.size(16.dp))
                                    Spacer(modifier = Modifier.width(4.dp))
                                    Text("Email", style = MaterialTheme.typography.labelSmall)
                                }
                            }
                        }
                    }
                }
            }
        }

        // Line items section header
        item {
            Text(
                "Line items",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurface,
            )
        }

        // InvoiceLineItemsTable — read-only table; embedded as a single item to
        // avoid nested lazy list issues.
        item {
            BrandCard(modifier = Modifier.fillMaxWidth()) {
                if (lineItems.isEmpty()) {
                    Text(
                        onlineDetailMessage ?: "No line items",
                        modifier = Modifier.padding(16.dp),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                } else {
                    InvoiceLineItemsTable(
                        lineItems = lineItems,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
        }

        // ── §7.2 Totals panel — subtotal / discount / tax / total / paid / balance due
        item {
            Text(
                "Totals",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurface,
            )
        }
        item {
            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (invoice.discount > 0) {
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text("Subtotal", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(invoice.subtotal.formatAsMoney(), style = MaterialTheme.typography.bodyMedium)
                        }
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text("Discount", style = MaterialTheme.typography.bodyMedium, color = SuccessGreen)
                            Text("-${invoice.discount.formatAsMoney()}", style = MaterialTheme.typography.bodyMedium, color = SuccessGreen)
                        }
                    }
                    if (invoice.totalTax > 0) {
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text("Tax", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(invoice.totalTax.formatAsMoney(), style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant, thickness = 1.dp)
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text("Total", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                        Text(
                            invoice.total.formatAsMoney(),
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text("Paid", style = MaterialTheme.typography.bodyMedium, color = SuccessGreen)
                        Text(invoice.amountPaid.formatAsMoney(), style = MaterialTheme.typography.bodyMedium, color = SuccessGreen)
                    }
                    if (invoice.amountDue > 0) {
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(
                                "Balance due",
                                style = MaterialTheme.typography.bodyMedium,
                                fontWeight = FontWeight.SemiBold,
                                color = MaterialTheme.colorScheme.error,
                            )
                            Text(
                                invoice.amountDue.formatAsMoney(),
                                style = MaterialTheme.typography.bodyMedium,
                                fontWeight = FontWeight.SemiBold,
                                color = MaterialTheme.colorScheme.error,
                            )
                        }
                    }
                }
            }
        }

        // Payments section
        if (payments.isNotEmpty()) {
            item {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    "Payments",
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurface,
                )
            }
            items(payments, key = { it.id }) { payment ->
                BrandCard(modifier = Modifier.fillMaxWidth()) {
                    Row(
                        modifier = Modifier
                            .padding(12.dp)
                            .fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Column {
                            Text(
                                payment.method?.replace("_", " ")?.replaceFirstChar { it.uppercase() } ?: "Payment",
                                style = MaterialTheme.typography.bodyMedium,
                            )
                            Text(
                                payment.paymentDate?.take(10) ?: "",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            if (payment.status == "voided") {
                                Text(
                                    "VOIDED",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                        Text(
                            "$${"%.2f".format(payment.amount ?: 0.0)}",
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                }
            }
        }

        // Send / Share / Print actions
        item {
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                "Send & Share",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Spacer(modifier = Modifier.height(8.dp))
            InvoiceSendActions(
                invoiceNumber = invoice.orderId.ifBlank { invoice.id.toString() },
                customerPhone = onlineDetail?.customerPhone,
                customerEmail = onlineDetail?.customerEmail,
                serverUrl = serverUrl,
            )
        }

        // Status-change timeline
        item {
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                "Timeline",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Spacer(modifier = Modifier.height(8.dp))
            InvoiceTimelineSection(invoice = invoice, payments = payments)
        }
    }
}

/**
 * Synthetic timeline built from the payments list + invoice creation date.
 *
 * A server-side /invoices/{id}/history endpoint does not exist yet; this derives
 * events from the data already available to avoid a 404. When the endpoint is added,
 * replace this with a real TicketHistoryTimeline-style component.
 */
@Composable
private fun InvoiceTimelineSection(
    invoice: InvoiceEntity,
    payments: List<InvoicePayment>,
) {
    data class TimelineEvent(val label: String, val date: String, val isFirst: Boolean = false)

    val events = buildList {
        add(TimelineEvent("Invoice created", invoice.createdAt.take(16).replace("T", " "), isFirst = true))
        payments.sortedBy { it.paymentDate }.forEach { p ->
            val method = p.method?.replace("_", " ")?.replaceFirstChar { it.uppercase() } ?: "Payment"
            val amt = "$${"%.2f".format(p.amount ?: 0.0)}"
            val suffix = if (p.status == "voided") " (voided)" else ""
            add(TimelineEvent("$method $amt recorded$suffix", p.paymentDate?.take(10) ?: ""))
        }
        if (invoice.status.equals("Voided", ignoreCase = true)) {
            add(TimelineEvent("Invoice voided", invoice.updatedAt.take(10)))
        } else if (invoice.amountDue <= 0L && invoice.amountPaid > 0L) {
            add(TimelineEvent("Invoice fully paid", invoice.updatedAt.take(10)))
        }
    }

    if (events.isEmpty()) {
        BrandCard(modifier = Modifier.fillMaxWidth()) {
            Text(
                "No timeline events yet.",
                modifier = Modifier.padding(16.dp),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        return
    }

    Column(modifier = Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(0.dp)) {
        events.forEachIndexed { index, event ->
            InvoiceTimelineRow(event = event, label = event.label, date = event.date, isLast = index == events.lastIndex)
        }
    }
}

@Composable
private fun InvoiceTimelineRow(
    event: Any,
    label: String,
    date: String,
    isLast: Boolean,
) {
    val dotColor = MaterialTheme.colorScheme.primary
    val lineColor = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f)

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(IntrinsicSize.Min),
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.width(24.dp),
        ) {
            Spacer(modifier = Modifier.height(4.dp))
            Box(
                modifier = Modifier
                    .size(10.dp)
                    .background(dotColor, CircleShape),
            )
            if (!isLast) {
                Box(
                    modifier = Modifier
                        .width(2.dp)
                        .weight(1f)
                        .fillMaxHeight()
                        .background(lineColor),
                )
                Spacer(modifier = Modifier.height(4.dp))
            }
        }
        Spacer(modifier = Modifier.width(8.dp))
        Column(
            modifier = Modifier
                .weight(1f)
                .padding(bottom = if (isLast) 0.dp else 12.dp),
        ) {
            Text(label, style = MaterialTheme.typography.bodySmall)
            if (date.isNotBlank()) {
                Text(
                    date,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}
