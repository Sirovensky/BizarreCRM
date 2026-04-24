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
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.ui.components.SensitiveScreenGuard
import com.bizarreelectronics.crm.ui.components.Sensitivity
import com.bizarreelectronics.crm.ui.components.shared.BrandPrimaryButton
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

    // AND-20260414-H4: route args now typed via navArgument in AppNavGraph
    // (ticketId=Long, total=Float, customerName=String?). Previously the
    // un-typed route stored every segment as String, and get<Long>("ticketId")
    // silently returned null — booting the screen with ticket 0 and $0.
    private val _state = MutableStateFlow(
        CheckoutUiState(
            ticketId = savedStateHandle.get<Long>("ticketId") ?: 0L,
            total = savedStateHandle.get<Float>("total")?.toDouble() ?: 0.0,
            customerName = savedStateHandle.get<String>("customerName")
                ?.let { android.net.Uri.decode(it) } ?: "",
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
                // D5-5: Split by payment method — cash can run offline via the
                // sync queue; card payments MUST hit the live processor and
                // therefore cannot be queued. Marking a card "approved"
                // locally would let the cashier hand back goods before the
                // charge clears, or (worse) without ever capturing funds.
                if (s.selectedMethod == PaymentMethod.CARD) {
                    _state.update {
                        it.copy(
                            isProcessing = false,
                            error = "Card payments require an internet connection. Switch to Cash to save offline.",
                        )
                    }
                } else {
                    completePaymentOffline(s, onSuccess)
                }
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
    // AND-20260414-H4: ticketId/total/customerName exposed as composable
    // params (alongside SavedStateHandle) so the defensive guard below can
    // fail fast on bad args before the VM instantiates and we render the
    // payment UI. Also makes this screen unit-testable outside a NavHost.
    ticketId: Long = 0L,
    total: Double = 0.0,
    customerName: String = "",
    onBack: () -> Unit,
    onSuccess: (ticketId: Long) -> Unit,
    viewModel: CheckoutViewModel = hiltViewModel(),
) {
    // AND-20260414-H4 defensive guard: refuse to boot the payment flow with
    // a zero ticket id or a non-positive total. Previously a broken caller
    // could silently process a $0 transaction against ticket 0, which would
    // then 400 on the server (or worse, succeed as a $0 invoice with no
    // line items), and the cashier would hand back goods in exchange for
    // nothing. Hard-fail with a clear error screen instead.
    if (ticketId == 0L || total <= 0.0) {
        CheckoutInvalidArgsScreen(
            ticketId = ticketId,
            total = total,
            onBack = onBack,
        )
        return
    }

    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    // D5-5: Dismiss any in-flight snackbar before queuing a new one so repeated
    // taps on a broken network don't pile up 15 identical "Network error"
    // toasts that the user then has to wait out one at a time. Primary debounce
    // is the `enabled = ... && !state.isProcessing` gate on the CTA below; this
    // is belt-and-suspenders for any other path (e.g. repeated validation
    // errors) that might re-fire the error state.
    LaunchedEffect(state.error) {
        state.error?.let {
            snackbarHostState.currentSnackbarData?.dismiss()
            snackbarHostState.showSnackbar(it)
            viewModel.clearError()
        }
    }

    // §2.16 L401 — require biometric re-auth on entry to the payment surface.
    SensitiveScreenGuard(sensitivity = Sensitivity.Payment) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        "Checkout",
                        style = MaterialTheme.typography.titleMedium,
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                    titleContentColor = MaterialTheme.colorScheme.onSurface,
                    actionIconContentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                ),
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
            // a11y: zero-size live-region node that triggers an Assertive announcement the
            // moment a payment error enters the state. TalkBack will interrupt whatever it is
            // currently reading and say "Payment failed: <reason>" so the cashier doesn't miss
            // it. The snackbar also shows the message visually; this node is purely auditory.
            if (state.error != null) {
                Box(
                    modifier = Modifier.semantics {
                        liveRegion = LiveRegionMode.Assertive
                        contentDescription = "Payment failed: ${state.error}"
                    },
                )
            }

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
            // CROSS48-adopt-more: checkout's dominant "Complete Payment" CTA
            // now uses BrandPrimaryButton so the per-site container-color
            // override falls away and the 12dp theme shape applies.
            BrandPrimaryButton(
                onClick = { viewModel.completePayment(onSuccess) },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp)
                    // a11y: mergeDescendants collapses the icon + text content into one focus node.
                    // contentDescription switches between the actionable label ("Charge $X via Cash")
                    // and a processing announcement so the user always knows what is happening.
                    // liveRegion=Polite lets TalkBack re-announce when the processing state changes
                    // without jarring interruptions.
                    .semantics(mergeDescendants = true) {
                        contentDescription = if (state.isProcessing) {
                            "Processing payment"
                        } else {
                            "Charge ${formatCurrency(state.total)} via ${state.selectedMethod.label}"
                        }
                        liveRegion = LiveRegionMode.Polite
                    },
                enabled = state.canComplete && !state.isProcessing,
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
                    // a11y: decorative — merged contentDescription on the button carries the spoken label
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
    } // end SensitiveScreenGuard
}

// ─── Invalid-args guard screen ───────────────────────────────────────
// AND-20260414-H4: rendered in place of the real payment UI when the
// caller hands us a zero ticket id or a non-positive total. Self-contained
// so it can render without the VM ever being instantiated.

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CheckoutInvalidArgsScreen(
    ticketId: Long,
    total: Double,
    onBack: () -> Unit,
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        "Checkout",
                        style = MaterialTheme.typography.titleMedium,
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                    titleContentColor = MaterialTheme.colorScheme.onSurface,
                    actionIconContentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                ),
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(modifier = Modifier.height(24.dp))
            val invalidReason = when {
                ticketId == 0L && total <= 0.0 -> "Missing ticket id and total."
                ticketId == 0L -> "Missing ticket id."
                else -> "Total must be greater than zero."
            }
            // a11y: mergeDescendants collapses the error icon, title, reason, and hint into
            // a single TalkBack focus stop. contentDescription reads the full explanation
            // so the user doesn't have to swipe through three separate nodes to understand
            // why checkout cannot proceed.
            Column(
                modifier = Modifier.semantics(mergeDescendants = true) {
                    contentDescription =
                        "Invalid checkout parameters. $invalidReason Return to the ticket and try again."
                },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Icon(
                    Icons.Default.ErrorOutline,
                    // a11y: decorative — merged contentDescription on the parent Column carries the full announcement
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.error,
                    modifier = Modifier.size(48.dp),
                )
                Text(
                    "Invalid checkout parameters",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.SemiBold,
                    textAlign = TextAlign.Center,
                )
                Text(
                    invalidReason,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )
                Text(
                    "Return to the ticket and try again.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )
            }
            Spacer(modifier = Modifier.height(8.dp))
            BrandPrimaryButton(
                onClick = onBack,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Go back")
            }
        }
    }
}

// ─── Sub-composables ─────────────────────────────────────────────────

@Composable
private fun OrderSummaryCard(customerName: String, total: Double) {
    // a11y: mergeDescendants collapses the customer name, "Total Due" label, and
    // formatted amount into a single TalkBack focus stop. contentDescription is
    // built eagerly so the value is stable across recompositions and can include
    // the customer name only when it is present.
    val summaryDesc = if (customerName.isNotBlank()) {
        "Customer: $customerName, Total: ${formatCurrency(total)}"
    } else {
        "Total: ${formatCurrency(total)}"
    }
    Card(
        modifier = Modifier
            .fillMaxWidth()
            // a11y: single merged focus node — reads the full order summary as one announcement
            .semantics(mergeDescendants = true) {
                contentDescription = summaryDesc
            },
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
                    .height(80.dp)
                    // a11y: Role.RadioButton makes TalkBack announce "radio button, selected/not
                    // selected" for each method tile. mergeDescendants collapses the icon + label
                    // into one focus stop; contentDescription gives a clean spoken label
                    // ("Cash payment method, selected") so the user never hears "payments icon".
                    .semantics(mergeDescendants = true) {
                        role = Role.RadioButton
                        contentDescription = if (isSelected) {
                            "${method.label} payment method, selected"
                        } else {
                            "${method.label} payment method"
                        }
                    },
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
                        // a11y: decorative — the card's merged contentDescription carries the label
                        contentDescription = null,
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
            // CROSS32-ext: unified money-input affordance — $ leadingIcon +
            // "0.00" placeholder. Was `prefix = { Text("$") }`.
            leadingIcon = {
                Text(
                    "$",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            },
            placeholder = { Text("0.00") },
            modifier = Modifier
                .fillMaxWidth()
                // a11y: explicit contentDescription for the amount field so TalkBack
                // reads "Payment amount in dollars, edit box" instead of "Cash amount, edit box"
                // which omits the currency context a blind user needs.
                .semantics { contentDescription = "Payment amount in dollars" },
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
                // a11y: Role.Button + descriptive label so TalkBack reads
                // "Set exact amount, button" rather than just "Exact".
                modifier = Modifier
                    .weight(1f)
                    .semantics { contentDescription = "Set exact amount" },
            )
            if (total <= 5.0) {
                AssistChip(
                    onClick = { onRound(5) },
                    label = { Text("$5") },
                    // a11y: spoken as "Round up to 5 dollars, button"
                    modifier = Modifier
                        .weight(1f)
                        .semantics { contentDescription = "Round up to 5 dollars" },
                )
            }
            if (total <= 10.0) {
                AssistChip(
                    onClick = { onRound(10) },
                    label = { Text("$10") },
                    // a11y: spoken as "Round up to 10 dollars, button"
                    modifier = Modifier
                        .weight(1f)
                        .semantics { contentDescription = "Round up to 10 dollars" },
                )
            }
            AssistChip(
                onClick = { onRound(20) },
                label = { Text("$20") },
                // a11y: spoken as "Round up to 20 dollars, button"
                modifier = Modifier
                    .weight(1f)
                    .semantics { contentDescription = "Round up to 20 dollars" },
            )
            if (total > 20.0) {
                AssistChip(
                    onClick = { onRound(50) },
                    label = { Text("$50") },
                    // a11y: spoken as "Round up to 50 dollars, button"
                    modifier = Modifier
                        .weight(1f)
                        .semantics { contentDescription = "Round up to 50 dollars" },
                )
            }
            if (total > 50.0) {
                AssistChip(
                    onClick = { onRound(100) },
                    label = { Text("$100") },
                    // a11y: spoken as "Round up to 100 dollars, button"
                    modifier = Modifier
                        .weight(1f)
                        .semantics { contentDescription = "Round up to 100 dollars" },
                )
            }
        }

        // Change due display
        if (changeDue > 0) {
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    // a11y: liveRegion=Polite so TalkBack announces the updated change amount
                    // after each keystroke without interrupting mid-sentence. mergeDescendants
                    // collapses "Change Due" label + formatted value into a single focus stop.
                    .semantics(mergeDescendants = true) {
                        liveRegion = LiveRegionMode.Polite
                        contentDescription = "Change due: ${formatCurrency(changeDue)}"
                    },
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
