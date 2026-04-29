package com.bizarreelectronics.crm.ui.screens.financial

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.TrendingUp
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.ui.auth.PinDots
import com.bizarreelectronics.crm.ui.auth.PinKeypad
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import java.text.NumberFormat
import java.util.Locale

// ─── Money formatter ─────────────────────────────────────────────────────────

/** Format cents (Long) as US currency string, e.g. 12345L → "$123.45". */
private fun formatCents(cents: Long): String =
    NumberFormat.getCurrencyInstance(Locale.US).format(cents / 100.0)

// ─── Screen ──────────────────────────────────────────────────────────────────

/**
 * §62 Financial Dashboard (owner view).
 *
 * Role-gated: requires [isOwner] == true (caller reads [AuthPreferences.userRole]).
 * A 403 from the server is surfaced as a snackbar; the non-owner path renders an
 * access-denied card.
 *
 * §62.5: If the device has a PIN configured ([PinPreferences.isPinSet]) the screen
 * shows a blocking PIN re-prompt dialog before revealing any financial data.
 *
 * §62.1 P&L, §62.2 Cash Flow, §62.3 Tax Liability, §62.4 Budget vs Actual are
 * wired to [FinancialDashboardViewModel] but currently render "Coming soon" stubs
 * because the server endpoints `/reports/pl-summary`, `/reports/cashflow`,
 * `/reports/expense-breakdown` and the budget API do not exist yet.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FinancialDashboardScreen(
    isOwner: Boolean,
    onBack: () -> Unit,
    viewModel: FinancialDashboardViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    // §62.5 — PIN re-prompt: gate the content behind a one-time PIN entry
    // when the device has a PIN set. rememberSaveable so a rotation doesn't
    // re-show the dialog if the user already dismissed it in this session.
    var pinUnlocked by rememberSaveable { mutableStateOf(false) }
    var pinInput by remember { mutableStateOf("") }
    var pinError by remember { mutableStateOf(false) }
    val pinRequired = state.isPinConfigured && !pinUnlocked

    // Consume snackbar events from the ViewModel
    LaunchedEffect(state.snackbarMessage) {
        state.snackbarMessage?.let { msg ->
            snackbarHostState.showSnackbar(msg)
            viewModel.clearSnackbar()
        }
    }

    // Non-owner access-denied path — no PIN prompt needed
    if (!isOwner) {
        AccessDeniedContent(onBack = onBack)
        return
    }

    // PIN re-prompt dialog
    if (pinRequired) {
        PinRePromptDialog(
            pinInput = pinInput,
            isError = pinError,
            onDigit = { digit ->
                if (pinInput.length < 4) {
                    val next = pinInput + digit
                    pinInput = next
                    if (next.length == 4) {
                        if (viewModel.verifyPin(next)) {
                            pinUnlocked = true
                            pinError = false
                        } else {
                            pinError = true
                            pinInput = ""
                        }
                    } else {
                        pinError = false
                    }
                }
            },
            onDelete = {
                if (pinInput.isNotEmpty()) pinInput = pinInput.dropLast(1)
                pinError = false
            },
            onDismiss = onBack,
        )
        return
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        stringResource(R.string.screen_financial_dashboard),
                        style = MaterialTheme.typography.titleLarge,
                    )
                },
                navigationIcon = {
                    IconButton(
                        onClick = onBack,
                        modifier = Modifier.semantics {
                            contentDescription = "Navigate back"
                        },
                    ) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = null,
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                    titleContentColor = MaterialTheme.colorScheme.onSurface,
                ),
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { innerPadding ->
        if (state.isLoading) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding),
                contentAlignment = Alignment.Center,
            ) {
                CircularProgressIndicator(
                    modifier = Modifier.semantics {
                        contentDescription = "Loading financial data"
                    },
                )
            }
            return@Scaffold
        }

        if (state.error != null) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding),
                contentAlignment = Alignment.Center,
            ) {
                ErrorState(
                    message = state.error!!,
                    onRetry = { viewModel.load() },
                )
            }
            return@Scaffold
        }

        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {

            // ── §62.1 P&L snapshot ───────────────────────────────────────────
            item {
                PLSummaryCard(state = state)
            }

            // ── §62.2 Cash flow forecast ─────────────────────────────────────
            item {
                CashFlowCard(state = state)
            }

            // ── §62.3 Tax liability ──────────────────────────────────────────
            item {
                TaxLiabilityCard(state = state)
            }

            // ── §62.4 Budget vs actual ───────────────────────────────────────
            item {
                BudgetVsActualCard(state = state)
            }
        }
    }
}

// ─── P&L snapshot card ───────────────────────────────────────────────────────

/**
 * §62.1 — Profit & Loss snapshot card.
 *
 * Displays revenue / COGS / gross margin / operating expenses / net income.
 * Also shows period-over-period delta chip.
 *
 * Renders a "Coming soon" stub until the server exposes `/reports/pl-summary`.
 */
@Composable
private fun PLSummaryCard(state: FinancialDashboardUiState) {
    OutlinedCard(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Default.TrendingUp,
                    contentDescription = stringResource(R.string.cd_financial_pl_icon),
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(20.dp),
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    stringResource(R.string.financial_pl_title),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
            }

            Spacer(Modifier.height(12.dp))

            if (state.plSummary == null) {
                ComingSoonRow(
                    label = stringResource(R.string.financial_coming_soon_pl),
                )
            } else {
                val pl = state.plSummary
                PLLineItem(
                    label = stringResource(R.string.financial_pl_revenue),
                    valueCents = pl.revenueCents,
                )
                PLLineItem(
                    label = stringResource(R.string.financial_pl_cogs),
                    valueCents = pl.cogsCents,
                    isDeduction = true,
                )
                PLLineItem(
                    label = stringResource(R.string.financial_pl_gross_margin),
                    valueCents = pl.grossMarginCents,
                    isBold = true,
                )
                PLLineItem(
                    label = stringResource(R.string.financial_pl_opex),
                    valueCents = pl.opexCents,
                    isDeduction = true,
                )
                PLLineItem(
                    label = stringResource(R.string.financial_pl_net_income),
                    valueCents = pl.netIncomeCents,
                    isBold = true,
                    isHighlighted = true,
                )
                Spacer(Modifier.height(8.dp))
                if (pl.periodChangePct != null) {
                    AssistChip(
                        onClick = {},
                        label = {
                            Text(
                                text = stringResource(
                                    R.string.financial_pl_period_change,
                                    String.format(Locale.US, "%.1f", pl.periodChangePct),
                                ),
                                style = MaterialTheme.typography.labelSmall,
                            )
                        },
                    )
                }
            }
        }
    }
}

@Composable
private fun PLLineItem(
    label: String,
    valueCents: Long,
    isDeduction: Boolean = false,
    isBold: Boolean = false,
    isHighlighted: Boolean = false,
) {
    ListItem(
        headlineContent = {
            Text(
                label,
                style = if (isBold) MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold)
                else MaterialTheme.typography.bodyMedium,
            )
        },
        trailingContent = {
            Text(
                text = if (isDeduction) "(${formatCents(valueCents)})" else formatCents(valueCents),
                style = if (isBold) MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold)
                else MaterialTheme.typography.bodyMedium,
                color = when {
                    isHighlighted && valueCents >= 0 -> MaterialTheme.colorScheme.primary
                    isHighlighted && valueCents < 0 -> MaterialTheme.colorScheme.error
                    isDeduction -> MaterialTheme.colorScheme.error
                    else -> MaterialTheme.colorScheme.onSurface
                },
            )
        },
    )
}

// ─── Cash flow forecast card ─────────────────────────────────────────────────

/**
 * §62.2 — Cash flow forecast card.
 *
 * Shows upcoming invoices due + recurring expenses + projected cash at 30/60/90 days.
 * Renders a stub until `/reports/cashflow` exists.
 */
@Composable
private fun CashFlowCard(state: FinancialDashboardUiState) {
    OutlinedCard(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Default.Schedule,
                    contentDescription = stringResource(R.string.cd_financial_cashflow_icon),
                    tint = MaterialTheme.colorScheme.tertiary,
                    modifier = Modifier.size(20.dp),
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    stringResource(R.string.financial_cashflow_title),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
            }

            Spacer(Modifier.height(12.dp))

            if (state.cashFlow == null) {
                ComingSoonRow(
                    label = stringResource(R.string.financial_coming_soon_cashflow),
                )
            } else {
                val cf = state.cashFlow
                ListItem(
                    headlineContent = { Text(stringResource(R.string.financial_cashflow_invoices_due)) },
                    trailingContent = { Text(formatCents(cf.invoicesDueCents)) },
                )
                ListItem(
                    headlineContent = { Text(stringResource(R.string.financial_cashflow_recurring_expenses)) },
                    trailingContent = {
                        Text(
                            "(${formatCents(cf.recurringExpensesCents)})",
                            color = MaterialTheme.colorScheme.error,
                        )
                    },
                )
                Spacer(Modifier.height(8.dp))
                Text(
                    stringResource(R.string.financial_cashflow_projections),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.height(4.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    AssistChip(
                        onClick = {},
                        label = {
                            Text(
                                stringResource(R.string.financial_cashflow_30d, formatCents(cf.projected30dCents)),
                                style = MaterialTheme.typography.labelSmall,
                            )
                        },
                        modifier = Modifier.semantics {
                            contentDescription = "Projected cash in 30 days"
                        },
                    )
                    AssistChip(
                        onClick = {},
                        label = {
                            Text(
                                stringResource(R.string.financial_cashflow_60d, formatCents(cf.projected60dCents)),
                                style = MaterialTheme.typography.labelSmall,
                            )
                        },
                        modifier = Modifier.semantics {
                            contentDescription = "Projected cash in 60 days"
                        },
                    )
                    AssistChip(
                        onClick = {},
                        label = {
                            Text(
                                stringResource(R.string.financial_cashflow_90d, formatCents(cf.projected90dCents)),
                                style = MaterialTheme.typography.labelSmall,
                            )
                        },
                        modifier = Modifier.semantics {
                            contentDescription = "Projected cash in 90 days"
                        },
                    )
                }
            }
        }
    }
}

// ─── Tax liability card ───────────────────────────────────────────────────────

/**
 * §62.3 — Tax liability card.
 *
 * Shows per-jurisdiction collected + remitted status.
 * Renders stub until a tax-jurisdiction endpoint exists on the server.
 */
@Composable
private fun TaxLiabilityCard(state: FinancialDashboardUiState) {
    OutlinedCard(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Default.AccountBalance,
                    contentDescription = stringResource(R.string.cd_financial_tax_icon),
                    tint = MaterialTheme.colorScheme.secondary,
                    modifier = Modifier.size(20.dp),
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    stringResource(R.string.financial_tax_title),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
            }

            Spacer(Modifier.height(12.dp))

            if (state.taxRows.isEmpty()) {
                ComingSoonRow(
                    label = stringResource(R.string.financial_coming_soon_tax),
                )
            } else {
                state.taxRows.forEach { row ->
                    ListItem(
                        headlineContent = { Text(row.jurisdiction) },
                        supportingContent = {
                            Text(
                                stringResource(
                                    R.string.financial_tax_remitted_label,
                                    formatCents(row.remittedCents),
                                ),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        },
                        trailingContent = {
                            Column(horizontalAlignment = Alignment.End) {
                                Text(
                                    formatCents(row.collectedCents),
                                    style = MaterialTheme.typography.bodyMedium,
                                )
                                AssistChip(
                                    onClick = {},
                                    label = {
                                        Text(
                                            if (row.isRemitted) stringResource(R.string.financial_tax_remitted)
                                            else stringResource(R.string.financial_tax_pending),
                                            style = MaterialTheme.typography.labelSmall,
                                        )
                                    },
                                )
                            }
                        },
                    )
                }
            }
        }
    }
}

// ─── Budget vs actual card ────────────────────────────────────────────────────

/**
 * §62.4 — Budget vs actual card.
 *
 * Tenant defines monthly budget per category; dashboard shows delta.
 * Renders stub until the budget CRUD API exists on the server.
 */
@Composable
private fun BudgetVsActualCard(state: FinancialDashboardUiState) {
    OutlinedCard(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Default.BarChart,
                    contentDescription = stringResource(R.string.cd_financial_budget_icon),
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(20.dp),
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    stringResource(R.string.financial_budget_title),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
            }

            Spacer(Modifier.height(12.dp))

            if (state.budgetRows.isEmpty()) {
                ComingSoonRow(
                    label = stringResource(R.string.financial_coming_soon_budget),
                )
            } else {
                state.budgetRows.forEach { row ->
                    ListItem(
                        headlineContent = { Text(row.category) },
                        supportingContent = {
                            Text(
                                stringResource(
                                    R.string.financial_budget_vs_actual_label,
                                    formatCents(row.budgetCents),
                                    formatCents(row.actualCents),
                                ),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        },
                        trailingContent = {
                            val delta = row.actualCents - row.budgetCents
                            Text(
                                text = if (delta >= 0) "+${formatCents(delta)}" else formatCents(delta),
                                color = if (delta <= 0) MaterialTheme.colorScheme.primary
                                else MaterialTheme.colorScheme.error,
                                style = MaterialTheme.typography.bodyMedium,
                                fontWeight = FontWeight.Medium,
                            )
                        },
                    )
                }
            }
        }
    }
}

// ─── Shared composables ───────────────────────────────────────────────────────

@Composable
private fun ComingSoonRow(label: String) {
    Text(
        text = label,
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(vertical = 4.dp),
    )
}

@Composable
private fun AccessDeniedContent(onBack: () -> Unit) {
    Scaffold(
        topBar = {
            @OptIn(ExperimentalMaterial3Api::class)
            TopAppBar(
                title = { Text(stringResource(R.string.screen_financial_dashboard)) },
                navigationIcon = {
                    IconButton(
                        onClick = onBack,
                        modifier = Modifier.semantics {
                            contentDescription = "Navigate back"
                        },
                    ) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
            )
        },
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            contentAlignment = Alignment.Center,
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Icon(
                    Icons.Default.Lock,
                    contentDescription = stringResource(R.string.cd_financial_access_denied_icon),
                    modifier = Modifier.size(48.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    stringResource(R.string.financial_access_denied_title),
                    style = MaterialTheme.typography.titleMedium,
                )
                Text(
                    stringResource(R.string.financial_access_denied_body),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

// ─── PIN re-prompt dialog ─────────────────────────────────────────────────────

/**
 * §62.5 — One-time PIN re-prompt dialog shown before financial data is revealed.
 * Wraps [PinDots] + [PinKeypad] inside an [AlertDialog].
 * Dismiss navigates back rather than unlocking.
 */
@Composable
private fun PinRePromptDialog(
    pinInput: String,
    isError: Boolean,
    onDigit: (String) -> Unit,
    onDelete: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        icon = {
            Icon(
                Icons.Default.Lock,
                contentDescription = stringResource(R.string.cd_financial_pin_lock_icon),
                tint = MaterialTheme.colorScheme.primary,
            )
        },
        title = { Text(stringResource(R.string.financial_pin_prompt_title)) },
        text = {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(
                    stringResource(R.string.financial_pin_prompt_body),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.height(16.dp))
                PinDots(
                    entered = pinInput.length,
                    length = 4,
                )
                if (isError) {
                    Spacer(Modifier.height(4.dp))
                    Text(
                        stringResource(R.string.financial_pin_incorrect),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
                Spacer(Modifier.height(12.dp))
                PinKeypad(
                    onDigit = { char -> onDigit(char.toString()) },
                    onBackspace = onDelete,
                )
            }
        },
        confirmButton = {},
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.financial_pin_cancel))
            }
        },
    )
}
