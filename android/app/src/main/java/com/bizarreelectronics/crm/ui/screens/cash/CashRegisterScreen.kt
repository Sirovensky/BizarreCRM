package com.bizarreelectronics.crm.ui.screens.cash

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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.remote.api.CashShift
import com.bizarreelectronics.crm.data.remote.api.TenderBreakdown
import com.bizarreelectronics.crm.data.remote.api.ZReport
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.BrandPrimaryButton
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.util.formatAsMoney

// ─── Screen ──────────────────────────────────────────────────────────────────

/**
 * Cash register screen: shift open/close, Z-report, pay-in/pay-out.
 *
 * Shows "Not available on this server" when the server returns 404.
 * Plan §39 L3027-L3058.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CashRegisterScreen(
    onBack: () -> Unit,
    viewModel: CashRegisterViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()
    val actionState by viewModel.actionState.collectAsState()
    var showOpenDialog by remember { mutableStateOf(false) }
    var showCloseDialog by remember { mutableStateOf(false) }
    var showPayInDialog by remember { mutableStateOf(false) }
    var showPayOutDialog by remember { mutableStateOf(false) }
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(actionState) {
        if (actionState is ShiftActionState.Error) {
            snackbarHostState.showSnackbar((actionState as ShiftActionState.Error).message)
            viewModel.clearActionError()
        }
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Cash Register",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        when (val state = uiState) {
            is CashRegisterUiState.Loading -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            }

            is CashRegisterUiState.NotAvailable -> {
                NotAvailableCard(modifier = Modifier.padding(padding).padding(16.dp))
            }

            is CashRegisterUiState.Error -> {
                ErrorState(
                    message = state.message,
                    onRetry = { viewModel.loadCurrentShift() },
                    modifier = Modifier.padding(padding),
                )
            }

            is CashRegisterUiState.NoShift -> {
                NoShiftPanel(
                    onOpenShift = { showOpenDialog = true },
                    modifier = Modifier.padding(padding).fillMaxSize(),
                )
            }

            is CashRegisterUiState.ShiftOpen -> {
                ShiftOpenPanel(
                    shift = state.shift,
                    isLoading = actionState is ShiftActionState.Loading,
                    onXReport = { viewModel.fetchXReport(state.shift.id) },
                    onPayIn = { showPayInDialog = true },
                    onPayOut = { showPayOutDialog = true },
                    onCloseShift = { showCloseDialog = true },
                    modifier = Modifier.padding(padding),
                )
            }

            is CashRegisterUiState.ZReportReady -> {
                ZReportPanel(
                    report = state.report,
                    onDismiss = { viewModel.dismissZReport() },
                    modifier = Modifier.padding(padding),
                )
            }
        }
    }

    // Open shift dialog
    if (showOpenDialog) {
        OpenShiftDialog(
            isLoading = actionState is ShiftActionState.Loading,
            onDismiss = { showOpenDialog = false },
            onConfirm = { registerId, startingCents ->
                viewModel.openShift(registerId, startingCents)
                showOpenDialog = false
            },
        )
    }

    // Close shift dialog
    val currentShift = (uiState as? CashRegisterUiState.ShiftOpen)?.shift
    if (showCloseDialog && currentShift != null) {
        CloseShiftDialog(
            expectedCashCents = currentShift.expectedCashCents,
            isLoading = actionState is ShiftActionState.Loading,
            onDismiss = { showCloseDialog = false },
            onConfirm = { closingCents, reason ->
                viewModel.closeShift(currentShift.id, closingCents, reason)
                showCloseDialog = false
            },
        )
    }

    // Pay-in / pay-out dialogs
    if (showPayInDialog && currentShift != null) {
        PayInOutDialog(
            title = "Pay-in",
            onDismiss = { showPayInDialog = false },
            onConfirm = { amountCents, reason ->
                viewModel.payIn(currentShift.id, amountCents, reason)
                showPayInDialog = false
            },
        )
    }
    if (showPayOutDialog && currentShift != null) {
        PayInOutDialog(
            title = "Pay-out",
            onDismiss = { showPayOutDialog = false },
            onConfirm = { amountCents, reason ->
                viewModel.payOut(currentShift.id, amountCents, reason)
                showPayOutDialog = false
            },
        )
    }
}

// ─── No-shift panel ───────────────────────────────────────────────────────────

@Composable
private fun NoShiftPanel(onOpenShift: () -> Unit, modifier: Modifier = Modifier) {
    Box(modifier = modifier, contentAlignment = Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Icon(
                Icons.Default.PointOfSale,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(56.dp),
            )
            Text("No shift open", style = MaterialTheme.typography.titleMedium)
            BrandPrimaryButton(text = "Open shift", onClick = onOpenShift)
        }
    }
}

// ─── Shift-open panel ─────────────────────────────────────────────────────────

@Composable
private fun ShiftOpenPanel(
    shift: CashShift,
    isLoading: Boolean,
    onXReport: () -> Unit,
    onPayIn: () -> Unit,
    onPayOut: () -> Unit,
    onCloseShift: () -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            BrandCard {
                Column(
                    modifier = Modifier.padding(16.dp).fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text("Shift open", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "Register: ${shift.registerId ?: "—"}",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    Text(
                        "Started: ${shift.startedAt ?: "—"}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
                    ShiftStatRow(
                        label = "Opening cash",
                        value = shift.startingCashCents.formatAsMoney(),
                    )
                    ShiftStatRow(
                        label = "Expected cash",
                        value = shift.expectedCashCents.formatAsMoney(),
                    )
                    ShiftStatRow(
                        label = "Sales",
                        value = "${shift.salesCount} · ${shift.salesTotalCents.formatAsMoney()}",
                    )
                }
            }
        }

        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                OutlinedButton(
                    onClick = onXReport,
                    enabled = !isLoading,
                    modifier = Modifier.weight(1f),
                ) { Text("X-Report") }
                OutlinedButton(
                    onClick = onPayIn,
                    enabled = !isLoading,
                    modifier = Modifier.weight(1f),
                ) { Text("Pay-in") }
                OutlinedButton(
                    onClick = onPayOut,
                    enabled = !isLoading,
                    modifier = Modifier.weight(1f),
                ) { Text("Pay-out") }
            }
        }

        item {
            Button(
                onClick = onCloseShift,
                enabled = !isLoading,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.error,
                ),
            ) {
                if (isLoading) {
                    CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                } else {
                    Icon(Icons.Default.Close, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text("Close shift & Z-report")
                }
            }
        }
    }
}

@Composable
private fun ShiftStatRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, style = MaterialTheme.typography.bodyMedium)
        Text(
            value,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold,
        )
    }
}

// ─── Z-report panel ───────────────────────────────────────────────────────────

@Composable
private fun ZReportPanel(
    report: ZReport,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Text(
                "Z-Report — Shift #${report.shiftId}",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
            )
        }

        item {
            BrandCard {
                Column(
                    modifier = Modifier.padding(16.dp).fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    ZRow("Cashier", report.cashier ?: "—")
                    ZRow("Register", report.registerId ?: "—")
                    ZRow("Opened", report.startedAt ?: "—")
                    ZRow("Closed", report.closedAt ?: "—")
                }
            }
        }

        item {
            BrandCard {
                Column(
                    modifier = Modifier.padding(16.dp).fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Text("Sales summary", style = MaterialTheme.typography.titleSmall)
                    ZRow("Sales count", "${report.salesCount}")
                    ZRow("Gross", report.grossCents.formatAsMoney())
                    ZRow("Net", report.netCents.formatAsMoney())
                    ZRow("Tips", report.tipsCents.formatAsMoney())
                    ZRow("Refunds", "${report.refundsCount} · ${report.refundsTotalCents.formatAsMoney()}")
                    ZRow("Voids", "${report.voidsCount}")
                }
            }
        }

        // Tender breakdown
        if (report.tenderBreakdown.isNotEmpty()) {
            item {
                BrandCard {
                    Column(
                        modifier = Modifier.padding(16.dp).fillMaxWidth(),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Text("By tender", style = MaterialTheme.typography.titleSmall)
                        report.tenderBreakdown.forEach { t ->
                            TenderRow(t)
                        }
                    }
                }
            }
        }

        // Cash reconciliation
        item {
            val overShort = report.overShortCents
            val overShortLabel = when {
                overShort > 0  -> "+${overShort.formatAsMoney()} (over)"
                overShort < 0  -> "${overShort.formatAsMoney()} (short)"
                else           -> "Balanced"
            }
            BrandCard {
                Column(
                    modifier = Modifier.padding(16.dp).fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Text("Cash reconciliation", style = MaterialTheme.typography.titleSmall)
                    ZRow("Opening cash", report.openingCashCents.formatAsMoney())
                    ZRow("Expected cash", report.expectedCashCents.formatAsMoney())
                    ZRow("Counted cash", (report.closingCashCents ?: 0L).formatAsMoney())
                    ZRow("Over / short", overShortLabel)
                }
            }
        }

        // Top items
        if (report.topItems.isNotEmpty()) {
            item {
                BrandCard {
                    Column(
                        modifier = Modifier.padding(16.dp).fillMaxWidth(),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Text("Top items", style = MaterialTheme.typography.titleSmall)
                        report.topItems.take(5).forEach { item ->
                            ZRow(item.name, "×${item.qty} · ${item.totalCents.formatAsMoney()}")
                        }
                    }
                }
            }
        }

        item {
            OutlinedButton(
                onClick = onDismiss,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Done")
            }
        }
    }
}

@Composable
private fun ZRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(value, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
    }
}

@Composable
private fun TenderRow(t: TenderBreakdown) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            t.tender.replaceFirstChar { it.uppercase() },
            style = MaterialTheme.typography.bodyMedium,
        )
        Text(
            "${t.salesCount} · ${t.salesTotalCents.formatAsMoney()}",
            style = MaterialTheme.typography.bodyMedium,
        )
    }
}

// ─── Open shift dialog ────────────────────────────────────────────────────────

@Composable
private fun OpenShiftDialog(
    isLoading: Boolean,
    onDismiss: () -> Unit,
    onConfirm: (registerId: String, startingCents: Long) -> Unit,
) {
    var registerId by remember { mutableStateOf("REG-01") }
    var startingCashText by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Open shift") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value = registerId,
                    onValueChange = { registerId = it },
                    label = { Text("Register ID") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = startingCashText,
                    onValueChange = { startingCashText = it },
                    label = { Text("Starting cash (\$)") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    val cents = ((startingCashText.toDoubleOrNull() ?: 0.0) * 100).toLong()
                    onConfirm(registerId.trim(), cents)
                },
                enabled = !isLoading,
            ) {
                if (isLoading) {
                    CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                } else {
                    Text("Open")
                }
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}

// ─── Close shift dialog ───────────────────────────────────────────────────────

@Composable
private fun CloseShiftDialog(
    expectedCashCents: Long,
    isLoading: Boolean,
    onDismiss: () -> Unit,
    onConfirm: (closingCents: Long, reason: String?) -> Unit,
) {
    var closingCashText by remember { mutableStateOf("") }
    var overShortReason by remember { mutableStateOf("") }
    val closingCents = ((closingCashText.toDoubleOrNull() ?: 0.0) * 100).toLong()
    val diff = closingCents - expectedCashCents
    val showReason = kotlin.math.abs(diff) > 200   // > $2

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Close shift") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    "Expected: ${expectedCashCents.formatAsMoney()}",
                    style = MaterialTheme.typography.bodyMedium,
                )
                OutlinedTextField(
                    value = closingCashText,
                    onValueChange = { closingCashText = it },
                    label = { Text("Counted cash (\$)") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    modifier = Modifier.fillMaxWidth(),
                )
                if (closingCashText.isNotBlank() && showReason) {
                    val diffLabel = if (diff > 0) "+${diff.formatAsMoney()} over"
                                    else "${diff.formatAsMoney()} short"
                    Text(
                        "Variance: $diffLabel — reason required",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                    OutlinedTextField(
                        value = overShortReason,
                        onValueChange = { overShortReason = it },
                        label = { Text("Reason") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    onConfirm(
                        closingCents,
                        overShortReason.takeIf { it.isNotBlank() },
                    )
                },
                enabled = !isLoading && closingCashText.isNotBlank() &&
                          (!showReason || overShortReason.isNotBlank()),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.error,
                ),
            ) {
                if (isLoading) {
                    CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                } else {
                    Text("Close & Z-Report")
                }
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}

// ─── Pay-in / pay-out dialog ──────────────────────────────────────────────────

@Composable
private fun PayInOutDialog(
    title: String,
    onDismiss: () -> Unit,
    onConfirm: (amountCents: Long, reason: String) -> Unit,
) {
    var amountText by remember { mutableStateOf("") }
    var reason by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value = amountText,
                    onValueChange = { amountText = it },
                    label = { Text("Amount (\$)") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = reason,
                    onValueChange = { reason = it },
                    label = { Text("Reason") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    val cents = ((amountText.toDoubleOrNull() ?: 0.0) * 100).toLong()
                    onConfirm(cents, reason.trim())
                },
                enabled = amountText.isNotBlank() && reason.isNotBlank(),
            ) { Text("Confirm") }
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
                Icons.Default.PointOfSale,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(40.dp),
            )
            Text(
                "Cash register not available on this server",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                "Update your server to enable cash sessions and Z-reports.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
