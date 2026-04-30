package com.bizarreelectronics.crm.ui.screens.pos

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.local.db.entities.ParkedCartEntity

/**
 * Bottom sheet that lists parked carts.
 *
 * Tapping a row restores the cart into the active session via
 * [PosCartViewModel.restoreParkedCart].
 *
 * TODO: POS-PARK-002 — full restore: deserialize cartJson → coordinator session.
 *       Until then, restoring deletes the parked row so the chip count decrements.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PosParkedCartsSheet(
    onDismiss: () -> Unit,
    onRestoreCart: (cartId: String) -> Unit,
    viewModel: PosCartViewModel = hiltViewModel(),
) {
    val parkedCarts by viewModel.parkedCarts.collectAsState(initial = emptyList())

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        shape = RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(bottom = 24.dp),
        ) {
            Text(
                "Parked carts",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(bottom = 12.dp),
            )

            if (parkedCarts.isEmpty()) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 32.dp),
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
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                    modifier = Modifier.heightIn(max = 400.dp),
                ) {
                    items(parkedCarts, key = { it.id }) { cart ->
                        ParkedCartRow(
                            cart = cart,
                            onRestore = { onRestoreCart(cart.id) },
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
    onRestore: () -> Unit,
) {
    // session 2026-04-26 — a11y: 48dp minimum touch target on parked-cart row
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 48.dp)
            .clickable(onClickLabel = "Restore ${cart.label}") { onRestore() }
            .padding(vertical = 12.dp, horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                cart.label,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
            )
            val subtitle = buildString {
                cart.customerName?.let { append(it).append(" · ") }
                append(cart.subtotalCents.toDollarString())
            }
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        TextButton(onClick = onRestore) {
            Text("Restore")
        }
    }
    HorizontalDivider()
}
