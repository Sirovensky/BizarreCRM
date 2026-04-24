package com.bizarreelectronics.crm.ui.screens.pos

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.PhotoCamera
import androidx.compose.material3.*
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.*
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
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PosCartScreen(
    onNavigateToTender: () -> Unit,
    onBack: () -> Unit,
    onScanBarcode: () -> Unit = {},
    scannedBarcodeFlow: kotlinx.coroutines.flow.Flow<String?>? = null,
    onScannedBarcodeConsumed: () -> Unit = {},
    viewModel: PosCartViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsState()
    var showDetachConfirm by remember { mutableStateOf(false) }
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
                                modifier = Modifier.size(28.dp).clip(CircleShape).background(MaterialTheme.colorScheme.tertiary),
                                contentAlignment = Alignment.Center,
                            ) {
                                Text(c.name.take(2).uppercase(), style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onTertiary)
                            }
                            Column {
                                Text(c.name, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                                Text("${state.lines.size} items", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    } ?: Text("Cart", style = MaterialTheme.typography.titleMedium)
                },
                actions = {
                    IconButton(onClick = onScanBarcode) {
                        Icon(Icons.Outlined.PhotoCamera, contentDescription = "Scan barcode")
                    }
                    IconButton(onClick = {}) {
                        Icon(Icons.Outlined.Person, contentDescription = "Attach customer")
                    }
                },
            )
        },
        bottomBar = {
            TotalsAndTenderBar(state = state, onTender = onNavigateToTender)
        },
    ) { padding ->
        if (state.lines.isEmpty()) {
            EmptyCartContent(modifier = Modifier.padding(padding))
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentPadding = PaddingValues(bottom = 8.dp),
            ) {
                items(state.lines, key = { it.id }) { line ->
                    CartLineRow(
                        line = line,
                        onTap = { viewModel.openLineEdit(line.id) },
                        onRemove = { viewModel.removeLine(line.id) },
                    )
                }

                // Three dashed-border action slots
                item {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(14.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        DashedSlot(label = "+ Misc item", onClick = {}, modifier = Modifier.weight(1f))
                        DashedSlot(label = "+ Note", onClick = {}, modifier = Modifier.weight(1f))
                        DashedSlot(label = "+ Discount", onClick = {}, modifier = Modifier.weight(1f))
                    }
                }
            }
        }
    }

    // ── Line edit bottom sheet ───────────────────────────────────────────────
    state.editingLine?.let { line ->
        CartLineBottomSheet(
            line = line,
            cartDimAlpha = 0.35f,
            onQtyChange = { viewModel.setLineQty(line.id, it) },
            onDiscountChange = { viewModel.setLineDiscount(line.id, it) },
            onNoteChange = { viewModel.setLineNote(line.id, it) },
            onRemove = { viewModel.removeLine(line.id) },
            onSave = { viewModel.dismissLineEdit() },
            onDismiss = { viewModel.dismissLineEdit() },
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
            Column(modifier = Modifier.weight(1f)) {
                Text(line.name, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("Qty ${line.qty}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    line.note?.let { Text("· ✎ note", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                }
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    line.lineTotalCents.toDollarString(),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.primary,
                )
                if (line.discountCents > 0) {
                    Text(
                        (line.unitPriceCents * line.qty).toDollarString(),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
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
            TotalsRow("Tax", state.taxCents.toDollarString())
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
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(
            value,
            style = MaterialTheme.typography.bodySmall,
            color = if (highlight) MaterialTheme.colorScheme.tertiary else MaterialTheme.colorScheme.onSurfaceVariant,
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
        Text(label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.tertiary)
    }
}

@Composable
private fun EmptyCartContent(modifier: Modifier = Modifier) {
    Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("🛒", style = MaterialTheme.typography.displayMedium)
            Text("Scan or pick parts to start", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
