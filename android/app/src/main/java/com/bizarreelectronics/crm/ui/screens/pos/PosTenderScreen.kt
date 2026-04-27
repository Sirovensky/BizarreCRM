package com.bizarreelectronics.crm.ui.screens.pos

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.ui.screens.pos.components.PosOfflineBanner
import com.bizarreelectronics.crm.ui.screens.pos.components.PosSplitTenderDialog
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
    var showGiftCardDialog by remember { mutableStateOf(false) }
    var showInvoiceLaterConfirm by remember { mutableStateOf(false) }
    var showSplitDialog by remember { mutableStateOf(false) }
    var showDrawerManualDialog by remember { mutableStateOf(false) }
    var showOverflowMenu by remember { mutableStateOf(false) }
    // §38.6 / §38.3 — Loyalty points redemption dialog
    var showLoyaltyDialog by remember { mutableStateOf(false) }
    val snackbarHostState = remember { SnackbarHostState() }

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

    // ── Task 1: Gift card dialog ───────────────────────────────────────────────
    if (showGiftCardDialog) {
        GiftCardDialog(
            onApply = { code ->
                viewModel.applyGiftCard(code)
                showGiftCardDialog = false
            },
            onDismiss = { showGiftCardDialog = false },
        )
    }

    // ── Task 2: Invoice later confirm dialog ──────────────────────────────────
    if (showInvoiceLaterConfirm) {
        AlertDialog(
            onDismissRequest = { showInvoiceLaterConfirm = false },
            title = { Text("Invoice later") },
            text = { Text("Create invoice for ${state.totalCents.toDollarString()} total? The customer will be billed later.") },
            confirmButton = {
                TextButton(onClick = {
                    showInvoiceLaterConfirm = false
                    viewModel.invoiceLater()
                }) { Text("Create Invoice") }
            },
            dismissButton = {
                TextButton(onClick = { showInvoiceLaterConfirm = false }) { Text("Cancel") }
            },
        )
    }

    // ── Task 3: Split tender dialog ───────────────────────────────────────────
    if (showSplitDialog) {
        PosSplitTenderDialog(
            totalCents = state.totalCents,
            remainingCents = state.remainingCents,
            onSplitEvenly = { parts ->
                showSplitDialog = false
                viewModel.splitEvenly(parts)
            },
            onSplitByItem = {
                showSplitDialog = false
                // TODO POS-SPLIT-BY-ITEM-001: item-level split needs cart screen — Phase 2.
                viewModel.showMessage("Split by item — Phase 2")
            },
            onDismiss = { showSplitDialog = false },
        )
    }

    // ── Task 5: Manual drawer open — reason dialog ────────────────────────────
    if (showDrawerManualDialog) {
        ManualDrawerDialog(
            onOpen = { reason ->
                showDrawerManualDialog = false
                viewModel.openCashDrawerManual(reason)
            },
            onDismiss = { showDrawerManualDialog = false },
        )
    }

    // ── §38.6 / §38.3 — Loyalty points redemption dialog ─────────────────────
    if (showLoyaltyDialog) {
        LoyaltyPointsDialog(
            onApply = { membershipId, points ->
                viewModel.applyLoyaltyPoints(membershipId, points)
                showLoyaltyDialog = false
            },
            onDismiss = { showLoyaltyDialog = false },
        )
    }

    PosKeyboardShortcuts(
        // F1 — new sale: go back (caller pops Tender → Cart → Entry, or
        // PosCoordinator handles full reset via back-stack).
        onNewSale = onBack,
        // F2 — scan: no barcode scanner on tender screen. No-op.
        onScan = {},
        // F3 — customer search: customer is already attached at tender stage. No-op.
        onCustomerSearch = {},
        // F4 — discount: discounts must be applied in the cart, not at tender. No-op.
        onDiscount = {},
        // F5 — tender / charge: invoke finalizeSale() — same as the "Charge $X"
        // bottom-bar button. Only fires if isFullyPaid; otherwise VM no-ops.
        onTender = viewModel::finalizeSale,
        // F6 — park: available via the PaymentMethodGrid "Park cart" tile;
        // delegate to parkCart() so the key mirrors the tile.
        onPark = viewModel::parkCart,
        // F7 — print: navigate to receipt with the completed orderId for
        // reprint, but only when the sale is already completed. If not yet
        // completed, the key is a no-op to prevent a premature nav.
        onPrint = {
            state.completedOrderId?.let { onNavigateToReceipt(it) }
        },
        // F8 — refund: refund flow not yet implemented. No-op.
        onRefund = {},
        // Ctrl+F — no search field on tender screen. No-op.
        onFocusSearch = {},
    ) {
    Scaffold(
        topBar = {
            TopAppBar(
                navigationIcon = {
                    // session 2026-04-26 — a11y: back button contentDescription
                    IconButton(
                        onClick = onBack,
                        modifier = Modifier.semantics { contentDescription = "Back" },
                    ) {
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
                    Spacer(modifier = Modifier.width(4.dp))
                    // ── Task 5: Overflow menu — "Open cash drawer" ────────────
                    // session 2026-04-26 — a11y: overflow button contentDescription
                    Box {
                        IconButton(
                            onClick = { showOverflowMenu = true },
                            modifier = Modifier.semantics { contentDescription = "More options" },
                        ) {
                            Text("⋮", style = MaterialTheme.typography.titleLarge, color = MaterialTheme.colorScheme.onSurface)
                        }
                        DropdownMenu(
                            expanded = showOverflowMenu,
                            onDismissRequest = { showOverflowMenu = false },
                        ) {
                            DropdownMenuItem(
                                text = { Text("Open cash drawer") },
                                onClick = {
                                    showOverflowMenu = false
                                    showDrawerManualDialog = true
                                },
                            )
                        }
                    }
                    Spacer(modifier = Modifier.width(4.dp))
                },
            )
        },
        bottomBar = {
            TenderActionBar(state = state, onFinalize = viewModel::finalizeSale)
        },
        // session 2026-04-26 — a11y: liveRegion Assertive on tender snackbar
        // (payment errors/success must interrupt speech per goal 4)
        snackbarHost = {
            SnackbarHost(
                snackbarHostState,
                modifier = Modifier.semantics { liveRegion = LiveRegionMode.Assertive },
            )
        },
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {
        // TASK-4: offline banner — zero-height when online
        PosOfflineBanner(
            isOnline = state.isOnline,
            pendingSaleCount = state.pendingSaleCount,
        )
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(horizontal = 14.dp),
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
                // ── Task 3: "Split…" button alongside header ──────────────────
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        "+ ADD PAYMENT FOR REMAINING ${state.remainingCents.toDollarString()}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    if (state.remainingCents > 0L) {
                        TextButton(
                            onClick = { showSplitDialog = true },
                            contentPadding = PaddingValues(horizontal = 8.dp, vertical = 0.dp),
                        ) {
                            Text("Split…", style = MaterialTheme.typography.labelSmall)
                        }
                    }
                }
            }
            item {
                PaymentMethodGrid(
                    remainingCents = state.remainingCents,
                    attachedCustomerStoreCreditCents = state.attachedCustomerStoreCreditCents,
                    hasAttachedCustomer = state.hasAttachedCustomer,
                    onCardReader = { viewModel.chargeCard(state.remainingCents) },
                    onCash = { showCashDialog = true },
                    onAch = { viewModel.applyAch(state.remainingCents) },
                    // NFC / Tap-to-pay: BlockChyp SDK pending — show snackbar until wired.
                    onNfc = { viewModel.showMessage("Tap-to-pay coming soon (BlockChyp SDK pending)") },
                    onParkCart = { viewModel.parkCart() },
                    onStoreCredit = { viewModel.applyStoreCredit() },
                    onGiftCard = { showGiftCardDialog = true },
                    onInvoiceLater = { showInvoiceLaterConfirm = true },
                    onLoyaltyPoints = { showLoyaltyDialog = true },
                )
            }
        }
        } // end Column (TASK-4)
    }

    LaunchedEffect(state.errorMessage) {
        state.errorMessage?.let { msg ->
            snackbarHostState.showSnackbar(msg)
            viewModel.clearError()
        }
    }
    } // end PosKeyboardShortcuts
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
                // session 2026-04-26 — a11y: color-blind safe remaining balance;
                // merged semantics provide "Remaining: $X" so screen reader
                // doesn't rely on primary color alone
                Column(
                    horizontalAlignment = Alignment.End,
                    modifier = Modifier.semantics(mergeDescendants = true) {
                        contentDescription = "Remaining: ${state.remainingCents.toDollarString()}"
                    },
                ) {
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
        // session 2026-04-26 — a11y: clearAndSetSemantics on visual-only badge
        // so screen reader reads "Status: Paid" not just the ✓ glyph
        Box(
            modifier = Modifier
                .size(26.dp)
                .clip(CircleShape)
                .background(success)
                .clearAndSetSemantics { contentDescription = "Status: Paid" },
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
    attachedCustomerStoreCreditCents: Long,
    hasAttachedCustomer: Boolean,
    onCardReader: () -> Unit,
    onCash: () -> Unit,
    onAch: () -> Unit,
    onNfc: () -> Unit,
    onParkCart: () -> Unit,
    onStoreCredit: () -> Unit,
    onGiftCard: () -> Unit,
    onInvoiceLater: () -> Unit,
    onLoyaltyPoints: () -> Unit = {},
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        // Mockup PHONE 5: Card-reader, Tap-to-pay (NFC), Cash, ACH as separate tiles.
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
                emoji = "📱",
                label = "Tap to pay",
                sublabel = "NFC",
                isPrimary = false,
                onClick = onNfc,
                modifier = Modifier.weight(1f),
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            PaymentTile(
                emoji = "💵",
                label = "Cash",
                sublabel = "Receive · change due",
                isPrimary = false,
                onClick = onCash,
                modifier = Modifier.weight(1f),
            )
            PaymentTile(
                emoji = "🏦",
                label = "ACH / check",
                sublabel = null,
                isPrimary = false,
                onClick = onAch,
                modifier = Modifier.weight(1f),
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            PaymentTile(
                emoji = "⏸",
                label = "Park cart",
                sublabel = "Layaway / hold",
                isPrimary = false,
                onClick = onParkCart,
                modifier = Modifier.weight(1f),
            )
        }
        // ── Task 1: Gift card + Task 2: Invoice later ─────────────────────────
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            PaymentTile(
                emoji = "🎁",
                label = "Gift card",
                sublabel = "Scan or enter code",
                isPrimary = false,
                onClick = onGiftCard,
                modifier = Modifier.weight(1f),
            )
            PaymentTile(
                emoji = "🧾",
                label = "Invoice later",
                sublabel = if (hasAttachedCustomer) "Bill customer later" else "Attach customer first",
                isPrimary = false,
                enabled = hasAttachedCustomer,
                onClick = onInvoiceLater,
                modifier = Modifier.weight(1f),
            )
        }
        if (attachedCustomerStoreCreditCents > 0L) {
            PaymentTile(
                emoji = "🎁",
                label = "Store credit",
                sublabel = "${attachedCustomerStoreCreditCents.toDollarString()} available",
                isPrimary = false,
                onClick = onStoreCredit,
                modifier = Modifier.fillMaxWidth(),
            )
        }
        // §38.6 / §38.3 — Loyalty points redemption tile.
        // NOTE: server-side point deduction blocked — see PosTenderViewModel.applyLoyaltyPoints.
        if (hasAttachedCustomer) {
            PaymentTile(
                emoji = "⭐",
                label = "Loyalty points",
                sublabel = "Redeem member points",
                isPrimary = false,
                onClick = onLoyaltyPoints,
                modifier = Modifier.fillMaxWidth(),
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
    enabled: Boolean = true,
) {
    val borderColor = when {
        !enabled -> MaterialTheme.colorScheme.outlineVariant
        isPrimary -> MaterialTheme.colorScheme.primary
        else -> MaterialTheme.colorScheme.outline
    }
    val borderWidth = if (isPrimary && enabled) 1.5.dp else 1.dp
    val contentAlpha = if (enabled) 1f else 0.38f
    // 2026-04-26 audit: revert Cookie9Sided to plain 10dp rounded square
    // (mockup PHONE 5 uses uniform 10px rounded square on all tender tiles —
    // primary differs only via 1.5px border + cream label).
    val tileShape: androidx.compose.ui.graphics.Shape = RoundedCornerShape(10.dp)

    // session 2026-04-26 — a11y: Role.Button + 48dp min height on payment tile
    Column(
        modifier = modifier
            .clip(tileShape)
            .border(borderWidth, borderColor, tileShape)
            .background(MaterialTheme.colorScheme.surface)
            .defaultMinSize(minHeight = 48.dp)
            .semantics { role = Role.Button }
            .clickable(enabled = enabled, onClickLabel = label) { onClick() }
            .padding(14.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(
            emoji,
            style = MaterialTheme.typography.headlineSmall,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = contentAlpha),
        )
        Text(
            label,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = if (isPrimary) FontWeight.Bold else FontWeight.SemiBold,
            color = when {
                !enabled -> MaterialTheme.colorScheme.onSurface.copy(alpha = contentAlpha)
                isPrimary -> MaterialTheme.colorScheme.primary
                else -> MaterialTheme.colorScheme.onSurface
            },
        )
        sublabel?.let {
            Text(
                it,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = contentAlpha),
            )
        }
    }
}

// ─── Gift card dialog ─────────────────────────────────────────────────────────

@Composable
private fun GiftCardDialog(
    onApply: (code: String) -> Unit,
    onDismiss: () -> Unit,
) {
    var code by remember { mutableStateOf("") }
    val canApply = code.isNotBlank()

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Gift card") },
        text = {
            OutlinedTextField(
                value = code,
                onValueChange = { code = it.uppercase().filter { c -> c.isLetterOrDigit() || c == '-' } },
                label = { Text("Card code") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Text),
                placeholder = { Text("e.g. GC-XXXX-XXXX") },
                modifier = Modifier.fillMaxWidth(),
            )
        },
        confirmButton = {
            TextButton(enabled = canApply, onClick = { onApply(code) }) { Text("Apply") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

// ─── Manual drawer open dialog ────────────────────────────────────────────────

@Composable
private fun ManualDrawerDialog(
    onOpen: (reason: String) -> Unit,
    onDismiss: () -> Unit,
) {
    var reason by remember { mutableStateOf("") }
    val canOpen = reason.isNotBlank()

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Open cash drawer") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    "Admin role required. Enter reason for manual open.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                OutlinedTextField(
                    value = reason,
                    onValueChange = { reason = it },
                    label = { Text("Reason") },
                    singleLine = true,
                    placeholder = { Text("e.g. Count drawer, customer change") },
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            TextButton(enabled = canOpen, onClick = { onOpen(reason) }) { Text("Open") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
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
    // session 2026-04-26 — ROUND-ERROR: compute change from Long cents (not Double dollars)
    // to prevent floating-point display error (e.g. $2.4999... instead of $2.50).
    val changeCents = (receivedCents - remainingCents).coerceAtLeast(0L)
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
                if (changeCents > 0L) {
                    Text(
                        "Change due: ${changeCents.toDollarString()}",
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

// ─── Loyalty points redemption dialog ────────────────────────────────────────

/**
 * §38.6 / §38.3 — Dialog for redeeming loyalty points at POS.
 *
 * Cashier enters the customer's membership ID and the number of points to
 * redeem. Points are converted at 1 pt = $0.01 and applied as a
 * `loyalty_points` tender via [PosTenderViewModel.applyLoyaltyPoints].
 *
 * NOTE: server-side point deduction is not yet implemented — see
 * [PosTenderViewModel.applyLoyaltyPoints] for the full rationale.
 */
@Composable
private fun LoyaltyPointsDialog(
    onApply: (membershipId: Long, pointsToRedeem: Int) -> Unit,
    onDismiss: () -> Unit,
) {
    var membershipIdText by remember { mutableStateOf("") }
    var pointsText by remember { mutableStateOf("") }
    val membershipId = membershipIdText.toLongOrNull()
    val points = pointsText.toIntOrNull()?.takeIf { it > 0 }
    val dollarValue = points?.let { it * 1L }
    val canApply = membershipId != null && points != null

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Redeem loyalty points") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value = membershipIdText,
                    onValueChange = { membershipIdText = it.filter { c -> c.isDigit() } },
                    label = { Text("Membership ID") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = pointsText,
                    onValueChange = { pointsText = it.filter { c -> c.isDigit() } },
                    label = { Text("Points to redeem") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier = Modifier.fillMaxWidth(),
                )
                if (dollarValue != null) {
                    Text(
                        "Value: ${(dollarValue).toDollarString()} (1 pt = \$0.01)",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Text(
                    "Note: point balance is deducted server-side when the next sync completes.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
        confirmButton = {
            TextButton(
                enabled = canApply,
                onClick = { onApply(membershipId!!, points!!) },
            ) { Text("Apply") }
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
