package com.bizarreelectronics.crm.ui.screens.pos

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.core.view.HapticFeedbackConstantsCompat
import androidx.core.view.ViewCompat
import com.bizarreelectronics.crm.ui.theme.LocalExtendedColors

/**
 * Bottom sheet shown when user taps a cart line.
 *
 * [cartDimAlpha] is applied to the underlying cart via the caller's Modifier —
 * the sheet itself just owns its own content.
 *
 * TASK-3: [canEditPrice] gates the unit-price field (admin/manager only).
 * [onPriceChange] receives the new price in cents + override reason on Save.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CartLineBottomSheet(
    line: CartLine,
    cartDimAlpha: Float = 0.35f,
    /** TASK-3: allow price editing for admin / manager roles. */
    canEditPrice: Boolean = false,
    onQtyChange: (Int) -> Unit,
    onDiscountChange: (Long) -> Unit,
    onNoteChange: (String) -> Unit,
    /** TASK-3: called on Save when canEditPrice is true. newPriceCents + reason. */
    onPriceChange: ((newPriceCents: Long, reason: String) -> Unit)? = null,
    onRemove: () -> Unit,
    onSave: () -> Unit,
    onDismiss: () -> Unit,
) {
    // AUDIT-033: skipPartiallyExpanded = true eliminates snap jitter
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    // AUDIT-036: restore selectedChip from line.discountCents on first composition
    val initialChip: DiscountChip? = remember(line.id) {
        when {
            line.discountCents == 0L -> null
            line.discountCents == (line.unitPriceCents * line.qty * 5 / 100) -> DiscountChip.FIVE_PCT
            line.discountCents == (line.unitPriceCents * line.qty * 10 / 100) -> DiscountChip.TEN_PCT
            else -> DiscountChip.FLAT
        }
    }

    // AUDIT-007: all local state — nothing is pushed to the VM until Save
    var qty by remember(line.id) { mutableIntStateOf(line.qty) }
    var selectedChip by remember(line.id) { mutableStateOf(initialChip) }

    // AUDIT-008: extra input state for FLAT ($) and CUSTOM (%) chips
    var flatInput by remember(line.id) {
        mutableStateOf(
            if (initialChip == DiscountChip.FLAT)
                "%.2f".format(line.discountCents / 100.0)
            else ""
        )
    }
    var customPctInput by remember(line.id) { mutableStateOf("") }

    var note by remember(line.id) { mutableStateOf(line.note ?: "") }

    // TASK-3: price override state (only matters when canEditPrice == true)
    var priceInput by remember(line.id) {
        mutableStateOf("%.2f".format(line.unitPriceCents / 100.0))
    }
    var priceReason by remember(line.id) { mutableStateOf("") }
    val newPriceCents: Long = Math.round((priceInput.toDoubleOrNull() ?: 0.0) * 100)

    // AUDIT-009: discount derived from current qty + chip + custom inputs (never stale)
    val discountCents: Long by remember {
        derivedStateOf {
            val subtotal = line.unitPriceCents * qty
            when (selectedChip) {
                DiscountChip.FIVE_PCT -> subtotal * 5 / 100
                DiscountChip.TEN_PCT -> subtotal * 10 / 100
                DiscountChip.FLAT -> {
                    val dollars = flatInput.toDoubleOrNull() ?: 0.0
                    // session 2026-04-26 — ROUND-ERROR: was .toLong() (truncation); Math.round gives HALF_UP
                    Math.round(dollars * 100).coerceIn(0L, subtotal)
                }
                DiscountChip.CUSTOM -> {
                    val pct = customPctInput.toDoubleOrNull() ?: 0.0
                    // session 2026-04-26 — ROUND-ERROR: was .toLong() (truncation); Math.round gives HALF_UP
                    Math.round(subtotal * pct / 100).coerceIn(0L, subtotal)
                }
                null -> 0L
            }
        }
    }

    val view = LocalView.current
    val focusManager = LocalFocusManager.current

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        scrimColor = Color.Black.copy(alpha = cartDimAlpha),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 18.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(0.dp),
        ) {
            // ── Header ────────────────────────────────────────────────────────
            Text(line.name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            line.itemId?.let {
                val stockSuffix = if (line.stockQty != null && line.stockQty > 0) " · Stock ${line.stockQty}" else ""
                Text("Unit · ${line.unitPriceCents.toDollarString()}$stockSuffix", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Spacer(modifier = Modifier.height(8.dp))

            // ── Qty stepper ───────────────────────────────────────────────────
            HorizontalDivider()
            Row(
                modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Qty", style = MaterialTheme.typography.bodyMedium)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    // AUDIT-007: qty mutations stay local; pushed only on Save
                    // AUDIT-037: tap target bumped from 34dp to 48dp
                    FilledIconButton(
                        onClick = {
                            if (qty > 1) {
                                qty--
                                ViewCompat.performHapticFeedback(view, HapticFeedbackConstantsCompat.CLOCK_TICK)
                            }
                        },
                        modifier = Modifier.size(48.dp).semantics { contentDescription = "Decrease quantity" },
                        colors = IconButtonDefaults.filledIconButtonColors(
                            containerColor = MaterialTheme.colorScheme.surfaceVariant,
                        ),
                    ) {
                        Text("−", style = MaterialTheme.typography.titleMedium)
                    }
                    Text(
                        "$qty",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.widthIn(min = 30.dp),
                    )
                    FilledIconButton(
                        onClick = {
                            if (qty < 999) {
                                qty++
                                ViewCompat.performHapticFeedback(view, HapticFeedbackConstantsCompat.CLOCK_TICK)
                            }
                        },
                        modifier = Modifier.size(48.dp).semantics { contentDescription = "Increase quantity" },
                    ) {
                        Text("+", style = MaterialTheme.typography.titleMedium)
                    }
                }
            }

            // ── Unit price ────────────────────────────────────────────────────
            // TASK-3: editable for admin/manager; read-only for others.
            HorizontalDivider()
            if (canEditPrice) {
                Column(modifier = Modifier.padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("Unit price", style = MaterialTheme.typography.bodyMedium)
                    OutlinedTextField(
                        value = priceInput,
                        onValueChange = { raw ->
                            val filtered = raw.filter { it.isDigit() || it == '.' }
                            val dotIdx = filtered.indexOf('.')
                            priceInput = if (dotIdx >= 0)
                                filtered.substring(0, dotIdx + 1) +
                                    filtered.substring(dotIdx + 1).filter { it.isDigit() }.take(2)
                            else filtered
                        },
                        prefix = { Text("$") },
                        label = { Text("Override price") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(
                            keyboardType = KeyboardType.Decimal,
                            imeAction = ImeAction.Done,
                        ),
                        keyboardActions = KeyboardActions(onDone = { focusManager.clearFocus() }),
                        modifier = Modifier.fillMaxWidth(),
                    )
                    OutlinedTextField(
                        value = priceReason,
                        onValueChange = { priceReason = it.take(200) },
                        label = { Text("Reason (required for audit)") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            } else {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("Unit price", style = MaterialTheme.typography.bodyMedium)
                    Text(line.unitPriceCents.toDollarString(), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Bold)
                }
            }

            // ── Discount chips ─────────────────────────────────────────────────
            HorizontalDivider()
            Column(modifier = Modifier.padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("Discount", style = MaterialTheme.typography.bodyMedium)
                    Text(
                        "− ${discountCents.toDollarString()}",
                        style = MaterialTheme.typography.bodyMedium,
                        color = LocalExtendedColors.current.success,
                    )
                }
                // M3 Expressive: ButtonGroup renders segmented-connected
                // toggle buttons with single-select semantics. Tap targets
                // remain 48dp minimum (usability guardrail #3). Falls back
                // automatically on the feature flag toggle because
                // ButtonGroup requires the expressive surface.
                // AUDIT-007/008/009: chip selection is local; discount derived;
                // nothing pushed to VM until Save
                @OptIn(ExperimentalMaterial3ExpressiveApi::class)
                ButtonGroup(
                    overflowIndicator = { /* No overflow; 4 fixed items */ },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    DiscountChip.entries.forEach { chip ->
                        val isActive = selectedChip == chip
                        val label = when (chip) {
                            DiscountChip.FIVE_PCT -> "5%"
                            DiscountChip.TEN_PCT -> "10%"
                            DiscountChip.FLAT -> "$"
                            DiscountChip.CUSTOM -> "Custom"
                        }
                        toggleableItem(
                            checked = isActive,
                            onCheckedChange = { checked ->
                                selectedChip = if (checked) chip else null
                                // Reset inline inputs when deselecting
                                if (!checked) {
                                    flatInput = ""
                                    customPctInput = ""
                                }
                            },
                            label = label,
                        )
                    }
                }
                // AUDIT-008: inline input shown for FLAT ($) and CUSTOM (%)
                if (selectedChip == DiscountChip.FLAT) {
                    OutlinedTextField(
                        value = flatInput,
                        onValueChange = { v ->
                            // Allow digits and a single decimal point; max 2 dp
                            val filtered = v.filter { it.isDigit() || it == '.' }
                            val dotIdx = filtered.indexOf('.')
                            flatInput = if (dotIdx >= 0)
                                filtered.substring(0, dotIdx + 1) +
                                    filtered.substring(dotIdx + 1).filter { it.isDigit() }.take(2)
                            else filtered
                        },
                        modifier = Modifier.fillMaxWidth().padding(top = 6.dp),
                        label = { Text("Flat discount ($)") },
                        placeholder = { Text("0.00") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(
                            keyboardType = KeyboardType.Decimal,
                            imeAction = ImeAction.Done,
                        ),
                        keyboardActions = KeyboardActions(onDone = { focusManager.clearFocus() }),
                    )
                }
                if (selectedChip == DiscountChip.CUSTOM) {
                    OutlinedTextField(
                        value = customPctInput,
                        onValueChange = { v ->
                            val filtered = v.filter { it.isDigit() }
                            val num = filtered.toIntOrNull() ?: 0
                            customPctInput = if (num <= 100) filtered else "100"
                        },
                        modifier = Modifier.fillMaxWidth().padding(top = 6.dp),
                        label = { Text("Custom discount (%)") },
                        placeholder = { Text("0") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(
                            keyboardType = KeyboardType.Number,
                            imeAction = ImeAction.Done,
                        ),
                        keyboardActions = KeyboardActions(onDone = { focusManager.clearFocus() }),
                    )
                }
            }

            // ── Note field ─────────────────────────────────────────────────────
            HorizontalDivider()
            Column(modifier = Modifier.padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("Note", style = MaterialTheme.typography.bodyMedium)
                // AUDIT-007: note mutation stays local until Save
                OutlinedTextField(
                    value = note,
                    onValueChange = { v ->
                        if (v.length <= 1000) note = v
                    },
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("Optional · appears on receipt") },
                    minLines = 2,
                    maxLines = 4,
                    supportingText = { Text("${note.length} / 1000") },
                )
            }

            // ── Action buttons ─────────────────────────────────────────────────
            Spacer(modifier = Modifier.height(4.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Button(
                    onClick = onRemove,
                    modifier = Modifier.weight(1f).semantics { contentDescription = "Remove ${line.name} from cart" },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.error,
                        contentColor = Color.White,
                    ),
                    shape = RoundedCornerShape(12.dp),
                ) {
                    Text("Remove", fontWeight = FontWeight.Bold)
                }
                // AUDIT-007: Save is the single point that flushes all local state to VM
                // TASK-3: also flush price override when canEditPrice
                Button(
                    onClick = {
                        onQtyChange(qty)
                        onDiscountChange(discountCents)
                        onNoteChange(note)
                        if (canEditPrice && newPriceCents != line.unitPriceCents) {
                            onPriceChange?.invoke(newPriceCents, priceReason)
                        }
                        onSave()
                    },
                    modifier = Modifier.weight(1.5f).semantics { contentDescription = "Save changes to ${line.name}" },
                    shape = RoundedCornerShape(12.dp),
                ) {
                    Text("Save", fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}
