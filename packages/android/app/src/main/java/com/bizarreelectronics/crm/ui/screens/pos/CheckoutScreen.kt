package com.bizarreelectronics.crm.ui.screens.pos

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.ui.theme.*
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.local.db.entities.SyncQueueEntity
import com.bizarreelectronics.crm.data.remote.api.InvoiceApi
import com.bizarreelectronics.crm.data.remote.api.TicketApi
import com.bizarreelectronics.crm.data.remote.dto.RecordPaymentRequest
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import com.google.gson.Gson
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.text.NumberFormat
import java.util.Locale
import javax.inject.Inject
import kotlin.math.ceil

// ─── Payment method enum ─────────────────────────────────────────────

enum class PaymentMethod(val label: String, val apiValue: String, val icon: ImageVector) {
    CASH("Cash", "cash", Icons.Default.Payments),
    CARD("Card", "credit_card", Icons.Default.CreditCard),
    OTHER("Other", "other", Icons.Default.MoreHoriz),
}

// ─── UI state ────────────────────────────────────────────────────────

data class CheckoutUiState(
    val ticketId: Long = 0,
    val total: Double = 0.0,
    val customerName: String = "",
    val selectedMethod: PaymentMethod = PaymentMethod.CASH,
    val cashInput: String = "",
    val isProcessing: Boolean = false,
    val error: String? = null,
    val pendingSync: Boolean = false,
) {
    val cashAmount: Double get() = cashInput.toDoubleOrNull() ?: 0.0
    val changeDue: Double get() = (cashAmount - total).coerceAtLeast(0.0)
    val canComplete: Boolean
        get() = when (selectedMethod) {
            PaymentMethod.CASH -> cashAmount >= total
            else -> true
        }
}

// ─── ViewModel ───────────────────────────────────────────────────────

@HiltViewModel
class CheckoutViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val ticketApi: TicketApi,
    private val invoiceApi: InvoiceApi,
    private val serverMonitor: ServerReachabilityMonitor,
    private val syncQueueDao: SyncQueueDao,
    private val gson: Gson,
) : ViewModel() {

    private val _state = MutableStateFlow(
        CheckoutUiState(
            ticketId = savedStateHandle.get<Long>("ticketId") ?: 0L,
            total = savedStateHandle.get<String>("total")?.toDoubleOrNull() ?: 0.0,
            customerName = savedStateHandle.get<String>("customerName") ?: "",
        )
    )
    val state: StateFlow<CheckoutUiState> = _state.asStateFlow()

    fun selectMethod(method: PaymentMethod) {
        _state.update { it.copy(selectedMethod = method, error = null) }
    }

    fun setCashInput(value: String) {
        // Allow only digits and one decimal point
        val filtered = value.filter { c -> c.isDigit() || c == '.' }
        val dotCount = filtered.count { it == '.' }
        if (dotCount <= 1) {
            _state.update { it.copy(cashInput = filtered, error = null) }
        }
    }

    fun setExactAmount() {
        _state.update { it.copy(cashInput = String.format(Locale.US, "%.2f", it.total), error = null) }
    }

    fun setRoundedAmount(roundTo: Int) {
        val rounded = ceil(_state.value.total / roundTo) * roundTo
        _state.update { it.copy(cashInput = String.format(Locale.US, "%.2f", rounded), error = null) }
    }

    fun completePayment(onSuccess: (ticketId: Long) -> Unit) {
        val s = _state.value
        if (s.isProcessing) return
        if (!s.canComplete) {
            _state.update { it.copy(error = "Insufficient payment amount.") }
            return
        }

        _state.update { it.copy(isProcessing = true, error = null) }
        viewModelScope.launch {
            val isOnline = serverMonitor.isEffectivelyOnline.value

            if (isOnline) {
                completePaymentOnline(s, onSuccess)
            } else {
                completePaymentOffline(s, onSuccess)
            }
        }
    }

    private suspend fun completePaymentOnline(
        s: CheckoutUiState,
        onSuccess: (ticketId: Long) -> Unit,
    ) {
        try {
            // Step 1: Convert ticket to invoice
            val invoiceResponse = ticketApi.convertToInvoice(s.ticketId)
            if (!invoiceResponse.success || invoiceResponse.data == null) {
                _state.update {
                    it.copy(
                        isProcessing = false,
                        error = invoiceResponse.message ?: "Failed to create invoice."
                    )
                }
                return
            }
            val invoiceId = invoiceResponse.data.id

            // Step 2: Record payment
            val paymentRequest = RecordPaymentRequest(
                amount = s.total,
                method = s.selectedMethod.apiValue,
                notes = if (s.selectedMethod == PaymentMethod.CASH && s.changeDue > 0) {
                    "Change: ${formatCurrency(s.changeDue)}"
                } else {
                    null
                },
            )
            val paymentResponse = invoiceApi.recordPayment(invoiceId, paymentRequest)
            if (!paymentResponse.success) {
                _state.update {
                    it.copy(
                        isProcessing = false,
                        error = paymentResponse.message ?: "Failed to record payment."
                    )
                }
                return
            }

            _state.update { it.copy(isProcessing = false) }
            onSuccess(s.ticketId)
        } catch (e: Exception) {
            _state.update { it.copy(isProcessing = false, error = e.message ?: "Network error.") }
        }
    }

    private suspend fun completePaymentOffline(
        s: CheckoutUiState,
        onSuccess: (ticketId: Long) -> Unit,
    ) {
        val payload = gson.toJson(
            mapOf(
                "ticketId" to s.ticketId,
                "paymentMethod" to s.selectedMethod.apiValue,
                "amount" to s.total,
            )
        )
        syncQueueDao.insert(
            SyncQueueEntity(
                entityType = "checkout",
                entityId = s.ticketId,
                operation = "convert_and_pay",
                payload = payload,
            )
        )

        _state.update { it.copy(isProcessing = false, pendingSync = true) }
        onSuccess(s.ticketId)
    }

    fun clearError() {
        _state.update { it.copy(error = null) }
    }
}

// ─── Formatting ──────────────────────────────────────────────────────

private val currencyFormatter: NumberFormat = NumberFormat.getCurrencyInstance(Locale.US)

private fun formatCurrency(amount: Double): String = currencyFormatter.format(amount)

// ─── Screen composable ──────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CheckoutScreen(
    onBack: () -> Unit,
    onSuccess: (ticketId: Long) -> Unit,
    viewModel: CheckoutViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(state.error) {
        state.error?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearError()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Checkout") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .imePadding()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // ── Order summary card ───────────────────────────────────
            OrderSummaryCard(
                customerName = state.customerName,
                total = state.total,
            )

            // ── Payment method selector ──────────────────────────────
            Text(
                "Payment Method",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
            PaymentMethodSelector(
                selected = state.selectedMethod,
                onSelect = viewModel::selectMethod,
            )

            // ── Cash-specific inputs ─────────────────────────────────
            if (state.selectedMethod == PaymentMethod.CASH) {
                CashPaymentSection(
                    total = state.total,
                    cashInput = state.cashInput,
                    changeDue = state.changeDue,
                    onCashInputChange = viewModel::setCashInput,
                    onExact = viewModel::setExactAmount,
                    onRound = viewModel::setRoundedAmount,
                )
            }

            Spacer(modifier = Modifier.weight(1f))

            // ── Complete payment button ──────────────────────────────
            Button(
                onClick = { viewModel.completePayment(onSuccess) },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp),
                enabled = state.canComplete && !state.isProcessing,
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.primary,
                ),
            ) {
                if (state.isProcessing) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(24.dp),
                        color = MaterialTheme.colorScheme.onPrimary,
                        strokeWidth = 2.dp,
                    )
                    Spacer(modifier = Modifier.width(12.dp))
                    Text("Processing...")
                } else {
                    Icon(Icons.Default.CheckCircle, contentDescription = null, modifier = Modifier.size(24.dp))
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        "Complete Payment  ${formatCurrency(state.total)}",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
        }
    }
}

// ─── Sub-composables ─────────────────────────────────────────────────

@Composable
private fun OrderSummaryCard(customerName: String, total: Double) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.primaryContainer,
        ),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            if (customerName.isNotBlank()) {
                Text(
                    customerName,
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onPrimaryContainer,
                )
                Spacer(modifier = Modifier.height(4.dp))
            }
            Text(
                "Total Due",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f),
            )
            Text(
                formatCurrency(total),
                style = MaterialTheme.typography.headlineLarge,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onPrimaryContainer,
            )
        }
    }
}

@Composable
private fun PaymentMethodSelector(
    selected: PaymentMethod,
    onSelect: (PaymentMethod) -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        PaymentMethod.entries.forEach { method ->
            val isSelected = method == selected
            OutlinedCard(
                onClick = { onSelect(method) },
                modifier = Modifier
                    .weight(1f)
                    .height(80.dp),
                border = BorderStroke(
                    width = if (isSelected) 2.dp else 1.dp,
                    color = if (isSelected) MaterialTheme.colorScheme.primary
                    else MaterialTheme.colorScheme.outlineVariant,
                ),
                colors = CardDefaults.outlinedCardColors(
                    containerColor = if (isSelected) MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.3f)
                    else MaterialTheme.colorScheme.surface,
                ),
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(8.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    Icon(
                        method.icon,
                        contentDescription = method.label,
                        modifier = Modifier.size(28.dp),
                        tint = if (isSelected) MaterialTheme.colorScheme.primary
                        else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        method.label,
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal,
                        color = if (isSelected) MaterialTheme.colorScheme.primary
                        else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

@Composable
private fun CashPaymentSection(
    total: Double,
    cashInput: String,
    changeDue: Double,
    onCashInputChange: (String) -> Unit,
    onExact: () -> Unit,
    onRound: (Int) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(
            "Amount Received",
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
        )

        OutlinedTextField(
            value = cashInput,
            onValueChange = onCashInputChange,
            label = { Text("Cash amount") },
            prefix = { Text("$") },
            modifier = Modifier.fillMaxWidth(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            singleLine = true,
        )

        // Quick amount buttons
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            AssistChip(
                onClick = onExact,
                label = { Text("Exact") },
                modifier = Modifier.weight(1f),
            )
            if (total <= 5.0) {
                AssistChip(
                    onClick = { onRound(5) },
                    label = { Text("$5") },
                    modifier = Modifier.weight(1f),
                )
            }
            if (total <= 10.0) {
                AssistChip(
                    onClick = { onRound(10) },
                    label = { Text("$10") },
                    modifier = Modifier.weight(1f),
                )
            }
            AssistChip(
                onClick = { onRound(20) },
                label = { Text("$20") },
                modifier = Modifier.weight(1f),
            )
            if (total > 20.0) {
                AssistChip(
                    onClick = { onRound(50) },
                    label = { Text("$50") },
                    modifier = Modifier.weight(1f),
                )
            }
            if (total > 50.0) {
                AssistChip(
                    onClick = { onRound(100) },
                    label = { Text("$100") },
                    modifier = Modifier.weight(1f),
                )
            }
        }

        // Change due display
        if (changeDue > 0) {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = SuccessGreen.copy(alpha = 0.12f),
                ),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        "Change Due",
                        style = MaterialTheme.typography.titleMedium,
                        color = SuccessGreen,
                    )
                    Text(
                        formatCurrency(changeDue),
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.Bold,
                        color = SuccessGreen,
                    )
                }
            }
        }
    }
}
