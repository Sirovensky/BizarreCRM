package com.bizarreelectronics.crm.ui.screens.pos

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items as gridItems
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Circle
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.PhotoCamera
import androidx.compose.material.icons.outlined.Place
import androidx.compose.material3.*
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import coil3.compose.AsyncImage
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.ui.screens.pos.components.PosOfflineBanner
import com.bizarreelectronics.crm.ui.screens.pos.components.JurisdictionTaxResult
import com.bizarreelectronics.crm.ui.theme.LocalExtendedColors

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PosCartScreen(
    onNavigateToTender: () -> Unit,
    onBack: () -> Unit,
    onScanBarcode: () -> Unit = {},
    // TASK-6: navigate to split-cart screen
    onSplitCart: () -> Unit = {},
    scannedBarcodeFlow: kotlinx.coroutines.flow.Flow<String?>? = null,
    onScannedBarcodeConsumed: () -> Unit = {},
    viewModel: PosCartViewModel = hiltViewModel(),
    // TASK-3: injected by NavGraph caller so screen doesn't need Hilt directly
    authPreferences: AuthPreferences? = null,
) {
    val state by viewModel.uiState.collectAsState()
    // TASK-3: admin / manager can override unit prices
    val canEditPrice = remember(authPreferences) {
        val role = authPreferences?.userRole?.lowercase()
        role == "admin" || role == "manager"
    }
    var showDetachConfirm by remember { mutableStateOf(false) }
    var showMiscDialog by remember { mutableStateOf(false) }
    var showDiscountDialog by remember { mutableStateOf(false) }
    var showNoteDialog by remember { mutableStateOf(false) }
    var showOverflowMenu by remember { mutableStateOf(false) }
    var showParkedCarts by remember { mutableStateOf(false) }
    var showTipDialog by remember { mutableStateOf(false) }
    // Mockup PHONE 3 path tabs: Catalog | Cart · N · $X — selected tab
    // index 1 by default since cashier reaches this screen with intent to
    // tender. Catalog tab populates from quick-add (Today's Top-5).
    var selectedTab by rememberSaveable { mutableIntStateOf(1) }
    val snackbarHostState = remember { SnackbarHostState() }

    // Consume scan-result handoff from the scanner screen. AppNavGraph
    // writes the scanned code onto this entry's savedStateHandle and pops
    // back; we read it here, push it through the VM, and clear it so a
    // recompose-only event doesn't re-add the same line.
    val scannedBarcode by (scannedBarcodeFlow ?: kotlinx.coroutines.flow.flowOf(null as String?))
        .collectAsState(initial = null)
    LaunchedEffect(scannedBarcode) {
        scannedBarcode?.takeIf { it.isNotBlank() }?.let {
            viewModel.scanBarcode(it)
            onScannedBarcodeConsumed()
        }
    }
    // Flash the scan result / error as a snackbar + clear the VM state.
    LaunchedEffect(state.scanMessage) {
        state.scanMessage?.let { msg ->
            snackbarHostState.showSnackbar(msg)
            viewModel.clearScanMessage()
        }
    }

    PosKeyboardShortcuts(
        // F1 — new sale: go back to PosEntry (caller pops the cart screen,
        // which resets the VM via PosCoordinator.startNewSale).
        onNewSale = onBack,
        // F2 — scan: delegate to the same camera-scanner callback used by the
        // top-bar scan icon.
        onScan = onScanBarcode,
        // F3 — customer search: no standalone search field on cart screen;
        // customer is already attached. No-op.
        onCustomerSearch = {},
        // F4 — discount: programmatically open the cart-discount dialog.
        onDiscount = { showDiscountDialog = true },
        // F5 — tender: navigate to PosTender (same as the Tender button CTA).
        onTender = onNavigateToTender,
        // F6 — park: POS-PARK-001 stub — mirrors the overflow-menu "Park cart"
        // item which is also a no-op pending implementation.
        onPark = {},
        // F7 — print: no receipt exists at cart stage. No-op.
        onPrint = {},
        // F8 — refund: refund flow not yet implemented. No-op.
        onRefund = {},
        // Ctrl+F — catalog tab has tile grid, not a TextField. No-op.
        onFocusSearch = {},
    ) {
    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Text("‹", style = MaterialTheme.typography.headlineMedium, color = MaterialTheme.colorScheme.onSurface)
                    }
                },
                title = {
                    state.customer?.let { c ->
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            modifier = Modifier.clickable(onClickLabel = "Detach customer") { showDetachConfirm = true },
                        ) {
                            Box(
                                modifier = Modifier.size(28.dp).clip(CircleShape).background(MaterialTheme.colorScheme.secondary),
                                contentAlignment = Alignment.Center,
                            ) {
                                Text(
                                    c.name.split(" ").take(2).joinToString("") { it.take(1) }.uppercase(),
                                    style = MaterialTheme.typography.labelSmall,
                                    fontWeight = FontWeight.Bold,
                                    color = MaterialTheme.colorScheme.onSecondary,
                                )
                            }
                            Column {
                                Text(c.name, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                                // Mockup phone 3 subtitle pattern: show the linked-ticket-draft
                                // state when set; otherwise fall back to an items count.
                                val subtitle = when {
                                    state.linkedTicketId != null -> "Ticket draft #${state.linkedTicketId}"
                                    state.lines.isEmpty() -> "Empty cart"
                                    else -> "${state.lines.size} items"
                                }
                                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    } ?: Text("Cart", style = MaterialTheme.typography.titleMedium)
                },
                actions = {
                    // ── Location chip ────────────────────────────────────────
                    AssistChip(
                        onClick = { /* TODO: location picker */ },
                        label = {
                            Text(state.locationName, style = MaterialTheme.typography.labelSmall)
                        },
                        leadingIcon = {
                            Icon(
                                Icons.Outlined.Place,
                                contentDescription = null,
                                modifier = Modifier.size(14.dp),
                            )
                        },
                        modifier = Modifier.height(28.dp),
                    )
                    Spacer(modifier = Modifier.width(2.dp))
                    // ── Shift status chip ────────────────────────────────────
                    AssistChip(
                        onClick = { /* TODO: clock-in/out */ },
                        label = {
                            Text(
                                if (state.shiftActive) "On shift" else "Off shift",
                                style = MaterialTheme.typography.labelSmall,
                            )
                        },
                        leadingIcon = {
                            Icon(
                                Icons.Filled.Circle,
                                contentDescription = null,
                                modifier = Modifier.size(8.dp),
                                tint = if (state.shiftActive) LocalExtendedColors.current.success
                                       else MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        },
                        modifier = Modifier.height(28.dp),
                    )
                    Spacer(modifier = Modifier.width(2.dp))
                    // ── Parked carts chip (only when count > 0) ──────────────
                    if (state.parkedCartCount > 0) {
                        AssistChip(
                            onClick = { showParkedCarts = true },
                            label = {
                                Text(
                                    "${state.parkedCartCount} parked",
                                    style = MaterialTheme.typography.labelSmall,
                                )
                            },
                            modifier = Modifier.height(28.dp),
                        )
                        Spacer(modifier = Modifier.width(2.dp))
                    }
                    IconButton(onClick = onScanBarcode) {
                        Icon(Icons.Outlined.PhotoCamera, contentDescription = "Scan barcode")
                    }
                    Box {
                        IconButton(onClick = { showOverflowMenu = true }) {
                            Icon(Icons.Outlined.MoreVert, contentDescription = "More options")
                        }
                        DropdownMenu(
                            expanded = showOverflowMenu,
                            onDismissRequest = { showOverflowMenu = false },
                        ) {
                            // "Detach customer" only when a customer is attached
                            if (state.customer != null) {
                                DropdownMenuItem(
                                    text = { Text("Detach customer") },
                                    onClick = {
                                        showOverflowMenu = false
                                        showDetachConfirm = true
                                    },
                                )
                            }
                            DropdownMenuItem(
                                text = { Text("Apply discount") },
                                onClick = {
                                    showOverflowMenu = false
                                    showDiscountDialog = true
                                },
                            )
                            DropdownMenuItem(
                                text = { Text("Add note") },
                                onClick = {
                                    showOverflowMenu = false
                                    showNoteDialog = true
                                },
                            )
                            DropdownMenuItem(
                                text = { Text("Park cart") },
                                onClick = {
                                    showOverflowMenu = false
                                    // TODO: POS-PARK-001 — park cart implementation
                                },
                            )
                            DropdownMenuItem(
                                text = { Text("Split cart") },
                                onClick = {
                                    showOverflowMenu = false
                                    onSplitCart()
                                },
                            )
                        }
                    }
                },
            )
        },
        bottomBar = {
            TotalsAndTenderBar(state = state, onTender = onNavigateToTender)
        },
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {
            // TASK-4: offline banner — zero-height when online
            PosOfflineBanner(
                isOnline = state.isOnline,
                pendingSaleCount = state.pendingSaleCount,
            )
            // Mockup PHONE 3 path tabs: 'Catalog' + 'Cart · N · $X' active.
            CartPathTabs(
                selectedIndex = selectedTab,
                cartLineCount = state.lines.size,
                cartTotalCents = state.subtotalCents,
                onSelect = { selectedTab = it },
            )

            if (selectedTab == 0) {
                // Catalog tab — quick-add tile grid
                CatalogTab(
                    items = state.catalog,
                    onTileTap = { viewModel.addQuickAddItem(it) },
                )
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(bottom = 8.dp),
                ) {
                    // Cart line rows (or empty emoji)
                    if (state.lines.isEmpty()) {
                        item {
                            Column(
                                modifier = Modifier.fillMaxWidth().padding(vertical = 48.dp),
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                Text("🛒", style = MaterialTheme.typography.displayMedium)
                                Text(
                                    "Scan or pick parts to start",
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                TextButton(onClick = { selectedTab = 0 }) {
                                    Text("Browse catalog →")
                                }
                            }
                        }
                    } else {
                        items(state.lines, key = { it.id }) { line ->
                            CartLineRow(
                                line = line,
                                onTap = { viewModel.openLineEdit(line.id) },
                                onRemove = { viewModel.removeLine(line.id) },
                            )
                        }
                    }

                    // Three dashed-border action slots — always visible so cashier can
                    // add a misc line / attach a note / apply a cart discount from an
                    // otherwise empty cart too (matches mockup PHONE 3 layout).
                    item {
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(14.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            DashedSlot(label = "+ Misc item", onClick = { showMiscDialog = true }, modifier = Modifier.weight(1f))
                            DashedSlot(label = "+ Note", onClick = { showNoteDialog = true }, modifier = Modifier.weight(1f))
                            DashedSlot(label = "+ Discount", onClick = { showDiscountDialog = true }, modifier = Modifier.weight(1f))
                            // TASK-1: tip slot
                            DashedSlot(
                                label = if (state.tipCents > 0) "Tip ${state.tipCents.toDollarString()}" else "+ Tip",
                                onClick = { showTipDialog = true },
                                modifier = Modifier.weight(1f),
                            )
                        }
                    }
                }
            }
        }

        // ── Line edit bottom sheet — INSIDE Scaffold content lambda so the
        // scrim covers the topBar correctly (POS-AUDIT-034).
        state.editingLine?.let { line ->
            CartLineBottomSheet(
                line = line,
                cartDimAlpha = 0.35f,
                canEditPrice = canEditPrice,
                onQtyChange = { viewModel.setLineQty(line.id, it) },
                onDiscountChange = { viewModel.setLineDiscount(line.id, it) },
                onNoteChange = { viewModel.setLineNote(line.id, it) },
                onPriceChange = { newPrice, reason ->
                    viewModel.setLineUnitPrice(line.id, newPrice, reason)
                },
                onRemove = { viewModel.removeLine(line.id) },
                onSave = { viewModel.dismissLineEdit() },
                onDismiss = { viewModel.dismissLineEdit() },
            )
        }
    }

    // TASK-1: tip dialog
    if (showTipDialog) {
        TipDialog(
            subtotalCents = state.subtotalCents,
            currentTipCents = state.tipCents,
            onApply = { cents ->
                viewModel.setTip(cents)
                showTipDialog = false
            },
            onDismiss = { showTipDialog = false },
        )
    }

    if (showMiscDialog) {
        MiscItemDialog(
            onAdd = { name, priceCents ->
                viewModel.addMiscItem(name, priceCents)
                showMiscDialog = false
            },
            onDismiss = { showMiscDialog = false },
        )
    }

    if (showNoteDialog) {
        CartNoteDialog(
            currentNote = state.cartNote,
            onApply = { text ->
                viewModel.setCartNote(text)
                showNoteDialog = false
            },
            onDismiss = { showNoteDialog = false },
        )
    }

    if (showDiscountDialog) {
        CartDiscountDialog(
            currentCents = state.discountCents,
            subtotalCents = state.subtotalCents,
            onApply = { cents ->
                viewModel.setCartDiscount(cents)
                showDiscountDialog = false
            },
            onDismiss = { showDiscountDialog = false },
        )
    }

    // ── Detach customer confirmation ─────────────────────────────────────────
    if (showDetachConfirm) {
        AlertDialog(
            onDismissRequest = { showDetachConfirm = false },
            title = { Text("Detach customer?") },
            text = { Text("The cart items will be kept. This customer will be removed from the sale.") },
            confirmButton = {
                TextButton(onClick = { viewModel.detachCustomer(); showDetachConfirm = false }) {
                    Text("Detach", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showDetachConfirm = false }) { Text("Cancel") }
            },
        )
    }
    // ── Parked carts sheet ───────────────────────────────────────────────────
    if (showParkedCarts) {
        PosParkedCartsSheet(
            onDismiss = { showParkedCarts = false },
            onRestoreCart = { cartId ->
                viewModel.restoreParkedCart(cartId)
                showParkedCarts = false
            },
        )
    }
    } // end PosKeyboardShortcuts
}

// ─── Cart line row with swipe-to-remove ──────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CartLineRow(line: CartLine, onTap: () -> Unit, onRemove: () -> Unit) {
    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            if (value == SwipeToDismissBoxValue.EndToStart) { onRemove(); true } else false
        }
    )

    SwipeToDismissBox(
        state = dismissState,
        backgroundContent = {
            Box(
                modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.error).padding(end = 16.dp),
                contentAlignment = Alignment.CenterEnd,
            ) {
                Icon(Icons.Outlined.Delete, contentDescription = "Remove line", tint = Color.White)
            }
        },
        enableDismissFromStartToEnd = false,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.surface)
                .clickable(onClickLabel = "Edit ${line.name}") { onTap() }
                .padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            // Mockup phone 3 pattern: 40dp rounded surface-2 square with a
            // type-based emoji glyph. Inventory = 🔧, service = ⚙️, custom = 🔌.
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .background(MaterialTheme.colorScheme.surfaceVariant),
                contentAlignment = Alignment.Center,
            ) {
                val glyph = when (line.type) {
                    "service" -> "⚙"
                    "custom" -> "🔌"
                    else -> "🔧"
                }
                Text(glyph, style = MaterialTheme.typography.titleMedium)
            }
            Column(modifier = Modifier.weight(1f)) {
                Text(line.name, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                val subtitle = buildString {
                    line.sku?.takeIf { it.isNotBlank() }?.let { append("SKU ").append(it).append(" · ") }
                    append("Qty ").append(line.qty)
                    line.note?.let { append(" · ✎ note") }
                }
                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    line.lineTotalCents.toDollarString(),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.primary,
                )
                val original = line.originalUnitPriceCents
                if (original != null && original > line.unitPriceCents) {
                    Text(
                        (original * line.qty).toDollarString(),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textDecoration = androidx.compose.ui.text.style.TextDecoration.LineThrough,
                    )
                } else if (line.discountCents > 0) {
                    Text(
                        (line.unitPriceCents * line.qty).toDollarString(),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textDecoration = androidx.compose.ui.text.style.TextDecoration.LineThrough,
                    )
                }
            }
        }
    }
    HorizontalDivider()
}

// ─── Totals bar + Tender CTA ─────────────────────────────────────────────────

@Composable
private fun TotalsAndTenderBar(state: PosCartUiState, onTender: () -> Unit) {
    Surface(
        shadowElevation = 8.dp,
        color = MaterialTheme.colorScheme.surface,
        tonalElevation = 2.dp,
    ) {
        Column(modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp)) {
            TotalsRow("Subtotal", state.subtotalCents.toDollarString())
            if (state.discountCents > 0) TotalsRow("Discount", "− ${state.discountCents.toDollarString()}", highlight = true)
            // TASK-5: multi-jurisdiction tax breakdown. When breakdown has
            // > 1 jurisdiction render one row each; else fallback to single
            // 'Tax · X%' line matching mockup PHONE 3.
            val breakdown = state.taxBreakdown
            if (breakdown != null && breakdown.jurisdictions.size > 1) {
                breakdown.jurisdictions.forEach { j ->
                    TotalsRow(j.name, j.taxCents.toDollarString())
                }
            } else {
                val taxLabel = if (state.taxRate > 0.0) {
                    "Tax · ${"%.2f".format(state.taxRate * 100).trimEnd('0').trimEnd('.')}%"
                } else "Tax"
                TotalsRow(taxLabel, state.taxCents.toDollarString())
            }
            // TASK-1: tip line — only when tip is set
            if (state.tipCents > 0L) {
                TotalsRow("Tip", state.tipCents.toDollarString())
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text("Total", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.ExtraBold)
                Text(state.totalCents.toDollarString(), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.ExtraBold)
            }
            Spacer(modifier = Modifier.height(10.dp))
            Button(
                onClick = onTender,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp)
                    .semantics { contentDescription = "Tender ${state.totalCents.toDollarString()}" },
                enabled = state.lines.isNotEmpty(),
                shape = RoundedCornerShape(14.dp),
            ) {
                Text("Tender · ${state.totalCents.toDollarString()}", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.ExtraBold)
            }
        }
    }
}

@Composable
private fun TotalsRow(label: String, value: String, highlight: Boolean = false) {
    val successGreen = LocalExtendedColors.current.success
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            label,
            style = MaterialTheme.typography.bodySmall,
            color = if (highlight) successGreen else MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            value,
            style = MaterialTheme.typography.bodySmall,
            color = if (highlight) successGreen else MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun DashedSlot(label: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    // Mockup phone 3: these three action slots (+Misc / +Note / +Discount)
    // render with a dashed rectangle border. Compose stdlib has no
    // Modifier.dashedBorder so we draw it inline via drawBehind + Stroke +
    // PathEffect — same recipe as GhostWalkInTile in PosEntryScreen.
    val outlineColor = MaterialTheme.colorScheme.outline
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(10.dp))
            .clickable(onClickLabel = label) { onClick() }
            .drawBehind {
                val strokeWidth = 1.dp.toPx()
                val dash = PathEffect.dashPathEffect(floatArrayOf(10f, 6f), 0f)
                drawRoundRect(
                    color = outlineColor,
                    size = Size(size.width - strokeWidth, size.height - strokeWidth),
                    topLeft = Offset(strokeWidth / 2, strokeWidth / 2),
                    cornerRadius = CornerRadius(10.dp.toPx() - strokeWidth / 2),
                    style = Stroke(width = strokeWidth, pathEffect = dash),
                )
            }
            .padding(vertical = 10.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, style = MaterialTheme.typography.bodySmall, color = LocalExtendedColors.current.info)
    }
}

// ─── Path tabs (Catalog | Cart · N · $X) ────────────────────────────────────

@Composable
private fun CartPathTabs(
    selectedIndex: Int,
    cartLineCount: Int,
    cartTotalCents: Long,
    onSelect: (Int) -> Unit,
) {
    // Mockup PHONE 3 .tabs row: surface bg + outline border-bottom; active
    // tab gains primary border-bottom + bold onSurface text. Inactive tabs
    // are muted.
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surface),
    ) {
        val primaryColor = MaterialTheme.colorScheme.primary
        val outlineVariantColor = MaterialTheme.colorScheme.outlineVariant
        listOf(
            "Catalog" to 0,
            "Cart · $cartLineCount · ${cartTotalCents.toDollarString()}" to 1,
        ).forEach { (label, idx) ->
            val isActive = idx == selectedIndex
            Box(
                modifier = Modifier
                    .weight(1f)
                    .clickable(onClickLabel = label) { onSelect(idx) }
                    .padding(vertical = 12.dp)
                    .drawBehind {
                        if (isActive) {
                            // 2dp primary underline matches mockup .tab.active
                            val w = 2.dp.toPx()
                            drawRect(
                                color = primaryColor,
                                topLeft = Offset(0f, size.height - w),
                                size = Size(size.width, w),
                            )
                        } else {
                            // 1px outlineVariant border-bottom on inactive tabs to
                            // mirror the mockup's full-width row separator.
                            val w = 1.dp.toPx()
                            drawRect(
                                color = outlineVariantColor,
                                topLeft = Offset(0f, size.height - w),
                                size = Size(size.width, w),
                            )
                        }
                    },
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    label,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = if (isActive) FontWeight.Bold else FontWeight.Normal,
                    color = if (isActive) MaterialTheme.colorScheme.onSurface
                            else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

// ─── Catalog tab — quick-add tile grid ───────────────────────────────────────

// MVP category list — hardcoded until a /pos-enrich/categories endpoint exists.
private val CATALOG_CATEGORIES = listOf("Parts", "Services", "Accessories", "Refurbished")

@Composable
private fun CatalogTab(
    items: List<com.bizarreelectronics.crm.data.remote.api.QuickAddItem>,
    onTileTap: (com.bizarreelectronics.crm.data.remote.api.QuickAddItem) -> Unit,
) {
    // Category filter state — null means "All"
    var selectedCategory by remember { mutableStateOf<String?>(null) }

    if (items.isEmpty()) {
        Box(
            modifier = Modifier.fillMaxSize().padding(24.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                "No catalog items configured yet.\nAdd inventory in Settings → Inventory.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
        }
        return
    }

    Column(modifier = Modifier.fillMaxSize()) {
        // ── Category filter chips ─────────────────────────────────────────
        LazyRow(
            modifier = Modifier.fillMaxWidth(),
            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            // "All" chip
            item {
                FilterChip(
                    selected = selectedCategory == null,
                    onClick = { selectedCategory = null },
                    label = { Text("All") },
                )
            }
            items(CATALOG_CATEGORIES, key = { it }) { category ->
                FilterChip(
                    selected = selectedCategory == category,
                    onClick = {
                        selectedCategory = if (selectedCategory == category) null else category
                    },
                    label = { Text(category) },
                )
            }
        }

        // ── Filtered tile grid ────────────────────────────────────────────
        val filtered = if (selectedCategory == null) items
                       else items.filter { it.category == selectedCategory }

        if (filtered.isEmpty()) {
            Box(
                modifier = Modifier.fillMaxSize().padding(24.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    "No items in this category.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        } else {
            // GridCells.Adaptive(140.dp): phones (~360dp) → 2 cols,
            // tablets (~800dp) → 4+ cols automatically.
            LazyVerticalGrid(
                columns = GridCells.Adaptive(minSize = 140.dp),
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(start = 12.dp, end = 12.dp, top = 0.dp, bottom = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                gridItems(filtered, key = { it.id }) { item ->
                    CatalogTile(item = item, onClick = { onTileTap(item) })
                }
            }
        }
    }
}

@Composable
private fun CatalogTile(
    item: com.bizarreelectronics.crm.data.remote.api.QuickAddItem,
    onClick: () -> Unit,
) {
    // Tile is 120dp tall: top-half photo (or emoji fallback), bottom-half text.
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .height(120.dp)
            .clip(RoundedCornerShape(12.dp))
            .border(1.dp, MaterialTheme.colorScheme.outline, RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surface)
            .clickable(onClickLabel = "Add ${item.name}") { onClick() },
        verticalArrangement = Arrangement.Top,
    ) {
        if (item.photoUrl != null) {
            // Photo fills top half of the tile (1:1 crop).
            AsyncImage(
                model = item.photoUrl,
                contentDescription = item.name,
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(60.dp)
                    .clip(RoundedCornerShape(topStart = 12.dp, topEnd = 12.dp)),
            )
        } else {
            // Fallback: emoji/icon area in surfaceVariant
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(60.dp)
                    .background(
                        MaterialTheme.colorScheme.surfaceVariant,
                        RoundedCornerShape(topStart = 12.dp, topEnd = 12.dp),
                    ),
                contentAlignment = Alignment.Center,
            ) {
                val glyph = when (item.category?.lowercase()) {
                    "services" -> "⚙"
                    "accessories" -> "🎧"
                    "refurbished" -> "♻"
                    else -> "🔧"
                }
                Text(glyph, style = MaterialTheme.typography.titleLarge)
            }
        }
        // Bottom half: name + price
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 8.dp, vertical = 4.dp),
            verticalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(
                item.name,
                style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
            )
            Text(
                item.priceCents.toDollarString(),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.primary,
            )
        }
    }
}

// ─── Misc item dialog — name + price ─────────────────────────────────────────

@Composable
private fun MiscItemDialog(onAdd: (String, Long) -> Unit, onDismiss: () -> Unit) {
    var name by remember { mutableStateOf("") }
    var priceInput by remember { mutableStateOf("") }
    // Math.round avoids float-truncation (e.g. 16.31 → 1630.999... → 1630).
    val priceCents = Math.round((priceInput.toDoubleOrNull() ?: 0.0) * 100)
    val canAdd = name.isNotBlank() && priceCents > 0L

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Add misc item") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it.take(120) },
                    label = { Text("Name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = priceInput,
                    onValueChange = { raw -> priceInput = raw.filter { it.isDigit() || it == '.' } },
                    label = { Text("Price") },
                    prefix = { Text("$") },
                    singleLine = true,
                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                        keyboardType = androidx.compose.ui.text.input.KeyboardType.Decimal,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            TextButton(onClick = { onAdd(name.trim(), priceCents) }, enabled = canAdd) {
                Text("Add")
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

// ─── Cart-wide discount dialog ───────────────────────────────────────────────

/**
 * AUDIT-012 / AUDIT-035: added [subtotalCents] cap so a cashier cannot apply
 * a discount that exceeds the cart subtotal, which would produce a negative
 * total.  Apply button is disabled and an inline error is shown when the
 * entered amount is out of range.
 */
@Composable
private fun CartDiscountDialog(
    currentCents: Long,
    subtotalCents: Long,
    onApply: (Long) -> Unit,
    onDismiss: () -> Unit,
) {
    var input by remember(currentCents) {
        mutableStateOf(if (currentCents > 0) "%.2f".format(currentCents / 100.0) else "")
    }
    val cents = Math.round((input.toDoubleOrNull() ?: 0.0) * 100)
    val overflow = cents > subtotalCents
    val canApply = cents > 0L && !overflow

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Cart discount") },
        text = {
            OutlinedTextField(
                value = input,
                onValueChange = { raw -> input = raw.filter { it.isDigit() || it == '.' } },
                label = { Text("Amount") },
                prefix = { Text("$") },
                singleLine = true,
                isError = overflow,
                supportingText = if (overflow) {
                    { Text("Discount cannot exceed subtotal ${subtotalCents.toDollarString()}") }
                } else null,
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                    keyboardType = androidx.compose.ui.text.input.KeyboardType.Decimal,
                ),
                modifier = Modifier.fillMaxWidth(),
            )
        },
        confirmButton = {
            TextButton(onClick = { onApply(cents) }, enabled = canApply) { Text("Apply") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

// ─── Tip dialog ──────────────────────────────────────────────────────────────

/**
 * TASK-1: Tip prompt with percent presets + flat-amount custom field.
 *
 * Percent presets (15 / 18 / 20) are hardcoded for now.
 * TODO: read default tip presets from AppPreferences once tenant tip config
 * is delivered from the server (TenantSettingsRepository).
 *
 * @param subtotalCents  Cart subtotal used to compute percent-based tips.
 * @param currentTipCents  Currently applied tip (pre-fills custom field).
 */
@Composable
private fun TipDialog(
    subtotalCents: Long,
    currentTipCents: Long,
    onApply: (Long) -> Unit,
    onDismiss: () -> Unit,
) {
    // Tip presets in percent — TODO: read from AppPreferences / tenant config
    val tipPresets = listOf(15, 18, 20)
    var selectedPct by remember { mutableStateOf<Int?>(null) }
    var customInput by remember {
        mutableStateOf(
            if (currentTipCents > 0) "%.2f".format(currentTipCents / 100.0) else ""
        )
    }

    val tipCents: Long = when {
        selectedPct != null -> subtotalCents * (selectedPct ?: 0) / 100
        else -> Math.round((customInput.toDoubleOrNull() ?: 0.0) * 100)
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Add tip") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                // Percent preset radio group
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    tipPresets.forEach { pct ->
                        FilterChip(
                            selected = selectedPct == pct,
                            onClick = {
                                selectedPct = if (selectedPct == pct) null else pct
                                if (selectedPct != null) customInput = ""
                            },
                            label = { Text("$pct%") },
                        )
                    }
                    // Custom % chip
                    FilterChip(
                        selected = selectedPct == null && customInput.isNotBlank(),
                        onClick = { selectedPct = null },
                        label = { Text("Custom") },
                    )
                }
                if (selectedPct != null) {
                    Text(
                        "Tip amount: ${tipCents.toDollarString()}",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                } else {
                    OutlinedTextField(
                        value = customInput,
                        onValueChange = { raw ->
                            val filtered = raw.filter { it.isDigit() || it == '.' }
                            val dotIdx = filtered.indexOf('.')
                            customInput = if (dotIdx >= 0)
                                filtered.substring(0, dotIdx + 1) +
                                    filtered.substring(dotIdx + 1).filter { it.isDigit() }.take(2)
                            else filtered
                        },
                        label = { Text("Tip amount") },
                        prefix = { Text("$") },
                        singleLine = true,
                        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                            keyboardType = androidx.compose.ui.text.input.KeyboardType.Decimal,
                        ),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onApply(tipCents) },
                enabled = tipCents >= 0L,
            ) {
                Text(if (tipCents == 0L) "No tip" else "Apply ${tipCents.toDollarString()}")
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

// ─── Cart-level note dialog ──────────────────────────────────────────────────

@Composable
private fun CartNoteDialog(
    currentNote: String?,
    onApply: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    var input by remember(currentNote) { mutableStateOf(currentNote.orEmpty()) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Cart note") },
        text = {
            OutlinedTextField(
                value = input,
                onValueChange = { input = it.take(1000) },
                label = { Text("Note") },
                placeholder = { Text("e.g. customer requested gift wrap") },
                minLines = 3,
                maxLines = 6,
                modifier = Modifier.fillMaxWidth(),
            )
        },
        confirmButton = {
            TextButton(onClick = { onApply(input.trim()) }) { Text("Apply") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}
