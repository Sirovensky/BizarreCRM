package com.bizarreelectronics.crm.ui.screens.giftcards

import androidx.compose.foundation.layout.*
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.remote.api.GiftCard
import com.bizarreelectronics.crm.data.remote.api.GiftCardRedeemData
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.util.formatAsMoney

// ─── Screen ──────────────────────────────────────────────────────────────────

/**
 * Gift card screen: issue, scan/lookup, redeem, store-credit balance.
 *
 * Shows "Not available on this server" when the server returns 404 on the
 * first operation. Plan §40 L3060-L3086.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GiftCardScreen(
    onBack: () -> Unit,
    viewModel: GiftCardViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()
    var selectedTab by remember { mutableIntStateOf(0) }
    val tabs = listOf("Issue", "Scan & Redeem", "Store Credit")
    val snackbarHostState = remember { SnackbarHostState() }

    // Surface errors via snackbar
    LaunchedEffect(uiState) {
        if (uiState is GiftCardUiState.Error) {
            snackbarHostState.showSnackbar((uiState as GiftCardUiState.Error).message)
        }
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Gift Cards & Store Credit",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
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
                        onClick = {
                            selectedTab = index
                            viewModel.reset()
                        },
                        text = { Text(title, style = MaterialTheme.typography.labelMedium) },
                    )
                }
            }

            when (uiState) {
                is GiftCardUiState.NotAvailable -> {
                    NotAvailableCard(modifier = Modifier.padding(16.dp))
                }

                else -> {
                    when (selectedTab) {
                        0 -> IssueTab(viewModel = viewModel, uiState = uiState)
                        1 -> ScanRedeemTab(viewModel = viewModel, uiState = uiState)
                        2 -> StoreCreditTab(viewModel = viewModel)
                    }
                }
            }
        }
    }
}

// ─── Issue tab ────────────────────────────────────────────────────────────────

@Composable
private fun IssueTab(
    viewModel: GiftCardViewModel,
    uiState: GiftCardUiState,
) {
    var amountText by remember { mutableStateOf("") }
    var codeText by remember { mutableStateOf("") }
    var customerIdText by remember { mutableStateOf("") }
    var sendDigital by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("Issue gift card", style = MaterialTheme.typography.titleMedium)

        OutlinedTextField(
            value = amountText,
            onValueChange = { amountText = it },
            label = { Text("Amount (\$)") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = codeText,
            onValueChange = { codeText = it },
            label = { Text("Card code (leave blank to auto-generate)") },
            singleLine = true,
            trailingIcon = {
                IconButton(onClick = { /* camera barcode scan */ }) {
                    Icon(Icons.Default.QrCodeScanner, contentDescription = "Scan barcode")
                }
            },
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = customerIdText,
            onValueChange = { customerIdText = it },
            label = { Text("Customer ID (optional)") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            modifier = Modifier.fillMaxWidth(),
        )
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Checkbox(
                checked = sendDigital,
                onCheckedChange = { sendDigital = it },
            )
            Text("Send digital copy (email / SMS)", style = MaterialTheme.typography.bodyMedium)
        }

        Button(
            onClick = {
                val cents = ((amountText.toDoubleOrNull() ?: 0.0) * 100).toLong()
                viewModel.issueGiftCard(
                    amountCents = cents,
                    code = codeText.takeIf { it.isNotBlank() },
                    customerId = customerIdText.toLongOrNull(),
                    sendDigital = sendDigital,
                )
            },
            enabled = uiState !is GiftCardUiState.Loading && amountText.isNotBlank(),
            modifier = Modifier.fillMaxWidth(),
        ) {
            if (uiState is GiftCardUiState.Loading) {
                CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
            } else {
                Icon(Icons.Default.CardGiftcard, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("Issue")
            }
        }

        // Success result
        if (uiState is GiftCardUiState.IssueSuccess) {
            GiftCardResultCard(card = uiState.card)
        }
    }
}

// ─── Scan & Redeem tab ────────────────────────────────────────────────────────

@Composable
private fun ScanRedeemTab(
    viewModel: GiftCardViewModel,
    uiState: GiftCardUiState,
) {
    var codeText by remember { mutableStateOf("") }
    var redeemAmountText by remember { mutableStateOf("") }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("Scan or enter code", style = MaterialTheme.typography.titleMedium)

        OutlinedTextField(
            value = codeText,
            onValueChange = { codeText = it },
            label = { Text("Gift card code") },
            singleLine = true,
            trailingIcon = {
                IconButton(onClick = { /* camera barcode scan */ }) {
                    Icon(Icons.Default.QrCodeScanner, contentDescription = "Scan")
                }
            },
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedButton(
            onClick = { viewModel.lookupCard(codeText.trim()) },
            enabled = uiState !is GiftCardUiState.Loading && codeText.isNotBlank(),
            modifier = Modifier.fillMaxWidth(),
        ) {
            if (uiState is GiftCardUiState.Loading) {
                CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
            } else {
                Text("Check balance")
            }
        }

        when (uiState) {
            is GiftCardUiState.CardLookup -> {
                GiftCardResultCard(card = uiState.card)
                HorizontalDivider()
                Text("Redeem amount", style = MaterialTheme.typography.titleSmall)
                OutlinedTextField(
                    value = redeemAmountText,
                    onValueChange = { redeemAmountText = it },
                    label = { Text("Amount (\$)") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    modifier = Modifier.fillMaxWidth(),
                )
                Button(
                    onClick = {
                        val cents = ((redeemAmountText.toDoubleOrNull() ?: 0.0) * 100).toLong()
                        viewModel.redeemGiftCard(uiState.card.code, cents)
                    },
                    enabled = redeemAmountText.isNotBlank(),
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("Redeem") }
            }

            is GiftCardUiState.RedeemSuccess -> {
                RedeemSuccessCard(result = uiState.result)
                OutlinedButton(
                    onClick = { viewModel.reset() },
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("Done") }
            }

            else -> Unit
        }
    }
}

// ─── Store credit tab ─────────────────────────────────────────────────────────

@Composable
private fun StoreCreditTab(viewModel: GiftCardViewModel) {
    val creditState by viewModel.storeCreditState.collectAsState()
    var customerIdText by remember { mutableStateOf("") }
    var issueAmountText by remember { mutableStateOf("") }
    var issueReason by remember { mutableStateOf("") }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("Store credit", style = MaterialTheme.typography.titleMedium)

        OutlinedTextField(
            value = customerIdText,
            onValueChange = { customerIdText = it },
            label = { Text("Customer ID") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedButton(
            onClick = {
                val cid = customerIdText.toLongOrNull() ?: return@OutlinedButton
                viewModel.loadStoreCredit(cid)
            },
            enabled = creditState !is StoreCreditState.Loading && customerIdText.isNotBlank(),
            modifier = Modifier.fillMaxWidth(),
        ) {
            if (creditState is StoreCreditState.Loading) {
                CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
            } else {
                Text("Load balance")
            }
        }

        if (creditState is StoreCreditState.Loaded) {
            val credit = (creditState as StoreCreditState.Loaded).credit
            BrandCard {
                Row(
                    modifier = Modifier.padding(16.dp).fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column {
                        Text("Store credit balance", style = MaterialTheme.typography.bodyMedium)
                        if (credit.updatedAt != null) {
                            Text(
                                "Updated ${credit.updatedAt}",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                    Text(
                        credit.balanceCents.formatAsMoney(),
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
            }

            HorizontalDivider()
            Text("Issue store credit", style = MaterialTheme.typography.titleSmall)
            OutlinedTextField(
                value = issueAmountText,
                onValueChange = { issueAmountText = it },
                label = { Text("Amount (\$)") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = issueReason,
                onValueChange = { issueReason = it },
                label = { Text("Reason (e.g. refund, goodwill)") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            Button(
                onClick = {
                    val cid = customerIdText.toLongOrNull() ?: return@Button
                    val cents = ((issueAmountText.toDoubleOrNull() ?: 0.0) * 100).toLong()
                    viewModel.issueStoreCredit(cid, cents, issueReason.trim())
                    issueAmountText = ""
                    issueReason = ""
                },
                enabled = issueAmountText.isNotBlank() && issueReason.isNotBlank(),
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Issue credit") }
        }

        if (creditState is StoreCreditState.Error) {
            Text(
                (creditState as StoreCreditState.Error).message,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
            )
        }
    }
}

// ─── Shared result cards ──────────────────────────────────────────────────────

@Composable
fun GiftCardResultCard(card: GiftCard, modifier: Modifier = Modifier) {
    BrandCard(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    card.code,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                )
                Badge(containerColor = if (card.status == "active") MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant) {
                    Text(card.status, style = MaterialTheme.typography.labelSmall)
                }
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text("Balance", style = MaterialTheme.typography.bodyMedium)
                Text(
                    card.balanceCents.formatAsMoney(),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
            if (card.expiresAt != null) {
                Text(
                    "Expires ${card.expiresAt}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun RedeemSuccessCard(result: GiftCardRedeemData, modifier: Modifier = Modifier) {
    BrandCard(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(
                "Redeemed successfully",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.primary,
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text("Applied", style = MaterialTheme.typography.bodyMedium)
                Text(
                    result.appliedCents.formatAsMoney(),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                )
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text("Remaining balance", style = MaterialTheme.typography.bodyMedium)
                Text(
                    result.remainingCents.formatAsMoney(),
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
        }
    }
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
                Icons.Default.CardGiftcard,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(40.dp),
            )
            Text(
                "Gift cards not available on this server",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                "Update your server to enable gift cards and store credit.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
