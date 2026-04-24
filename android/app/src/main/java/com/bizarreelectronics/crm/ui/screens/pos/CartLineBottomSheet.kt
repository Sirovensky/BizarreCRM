package com.bizarreelectronics.crm.ui.screens.pos

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.view.HapticFeedbackConstantsCompat
import androidx.core.view.ViewCompat

/**
 * Bottom sheet shown when user taps a cart line.
 *
 * [cartDimAlpha] is applied to the underlying cart via the caller's Modifier —
 * the sheet itself just owns its own content.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CartLineBottomSheet(
    line: CartLine,
    cartDimAlpha: Float = 0.35f,
    onQtyChange: (Int) -> Unit,
    onDiscountChange: (Long) -> Unit,
    onNoteChange: (String) -> Unit,
    onRemove: () -> Unit,
    onSave: () -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)

    // Local editable state — applied to VM only on Save
    var qty by remember { mutableIntStateOf(line.qty) }
    var selectedChip by remember { mutableStateOf<DiscountChip?>(null) }
    var discountCents by remember { mutableLongStateOf(line.discountCents) }
    var note by remember { mutableStateOf(line.note ?: "") }

    val view = LocalView.current

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
                Text("Unit · ${line.unitPriceCents.toDollarString()}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
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
                    FilledIconButton(
                        onClick = {
                            if (qty > 1) {
                                qty--
                                ViewCompat.performHapticFeedback(view, HapticFeedbackConstantsCompat.CLOCK_TICK)
                                onQtyChange(qty)
                            }
                        },
                        modifier = Modifier.size(34.dp).semantics { contentDescription = "Decrease quantity" },
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
                                onQtyChange(qty)
                            }
                        },
                        modifier = Modifier.size(34.dp).semantics { contentDescription = "Increase quantity" },
                    ) {
                        Text("+", style = MaterialTheme.typography.titleMedium)
                    }
                }
            }

            // ── Unit price (read-only) ─────────────────────────────────────────
            HorizontalDivider()
            Row(
                modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Unit price", style = MaterialTheme.typography.bodyMedium)
                Text(line.unitPriceCents.toDollarString(), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Bold)
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
                        color = MaterialTheme.colorScheme.tertiary,
                    )
                }
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    DiscountChip.entries.forEach { chip ->
                        val isActive = selectedChip == chip
                        FilterChip(
                            selected = isActive,
                            onClick = {
                                selectedChip = if (isActive) null else chip
                                discountCents = when (chip) {
                                    DiscountChip.FIVE_PCT -> (line.unitPriceCents * qty * 5 / 100)
                                    DiscountChip.TEN_PCT -> (line.unitPriceCents * qty * 10 / 100)
                                    DiscountChip.FLAT, DiscountChip.CUSTOM -> 0L
                                }
                                onDiscountChange(discountCents)
                            },
                            label = {
                                Text(
                                    when (chip) {
                                        DiscountChip.FIVE_PCT -> "5%"
                                        DiscountChip.TEN_PCT -> "10%"
                                        DiscountChip.FLAT -> "$"
                                        DiscountChip.CUSTOM -> "Custom"
                                    }
                                )
                            },
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
            }

            // ── Note field ─────────────────────────────────────────────────────
            HorizontalDivider()
            Column(modifier = Modifier.padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("Note", style = MaterialTheme.typography.bodyMedium)
                OutlinedTextField(
                    value = note,
                    onValueChange = { v ->
                        if (v.length <= 1000) {
                            note = v
                            onNoteChange(v)
                        }
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
                Button(
                    onClick = onSave,
                    modifier = Modifier.weight(1.5f).semantics { contentDescription = "Save changes to ${line.name}" },
                    shape = RoundedCornerShape(12.dp),
                ) {
                    Text("Save", fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}
