package com.bizarreelectronics.crm.ui.screens.refunds

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.launch
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.remote.api.RefundRow
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.util.formatAsMoney

// ─── Constants ───────────────────────────────────────────────────────────────

/** Manager PIN is required for refunds above this threshold (in cents). §40.3 */
private const val MANAGER_PIN_THRESHOLD_CENTS = 5000L // $50.00

// PIN verification routes through the server (`POST /auth/verify-pin`) via
// PinRepository. We never embed a PIN in APK bytecode — extractable PINs in
// shipped APKs are a recurring app-store rejection cause.

// ─── Screen ──────────────────────────────────────────────────────────────────

/**
 * Refund management screen: create a new refund, list pending/completed refunds,
 * and approve/decline pending ones.
 *
 * §40.3 — original-tender path default (card → card via BlockChyp; cash → cash;
 * gift → reload gift). Alternative: store credit. Manager PIN required over
 * [MANAGER_PIN_THRESHOLD_CENTS].
 *
 * §40.2 — "Issue: refund → store credit option" is exposed via the Type dropdown.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RefundScreen(
    onBack: () -> Unit,
    viewModel: RefundViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()
    val listState by viewModel.listState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    var selectedTab by remember { mutableIntStateOf(0) }
    val tabs = listOf("New Refund", "Refund History")

    LaunchedEffect(uiState) {
        when (val s = uiState) {
            is RefundUiState.Error -> snackbarHostState.showSnackbar(s.message)
            is RefundUiState.Created -> {
                snackbarHostState.showSnackbar("Refund #${s.refundId} created — pending approval")
                viewModel.reset()
            }
            else -> Unit
        }
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Refunds",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                        )
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Column(modifier = Modifier.padding(padding)) {
            TabRow(selectedTabIndex = selectedTab) {
                tabs.forEachIndexed { index, title ->
                    Tab(
                        selected = selectedTab == index,
                        onClick = { selectedTab = index },
                        text = { Text(title, style = MaterialTheme.typography.labelMedium) },
                    )
                }
            }

            when (uiState) {
                is RefundUiState.NotAvailable -> NotAvailableCard(
                    modifier = Modifier.padding(16.dp),
                )
                else -> when (selectedTab) {
                    0 -> NewRefundTab(viewModel = viewModel, uiState = uiState)
                    1 -> RefundHistoryTab(listState = listState, viewModel = viewModel)
                }
            }
        }
    }
}

// ─── New Refund tab ───────────────────────────────────────────────────────────

@Composable
private fun NewRefundTab(
    viewModel: RefundViewModel,
    uiState: RefundUiState,
) {
    var invoiceIdText by remember { mutableStateOf("") }
    var customerIdText by remember { mutableStateOf("") }
    var amountText by remember { mutableStateOf("") }
    var reasonText by remember { mutableStateOf("") }
    var selectedType by remember { mutableStateOf("refund") }
    var selectedMethod by remember { mutableStateOf("") }
    var showPinDialog by remember { mutableStateOf(false) }
    var pinError by remember { mutableStateOf(false) }
    var pinVerifying by remember { mutableStateOf(false) }
    val coroutineScope = rememberCoroutineScope()

    val types = listOf("refund" to "Original Tender", "store_credit" to "Store Credit", "credit_note" to "Credit Note")
    val methods = listOf("" to "Auto-detect", "cash" to "Cash", "card" to "Card (BlockChyp)", "gift_card" to "Gift Card reload", "store_credit" to "Store Credit")

    val amountCents = ((amountText.toDoubleOrNull() ?: 0.0) * 100).toLong()
    val requiresPin = amountCents >= MANAGER_PIN_THRESHOLD_CENTS

    if (showPinDialog) {
        ManagerPinDialog(
            onConfirm = { pin ->
                if (pinVerifying) return@ManagerPinDialog
                pinVerifying = true
                pinError = false
                coroutineScope.launch {
                    val ok = viewModel.verifyManagerPin(pin)
                    pinVerifying = false
                    if (ok) {
                        showPinDialog = false
                        viewModel.createRefund(
                            invoiceId = invoiceIdText.toLongOrNull(),
                            customerId = customerIdText.toLong(),
                            amountCents = amountCents,
                            type = selectedType,
                            method = selectedMethod.takeIf { it.isNotBlank() },
                            reason = reasonText,
                        )
                    } else {
                        pinError = true
                    }
                }
            },
            onDismiss = { showPinDialog = false; pinError = false },
            isError = pinError,
        )
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("Create refund", style = MaterialTheme.typography.titleMedium)

        OutlinedTextField(
            value = customerIdText,
            onValueChange = { customerIdText = it },
            label = { Text("Customer ID *") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = invoiceIdText,
            onValueChange = { invoiceIdText = it },
            label = { Text("Invoice ID (optional)") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = amountText,
            onValueChange = { amountText = it },
            label = { Text("Amount (\$) *") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            trailingIcon = {
                if (requiresPin) {
                    Icon(
                        Icons.Default.Lock,
                        contentDescription = "Manager PIN required",
                        tint = MaterialTheme.colorScheme.error,
                    )
                }
            },
            modifier = Modifier.fillMaxWidth(),
        )

        if (requiresPin && amountText.isNotBlank()) {
            AssistChip(
                onClick = {},
                label = { Text("Manager PIN required (over \$${MANAGER_PIN_THRESHOLD_CENTS / 100})") },
                leadingIcon = {
                    Icon(
                        Icons.Default.Lock,
                        contentDescription = null,
                        modifier = Modifier.size(AssistChipDefaults.IconSize),
                    )
                },
                colors = AssistChipDefaults.assistChipColors(
                    containerColor = MaterialTheme.colorScheme.errorContainer,
                    labelColor = MaterialTheme.colorScheme.onErrorContainer,
                ),
            )
        }

        // §40.3 + §40.2 — Refund type selector
        // "store_credit" type implements the §40.2 "refund → store credit option"
        Text("Refund type", style = MaterialTheme.typography.labelMedium)
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            types.forEach { (value, label) ->
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    RadioButton(
                        selected = selectedType == value,
                        onClick = { selectedType = value },
                    )
                    Text(label, style = MaterialTheme.typography.bodyMedium)
                }
            }
        }

        // §40.3 — original-tender method selector
        Text("Refund method", style = MaterialTheme.typography.labelMedium)
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            methods.forEach { (value, label) ->
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    RadioButton(
                        selected = selectedMethod == value,
                        onClick = { selectedMethod = value },
                    )
                    Text(label, style = MaterialTheme.typography.bodyMedium)
                }
            }
        }

        OutlinedTextField(
            value = reasonText,
            onValueChange = { reasonText = it },
            label = { Text("Reason") },
            singleLine = false,
            maxLines = 3,
            modifier = Modifier.fillMaxWidth(),
        )

        val canSubmit = uiState !is RefundUiState.Loading
            && amountText.isNotBlank()
            && customerIdText.isNotBlank()
            && (amountText.toDoubleOrNull() ?: 0.0) > 0.0

        FilledTonalButton(
            onClick = {
                if (requiresPin) {
                    showPinDialog = true
                } else {
                    viewModel.createRefund(
                        invoiceId = invoiceIdText.toLongOrNull(),
                        customerId = customerIdText.toLongOrNull() ?: return@FilledTonalButton,
                        amountCents = amountCents,
                        type = selectedType,
                        method = selectedMethod.takeIf { it.isNotBlank() },
                        reason = reasonText,
                    )
                }
            },
            enabled = canSubmit,
            modifier = Modifier.fillMaxWidth(),
        ) {
            if (uiState is RefundUiState.Loading) {
                CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
            } else {
                Icon(Icons.Default.AssignmentReturn, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text(if (requiresPin) "Submit (requires PIN)" else "Submit Refund")
            }
        }
    }
}

// ─── Refund history tab ───────────────────────────────────────────────────────

@Composable
private fun RefundHistoryTab(
    listState: RefundListState,
    viewModel: RefundViewModel,
) {
    when (listState) {
        is RefundListState.Loading -> {
            Box(
                modifier = Modifier.fillMaxSize().padding(32.dp),
                contentAlignment = Alignment.Center,
            ) { CircularProgressIndicator() }
        }
        is RefundListState.NotAvailable -> NotAvailableCard(modifier = Modifier.padding(16.dp))
        is RefundListState.Error -> {
            Column(modifier = Modifier.padding(16.dp)) {
                Text(
                    listState.message,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
                Spacer(Modifier.height(8.dp))
                OutlinedButton(onClick = { viewModel.loadRefunds() }) { Text("Retry") }
            }
        }
        is RefundListState.Loaded -> {
            if (listState.refunds.isEmpty()) {
                Box(
                    modifier = Modifier.fillMaxSize().padding(32.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        "No refunds yet",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            } else {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState())
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    listState.refunds.forEach { refund ->
                        RefundListItem(refund = refund, viewModel = viewModel)
                    }
                }
            }
        }
    }
}

@Composable
private fun RefundListItem(
    refund: RefundRow,
    viewModel: RefundViewModel,
) {
    val amountCents = (refund.amount * 100).toLong()
    val statusColor = when (refund.status) {
        "completed" -> MaterialTheme.colorScheme.primaryContainer
        "declined" -> MaterialTheme.colorScheme.errorContainer
        else -> MaterialTheme.colorScheme.surfaceVariant
    }
    val customerName = listOfNotNull(refund.firstName, refund.lastName)
        .joinToString(" ")
        .ifBlank { "Customer #${refund.customerId}" }

    BrandCard(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column {
                    Text(
                        "Refund #${refund.id}",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        customerName,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Column(horizontalAlignment = Alignment.End) {
                    Text(
                        amountCents.formatAsMoney(),
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Bold,
                    )
                    Badge(containerColor = statusColor) {
                        Text(refund.status, style = MaterialTheme.typography.labelSmall)
                    }
                }
            }

            if (!refund.reason.isNullOrBlank()) {
                Spacer(Modifier.height(4.dp))
                Text(
                    refund.reason,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            val typeLabel = when (refund.type) {
                "store_credit" -> "→ Store Credit"
                "credit_note" -> "→ Credit Note"
                else -> refund.method?.let { "via $it" } ?: "Original tender"
            }
            Text(
                typeLabel,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            if (refund.status == "pending") {
                Spacer(Modifier.height(8.dp))
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    OutlinedButton(
                        onClick = { viewModel.declineRefund(refund.id) },
                        modifier = Modifier.weight(1f),
                    ) {
                        Icon(Icons.Default.Close, contentDescription = "Decline")
                        Spacer(Modifier.width(4.dp))
                        Text("Decline")
                    }
                    FilledTonalButton(
                        onClick = { viewModel.approveRefund(refund.id) },
                        modifier = Modifier.weight(1f),
                    ) {
                        Icon(Icons.Default.Check, contentDescription = "Approve")
                        Spacer(Modifier.width(4.dp))
                        Text("Approve")
                    }
                }
            }
        }
    }
}

// ─── Manager PIN dialog ───────────────────────────────────────────────────────

/**
 * §40.3 — Manager PIN dialog for refunds above the threshold.
 * Accepts the 4-digit device PIN. PIN is compared locally against the
 * hardcoded constant; the server enforces role-based access independently.
 */
@Composable
private fun ManagerPinDialog(
    onConfirm: (String) -> Unit,
    onDismiss: () -> Unit,
    isError: Boolean,
) {
    var pinText by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        icon = {
            Icon(Icons.Default.Lock, contentDescription = "Manager PIN required")
        },
        title = { Text("Manager PIN Required") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    "Refunds above \$${MANAGER_PIN_THRESHOLD_CENTS / 100} require manager authorization.",
                    style = MaterialTheme.typography.bodyMedium,
                )
                OutlinedTextField(
                    value = pinText,
                    onValueChange = { if (it.length <= 4 && it.all { c -> c.isDigit() }) pinText = it },
                    label = { Text("PIN") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                    isError = isError,
                    supportingText = if (isError) {
                        { Text("Incorrect PIN", color = MaterialTheme.colorScheme.error) }
                    } else null,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onConfirm(pinText) },
                enabled = pinText.length == 4,
            ) { Text("Authorize") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}

// ─── Not-available card ───────────────────────────────────────────────────────

@Composable
private fun NotAvailableCard(modifier: Modifier = Modifier) {
    BrandCard(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(24.dp).fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(
                Icons.Default.AssignmentReturn,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(40.dp),
            )
            Text(
                "Refunds not available on this server",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                "Update your server to enable the refund endpoints.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
