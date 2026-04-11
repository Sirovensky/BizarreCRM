package com.bizarreelectronics.crm.ui.screens.invoices

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.ui.theme.*
import com.bizarreelectronics.crm.data.local.db.entities.InvoiceEntity
import com.bizarreelectronics.crm.data.remote.api.InvoiceApi
import com.bizarreelectronics.crm.data.remote.dto.InvoiceDetail
import com.bizarreelectronics.crm.data.remote.dto.InvoiceLineItem
import com.bizarreelectronics.crm.data.remote.dto.InvoicePayment
import com.bizarreelectronics.crm.data.remote.dto.RecordPaymentRequest
import com.bizarreelectronics.crm.data.repository.InvoiceRepository
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
                    lineItems = detail?.lineItems ?: emptyList(),
                    payments = detail?.payments ?: emptyList(),
                    onlineDetailMessage = null,
                )
            } catch (_: Exception) {
                _state.value = _state.value.copy(
                    lineItems = emptyList(),
                    payments = emptyList(),
                    onlineDetailMessage = "Line items available when online",
                )
            }
        }
    }

    fun recordPayment(amount: Double, method: String) {
        // U1 fix: hard guard against re-entry so that a double-tap while the
        // coroutine is in flight can't enqueue a second POST /payments.
        if (_state.value.isActionInProgress) return
        viewModelScope.launch {
            _state.value = _state.value.copy(isActionInProgress = true)
            try {
                val request = RecordPaymentRequest(amount = amount, method = method)
                invoiceApi.recordPayment(invoiceId, request)
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Payment of $${"%.2f".format(amount)} recorded",
                    paymentSuccessCounter = _state.value.paymentSuccessCounter + 1,
                )
                // Refresh both entity and online details after payment
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

    // U13 fix: rememberSaveable so rotations / dialog dismissals don't reset these.
    var showPaymentDialog by rememberSaveable { mutableStateOf(false) }
    var showVoidConfirm by rememberSaveable { mutableStateOf(false) }
    var paymentAmount by rememberSaveable { mutableStateOf("") }
    var paymentMethod by rememberSaveable { mutableStateOf("cash") }
    var showMethodDropdown by remember { mutableStateOf(false) }

    val snackbarHostState = remember { SnackbarHostState() }

    // U1 fix: dialog is closed from a LaunchedEffect keyed on the VM's success
    // counter, never from the click handler. This guarantees the dialog stays
    // open until the mutation actually succeeds.
    LaunchedEffect(state.paymentSuccessCounter) {
        if (state.paymentSuccessCounter > 0) {
            showPaymentDialog = false
            paymentAmount = ""
            paymentMethod = "cash"
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
            },
            title = { Text("Record Payment") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    // Convert stored cents back to a Double dollars value for
                    // comparison against the user's text-field input. We still
                    // keep the comparison in dollars because the user types
                    // "$12.34"; accepting tenths of a cent would surprise them.
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
                        prefix = { Text("$") },
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
                        TextButton(onClick = {
                            paymentAmount = "%.2f".format(dueDollars)
                        }) {
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
                }
            },
            confirmButton = {
                // Convert stored cents back to dollars for comparison with the
                // user-typed amount; see the matching comment in the dialog body.
                val amountDue = (invoice?.amountDue ?: 0L).toDollars()
                val parsedAmount = paymentAmount.toDoubleOrNull()
                val isAmountValid = parsedAmount != null &&
                    parsedAmount > 0.0 &&
                    parsedAmount <= amountDue
                TextButton(
                    onClick = {
                        // U1 fix: we no longer close the dialog here. We call
                        // recordPayment, and a LaunchedEffect closes the dialog
                        // ONLY after the mutation succeeds.
                        val amt = parsedAmount
                        if (isAmountValid && amt != null && !state.isActionInProgress) {
                            viewModel.recordPayment(amt, paymentMethod)
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
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Recording...")
                    } else {
                        Text("Record")
                    }
                }
            },
            dismissButton = {
                TextButton(onClick = {
                    showPaymentDialog = false
                    paymentAmount = ""
                    paymentMethod = "cash"
                }) {
                    Text("Cancel")
                }
            },
        )
    }

    // Void confirmation
    if (showVoidConfirm) {
        AlertDialog(
            onDismissRequest = { showVoidConfirm = false },
            title = { Text("Void Invoice") },
            text = { Text("Are you sure you want to void this invoice? This will restore stock and mark all payments as voided. This action cannot be undone.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        showVoidConfirm = false
                        viewModel.voidInvoice()
                    },
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                ) {
                    Text("Void Invoice")
                }
            },
            dismissButton = {
                TextButton(onClick = { showVoidConfirm = false }) {
                    Text("Cancel")
                }
            },
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = { Text(invoice?.orderId?.ifBlank { "INV-$invoiceId" } ?: "INV-$invoiceId") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    if (invoice != null && !invoice.status.equals("Voided", ignoreCase = true)) {
                        IconButton(onClick = { showVoidConfirm = true }) {
                            Icon(Icons.Default.Block, contentDescription = "Void", tint = MaterialTheme.colorScheme.error)
                        }
                    }
                },
            )
        },
        bottomBar = {
            val amountDueCents = invoice?.amountDue ?: 0L
            if (amountDueCents > 0 && invoice?.status?.equals("Voided", ignoreCase = true) != true) {
                BottomAppBar {
                    Button(
                        onClick = { showPaymentDialog = true },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp),
                        enabled = !state.isActionInProgress,
                    ) {
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
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(state.error ?: "Error", color = MaterialTheme.colorScheme.error)
                        Spacer(modifier = Modifier.height(8.dp))
                        TextButton(onClick = { viewModel.loadInvoice() }) { Text("Retry") }
                    }
                }
            }
            invoice != null -> {
                InvoiceDetailContent(
                    invoice = invoice,
                    lineItems = state.lineItems,
                    payments = state.payments,
                    onlineDetailMessage = state.onlineDetailMessage,
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
    lineItems: List<InvoiceLineItem>,
    payments: List<InvoicePayment>,
    onlineDetailMessage: String?,
    padding: PaddingValues,
    onNavigateToTicket: ((Long) -> Unit)? = null,
) {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Status + customer
        item {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            invoice.customerName ?: "Unknown Customer",
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                        )

                        val detailStatusColor = when (invoice.status.replaceFirstChar { it.uppercase() }) {
                            "Paid" -> SuccessGreen
                            "Unpaid" -> ErrorRed
                            "Partial" -> WarningAmber
                            "Voided" -> Color.Gray
                            "Refunded" -> RefundedPurple
                            else -> Color.Gray
                        }
                        Surface(shape = MaterialTheme.shapes.small, color = detailStatusColor) {
                            Text(
                                invoice.status.replaceFirstChar { it.uppercase() },
                                modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                                style = MaterialTheme.typography.labelSmall,
                                color = contrastTextColor(detailStatusColor),
                            )
                        }
                    }
                    Text(
                        "Created: ${invoice.createdAt.take(10)}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
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

        // Line items
        item {
            Text("Line Items", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        }

        if (lineItems.isEmpty()) {
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
                ) {
                    Text(
                        onlineDetailMessage ?: "No line items",
                        modifier = Modifier.padding(16.dp),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        } else {
            items(lineItems, key = { it.id }) { item ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 4.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(item.name ?: "Item", style = MaterialTheme.typography.bodyMedium)
                        Text(
                            "Qty: ${item.quantity ?: 1} x $${"%.2f".format(item.price ?: 0.0)}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        if (item.sku != null) {
                            Text("SKU: ${item.sku}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    Text(
                        "$${"%.2f".format(item.total ?: 0.0)}",
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Medium,
                    )
                }
            }
        }

        // Totals
        item {
            HorizontalDivider()
            Spacer(modifier = Modifier.height(8.dp))
            if (invoice.discount > 0) {
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("Subtotal", style = MaterialTheme.typography.bodyMedium)
                    Text(invoice.subtotal.formatAsMoney(), style = MaterialTheme.typography.bodyMedium)
                }
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("Discount", style = MaterialTheme.typography.bodyMedium, color = SuccessGreen)
                    Text("-${invoice.discount.formatAsMoney()}", style = MaterialTheme.typography.bodyMedium, color = SuccessGreen)
                }
            }
            if (invoice.totalTax > 0) {
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("Tax", style = MaterialTheme.typography.bodyMedium)
                    Text(invoice.totalTax.formatAsMoney(), style = MaterialTheme.typography.bodyMedium)
                }
            }
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("Total", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                Text(invoice.total.formatAsMoney(), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            }
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("Paid", style = MaterialTheme.typography.bodyMedium, color = SuccessGreen)
                Text(invoice.amountPaid.formatAsMoney(), style = MaterialTheme.typography.bodyMedium, color = SuccessGreen)
            }
            if (invoice.amountDue > 0) {
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("Due", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = ErrorRed)
                    Text(invoice.amountDue.formatAsMoney(), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = ErrorRed)
                }
            }
        }

        // Payments
        if (payments.isNotEmpty()) {
            item {
                Spacer(modifier = Modifier.height(8.dp))
                Text("Payments", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            }
            items(payments, key = { it.id }) { payment ->
                Card(modifier = Modifier.fillMaxWidth()) {
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
                                Text("VOIDED", style = MaterialTheme.typography.labelSmall, color = Color.Gray)
                            }
                        }
                        Text(
                            "$${"%.2f".format(payment.amount ?: 0.0)}",
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.Medium,
                        )
                    }
                }
            }
        }
    }
}
