package com.bizarreelectronics.crm.ui.screens.pos

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.ui.theme.LocalExtendedColors

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PosTenderScreen(
    onNavigateToReceipt: (orderId: String) -> Unit,
    onBack: () -> Unit,
    viewModel: PosTenderViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsState()
    var showCashDialog by remember { mutableStateOf(false) }

    // Navigate when order completes
    LaunchedEffect(state.completedOrderId) {
        state.completedOrderId?.let { onNavigateToReceipt(it) }
    }

    if (showCashDialog) {
        CashTenderDialog(
            remainingCents = state.remainingCents,
            onApply = { receivedCents ->
                viewModel.applyCash(receivedCents)
                showCashDialog = false
            },
            onDismiss = { showCashDialog = false },
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Text("‹", style = MaterialTheme.typography.headlineMedium, color = MaterialTheme.colorScheme.onSurface)
                    }
                },
                title = { Text("Tender") },
                actions = {
                    Surface(
                        shape = RoundedCornerShape(99.dp),
                        color = MaterialTheme.colorScheme.primary,
                    ) {
                        Text(
                            state.totalCents.toDollarString(),
                            modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp),
                            style = MaterialTheme.typography.labelMedium,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onPrimary,
                        )
                    }
                    Spacer(modifier = Modifier.width(8.dp))
                },
            )
        },
        bottomBar = {
            TenderActionBar(state = state, onFinalize = viewModel::finalizeSale)
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding).padding(horizontal = 14.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
            contentPadding = PaddingValues(vertical = 14.dp),
        ) {
            // ── Hero balance card ──────────────────────────────────────────────
            item {
                BalanceHeroCard(state = state)
            }

            // ── Applied tenders ────────────────────────────────────────────────
            if (state.appliedTenders.isNotEmpty()) {
                item {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            "✓ PAID · ${state.appliedTenders.size}",
                            style = MaterialTheme.typography.labelSmall,
                            color = LocalExtendedColors.current.success,
                            fontWeight = FontWeight.Bold,
                        )
                        Text(
                            "Tap ✕ to undo",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                items(state.appliedTenders, key = { it.id }) { tender ->
                    AppliedTenderCard(tender = tender, onRemove = { viewModel.removeTender(tender.id) })
                }
            }

            // ── Add payment grid ───────────────────────────────────────────────
            item {
                Text(
                    "+ ADD PAYMENT FOR REMAINING ${state.remainingCents.toDollarString()}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            item {
                PaymentMethodGrid(
                    remainingCents = state.remainingCents,
                    onCardReader = { viewModel.chargeCard(state.remainingCents) },
                    onCash = { showCashDialog = true },
                    onAch = { viewModel.applyAch(state.remainingCents) },
                    onParkCart = { viewModel.parkCart() },
                )
            }
        }
    }

    state.errorMessage?.let { msg ->
        val snackbarHostState = remember { SnackbarHostState() }
        LaunchedEffect(msg) {
            snackbarHostState.showSnackbar(msg)
            viewModel.clearError()
        }
    }
}

// ─── Balance hero card ────────────────────────────────────────────────────────

@Composable
private fun BalanceHeroCard(state: PosTenderUiState) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
    ) {
        Column(modifier = Modifier.padding(14.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Bottom,
            ) {
                Column {
                    Text("TOTAL DUE", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(state.totalCents.toDollarString(), style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.ExtraBold)
                }
                Column(horizontalAlignment = Alignment.End) {
                    Text("REMAINING", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(
                        state.remainingCents.toDollarString(),
                        style = MaterialTheme.typography.headlineMedium,
                        fontWeight = FontWeight.ExtraBold,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
            }
            Spacer(modifier = Modifier.height(10.dp))
            // M3 Expressive default trackColor tints close to the active color,
            // which read as 'paid in full' on dark surfaces even at 0% paid.
            // Force trackColor to surfaceVariant so the inactive segment reads
            // as muted grey vs the green active segment.
            LinearProgressIndicator(
                progress = { state.paidPercent },
                modifier = Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(3.dp)),
                color = LocalExtendedColors.current.success,
                trackColor = MaterialTheme.colorScheme.surfaceVariant,
                gapSize = 0.dp,
                drawStopIndicator = {},
            )
            Spacer(modifier = Modifier.height(4.dp))
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(
                    "✓ Paid ${state.paidCents.toDollarString()}",
                    style = MaterialTheme.typography.labelSmall,
                    color = LocalExtendedColors.current.success,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    "${(state.paidPercent * 100).toInt()}%",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

// ─── Applied tender card ──────────────────────────────────────────────────────

@Composable
private fun AppliedTenderCard(tender: AppliedTender, onRemove: () -> Unit) {
    val success = LocalExtendedColors.current.success
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .border(1.dp, success, RoundedCornerShape(10.dp))
            .background(success.copy(alpha = 0.08f))
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(
            modifier = Modifier.size(26.dp).clip(CircleShape).background(success),
            contentAlignment = Alignment.Center,
        ) {
            Text("✓", style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Black, color = Color(0xFF002817))
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(
                "${tender.label} · ${tender.amountCents.toDollarString()}",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Bold,
            )
            tender.detail?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
        IconButton(
            onClick = onRemove,
            modifier = Modifier.semantics { contentDescription = "Remove ${tender.label} tender" },
        ) {
            Text("✕", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

// ─── Payment method grid ──────────────────────────────────────────────────────

@Composable
private fun PaymentMethodGrid(
    remainingCents: Long,
    onCardReader: () -> Unit,
    onCash: () -> Unit,
    onAch: () -> Unit,
    onParkCart: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        // Mockup PHONE 5 ships Card-reader + Tap-to-pay as separate tiles, but
        // the shop's hardware path is a single Bluetooth/USB card reader (no
        // device-to-device NFC), so the two collapse into one tile labelled
        // 'Card / Tap'. Cash takes Tap-to-pay's slot since real-world walk-in
        // sales still hand over physical bills more often than ACH.
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            PaymentTile(
                emoji = "💳",
                label = "Card / Tap",
                sublabel = "Charge ${remainingCents.toDollarString()}",
                isPrimary = true,
                onClick = onCardReader,
                modifier = Modifier.weight(1f),
            )
            PaymentTile(
                emoji = "💵",
                label = "Cash",
                sublabel = "Receive · change due",
                isPrimary = false,
                onClick = onCash,
                modifier = Modifier.weight(1f),
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            PaymentTile(
                emoji = "🏦",
                label = "ACH / check",
                sublabel = null,
                isPrimary = false,
                onClick = onAch,
                modifier = Modifier.weight(1f),
            )
            PaymentTile(
                emoji = "⏸",
                label = "Park cart",
                sublabel = "Layaway / hold",
                isPrimary = false,
                onClick = onParkCart,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun PaymentTile(
    emoji: String,
    label: String,
    sublabel: String?,
    isPrimary: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val borderColor = if (isPrimary) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline
    val borderWidth = if (isPrimary) 1.5.dp else 1.dp
    // M3 Expressive: primary 'Card / Tap' tile uses MaterialShapes.Cookie9Sided
    // so the canonical primary payment surface gets the alpha shape morph
    // (visible cut-off edges). Secondary tiles stay rounded squares.
    @OptIn(ExperimentalMaterial3ExpressiveApi::class)
    val tileShape: androidx.compose.ui.graphics.Shape = if (isPrimary)
        MaterialShapes.Cookie9Sided.toShape()
    else RoundedCornerShape(10.dp)

    Column(
        modifier = modifier
            .clip(tileShape)
            .border(borderWidth, borderColor, tileShape)
            .background(MaterialTheme.colorScheme.surface)
            .clickable(onClickLabel = label) { onClick() }
            .padding(14.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(emoji, style = MaterialTheme.typography.headlineSmall)
        Text(
            label,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = if (isPrimary) FontWeight.Bold else FontWeight.SemiBold,
            color = if (isPrimary) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
        )
        sublabel?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

// ─── Cash tender dialog — receive amount + change-due preview ───────────────

@Composable
private fun CashTenderDialog(
    remainingCents: Long,
    onApply: (receivedCents: Long) -> Unit,
    onDismiss: () -> Unit,
) {
    val remainingDollars = remainingCents / 100.0
    var input by remember { mutableStateOf("%.2f".format(remainingDollars)) }
    val received = (input.toDoubleOrNull() ?: 0.0)
    // Math.round avoids the float-truncation bug where 16.31 * 100 = 1630.999...
    // would .toLong() to 1630 and leave \$0.01 remaining on a fully-paid sale.
    val receivedCents = Math.round(received * 100)
    val changeDollars = (received - remainingDollars).coerceAtLeast(0.0)
    val canApply = receivedCents > 0L

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Cash received") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value = input,
                    onValueChange = { raw -> input = raw.filter { it.isDigit() || it == '.' } },
                    label = { Text("Amount") },
                    prefix = { Text("$") },
                    singleLine = true,
                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                        keyboardType = androidx.compose.ui.text.input.KeyboardType.Decimal,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                )
                Text(
                    "Due: ${remainingCents.toDollarString()}",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (changeDollars > 0.0) {
                    Text(
                        "Change due: ${"$%.2f".format(changeDollars)}",
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Bold,
                        color = LocalExtendedColors.current.success,
                    )
                }
            }
        },
        confirmButton = {
            TextButton(enabled = canApply, onClick = { onApply(receivedCents) }) {
                Text("Apply")
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

// ─── Bottom action bar ────────────────────────────────────────────────────────

@Composable
private fun TenderActionBar(state: PosTenderUiState, onFinalize: () -> Unit) {
    Surface(
        shadowElevation = 8.dp,
        color = MaterialTheme.colorScheme.surface,
        tonalElevation = 2.dp,
    ) {
        Column(modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp)) {
            Button(
                onClick = onFinalize,
                enabled = state.isFullyPaid && !state.isProcessing,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp)
                    .semantics {
                        contentDescription = if (state.isFullyPaid) "Charge ${state.totalCents.toDollarString()}" else "${state.remainingCents.toDollarString()} remaining — add payment to finish"
                    },
                shape = RoundedCornerShape(14.dp),
            ) {
                if (state.isProcessing) {
                    // M3 Expressive LoadingIndicator morphs between shapes for
                    // the short (~2-5s) card-reader charge wait. Usability
                    // guardrail #4: short wait → LoadingIndicator, never
                    // WavyProgressIndicator.
                    @OptIn(ExperimentalMaterial3ExpressiveApi::class)
                    LoadingIndicator(modifier = Modifier.size(28.dp), color = MaterialTheme.colorScheme.onPrimary)
                } else if (state.isFullyPaid) {
                    Text("Charge ${state.totalCents.toDollarString()}", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.ExtraBold)
                } else {
                    Text("${state.remainingCents.toDollarString()} remaining — add payment to finish", style = MaterialTheme.typography.bodyMedium)
                }
            }
        }
    }
}
