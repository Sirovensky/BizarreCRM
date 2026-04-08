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
import com.bizarreelectronics.crm.data.remote.api.InvoiceApi
import com.bizarreelectronics.crm.data.remote.dto.InvoiceDetail
import com.bizarreelectronics.crm.data.remote.dto.RecordPaymentRequest
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class InvoiceDetailUiState(
    val invoice: InvoiceDetail? = null,
    val isLoading: Boolean = true,
    val error: String? = null,
    val actionMessage: String? = null,
    val isActionInProgress: Boolean = false,
)

@HiltViewModel
class InvoiceDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val invoiceApi: InvoiceApi,
) : ViewModel() {

    private val invoiceId: Long = savedStateHandle.get<String>("id")?.toLongOrNull() ?: 0L

    private val _state = MutableStateFlow(InvoiceDetailUiState())
    val state = _state.asStateFlow()

    init {
        loadInvoice()
    }

    fun loadInvoice() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                val response = invoiceApi.getInvoice(invoiceId)
                val invoice = response.data?.invoice
                _state.value = _state.value.copy(invoice = invoice, isLoading = false)
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = e.message ?: "Failed to load invoice",
                )
            }
        }
    }

    fun recordPayment(amount: Double, method: String) {
        viewModelScope.launch {
            _state.value = _state.value.copy(isActionInProgress = true)
            try {
                val request = RecordPaymentRequest(amount = amount, method = method)
                val response = invoiceApi.recordPayment(invoiceId, request)
                _state.value = _state.value.copy(
                    invoice = response.data?.invoice,
                    isActionInProgress = false,
                    actionMessage = "Payment of $${"%.2f".format(amount)} recorded",
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Failed to record payment: ${e.message}",
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
                loadInvoice()
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isActionInProgress = false,
                    actionMessage = "Failed to void invoice: ${e.message}",
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

    var showPaymentDialog by remember { mutableStateOf(false) }
    var showVoidConfirm by remember { mutableStateOf(false) }
    var paymentAmount by remember { mutableStateOf("") }
    var paymentMethod by remember { mutableStateOf("cash") }
    var showMethodDropdown by remember { mutableStateOf(false) }

    val snackbarHostState = remember { SnackbarHostState() }

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
                    )

                    // Pre-fill with amount due
                    if (paymentAmount.isEmpty() && invoice?.amountDue != null && invoice.amountDue > 0) {
                        TextButton(onClick = {
                            paymentAmount = "%.2f".format(invoice.amountDue)
                        }) {
                            Text("Fill remaining: $${"%.2f".format(invoice.amountDue)}")
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
                TextButton(
                    onClick = {
                        val amount = paymentAmount.toDoubleOrNull()
                        if (amount != null && amount > 0) {
                            viewModel.recordPayment(amount, paymentMethod)
                            showPaymentDialog = false
                            paymentAmount = ""
                            paymentMethod = "cash"
                        }
                    },
                    enabled = paymentAmount.toDoubleOrNull()?.let { it > 0 } == true,
                ) {
                    Text("Record")
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
                title = { Text(invoice?.orderId ?: "INV-$invoiceId") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    if (invoice != null && invoice.status != "Voided") {
                        IconButton(onClick = { showVoidConfirm = true }) {
                            Icon(Icons.Default.Block, contentDescription = "Void", tint = MaterialTheme.colorScheme.error)
                        }
                    }
                },
            )
        },
        bottomBar = {
            val amountDue = invoice?.amountDue ?: 0.0
            if (amountDue > 0 && invoice?.status != "Voided") {
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
                        Text("Record Payment (${"$%.2f".format(amountDue)} due)")
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
                    padding = padding,
                    onNavigateToTicket = onNavigateToTicket,
                )
            }
        }
    }
}

@Composable
private fun InvoiceDetailContent(
    invoice: InvoiceDetail,
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
                        val customerName = invoice.customerName

                        Text(customerName, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)

                        val detailStatusColor = when (invoice.status) {
                            "Paid" -> SuccessGreen
                            "Unpaid" -> ErrorRed
                            "Partial" -> WarningAmber
                            "Voided" -> Color.Gray
                            "Refunded" -> RefundedPurple
                            else -> Color.Gray
                        }
                        Surface(shape = MaterialTheme.shapes.small, color = detailStatusColor) {
                            Text(
                                invoice.status ?: "",
                                modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                                style = MaterialTheme.typography.labelSmall,
                                color = contrastTextColor(detailStatusColor),
                            )
                        }
                    }
                    Text(
                        "Created: ${invoice.createdAt?.take(10) ?: ""}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    if (invoice.ticketOrderId != null) {
                        Text(
                            "From ticket: ${invoice.ticketOrderId}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = if (invoice.ticketId != null && onNavigateToTicket != null) {
                                Modifier.clickable { onNavigateToTicket(invoice.ticketId) }
                            } else {
                                Modifier
                            },
                        )
                    }
                }
            }
        }

        // Line items
        item {
            Text("Line Items", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        }

        val lineItems = invoice.lineItems ?: emptyList()
        if (lineItems.isEmpty()) {
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
                ) {
                    Text(
                        "No line items",
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
            if (invoice.discount != null && invoice.discount > 0) {
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("Subtotal", style = MaterialTheme.typography.bodyMedium)
                    Text("$${"%.2f".format(invoice.subtotal ?: 0.0)}", style = MaterialTheme.typography.bodyMedium)
                }
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("Discount", style = MaterialTheme.typography.bodyMedium, color = SuccessGreen)
                    Text("-$${"%.2f".format(invoice.discount)}", style = MaterialTheme.typography.bodyMedium, color = SuccessGreen)
                }
            }
            if (invoice.totalTax != null && invoice.totalTax > 0) {
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("Tax", style = MaterialTheme.typography.bodyMedium)
                    Text("$${"%.2f".format(invoice.totalTax)}", style = MaterialTheme.typography.bodyMedium)
                }
            }
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("Total", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                Text("$${"%.2f".format(invoice.total ?: 0.0)}", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            }
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("Paid", style = MaterialTheme.typography.bodyMedium, color = SuccessGreen)
                Text("$${"%.2f".format(invoice.amountPaid ?: 0.0)}", style = MaterialTheme.typography.bodyMedium, color = SuccessGreen)
            }
            val amountDue = invoice.amountDue ?: 0.0
            if (amountDue > 0) {
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("Due", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = ErrorRed)
                    Text("$${"%.2f".format(amountDue)}", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = ErrorRed)
                }
            }
        }

        // Payments
        val payments = invoice.payments ?: emptyList()
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
