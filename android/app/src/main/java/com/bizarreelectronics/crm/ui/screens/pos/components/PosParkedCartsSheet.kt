package com.bizarreelectronics.crm.ui.screens.pos.components

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.local.db.entities.ParkedCartEntity
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Bottom sheet listing all parked carts.
 *
 * Tap a cart to resume it; swipe / delete button to discard.
 * Plan §16.1 L1800.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PosParkedCartsSheet(
    parkedCarts: List<ParkedCartEntity>,
    onResume: (ParkedCartEntity) -> Unit,
    onDelete: (ParkedCartEntity) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 24.dp),
        ) {
            Text(
                "Parked Carts",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(horizontal = 24.dp, vertical = 12.dp),
            )

            if (parkedCarts.isEmpty()) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(120.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        "No parked carts",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxWidth(),
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 4.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(parkedCarts, key = { it.id }) { cart ->
                        ParkedCartRow(
                            cart = cart,
                            onResume = { onResume(cart) },
                            onDelete = { onDelete(cart) },
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ParkedCartRow(
    cart: ParkedCartEntity,
    onResume: () -> Unit,
    onDelete: () -> Unit,
) {
    val timeLabel = remember(cart.parkedAt) {
        SimpleDateFormat("h:mm a", Locale.US).format(Date(cart.parkedAt))
    }
    val subtotal = "$${String.format(Locale.US, "%.2f", cart.subtotalCents / 100.0)}"

    Card(
        onClick = onResume,
        modifier = Modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {
                contentDescription = "Parked cart: ${cart.label}, $subtotal, parked at $timeLabel. Tap to resume."
                role = Role.Button
            },
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(
                Icons.Default.ShoppingCart,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    cart.label,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    "$subtotal · $timeLabel",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            IconButton(
                onClick = onDelete,
                modifier = Modifier.semantics { contentDescription = "Delete ${cart.label}" },
            ) {
                Icon(Icons.Default.Delete, contentDescription = null)
            }
        }
    }
}
