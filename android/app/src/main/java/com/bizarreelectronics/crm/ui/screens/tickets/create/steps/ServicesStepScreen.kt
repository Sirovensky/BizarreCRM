package com.bizarreelectronics.crm.ui.screens.tickets.create.steps

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.dto.RepairServiceItem
import com.bizarreelectronics.crm.ui.screens.tickets.CartPart
import com.bizarreelectronics.crm.ui.screens.tickets.RepairCartItem

/**
 * Step 3 — Services & Parts selection.
 *
 * Provides:
 * - Top-5 quick-add service tiles (most common services from the loaded list).
 * - Full service list with search.
 * - Per-service labor rate from `GET /repair-pricing/services`.
 * - Added services shown as a cart summary at the bottom.
 *
 * ### Barcode scan
 * Barcode scan entry point stub — integration requires CameraX + ML Kit
 * which involves a manifest permission and Activity-level setup.  The
 * [onBarcodeScan] callback is wired here; callers configure the scanner.
 *
 * Validation: always valid (user may advance without adding services).
 */
@Composable
fun ServicesStepScreen(
    services: List<RepairServiceItem>,
    selectedService: RepairServiceItem?,
    cartItems: List<RepairCartItem>,
    isLoadingPricing: Boolean,
    manualPrice: String,
    onServiceSelect: (RepairServiceItem) -> Unit,
    onManualPriceChange: (String) -> Unit,
    onAddToCart: () -> Unit,
    onRemoveFromCart: (String) -> Unit,
    onBarcodeScan: () -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        // ── Quick-add top-5 tiles ──────────────────────────────────────
        if (services.isNotEmpty()) {
            item(key = "quick_header") {
                Text("Quick add", style = MaterialTheme.typography.labelMedium)
            }
            item(key = "quick_tiles") {
                QuickAddTiles(
                    services = services.take(5),
                    selectedService = selectedService,
                    onSelect = onServiceSelect,
                )
            }
        }

        // ── Full service list ──────────────────────────────────────────
        item(key = "all_header") {
            Text("All services", style = MaterialTheme.typography.labelMedium)
        }
        items(services, key = { "svc_${it.id}" }) { service ->
            ServiceRow(
                service = service,
                isSelected = selectedService?.id == service.id,
                onSelect = { onServiceSelect(service) },
            )
        }

        // ── Barcode scan action ────────────────────────────────────────
        item(key = "barcode") {
            OutlinedButton(
                onClick = onBarcodeScan,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Scan barcode / part")
            }
        }

        // ── Price entry for selected service ──────────────────────────
        if (selectedService != null) {
            item(key = "price") {
                SelectedServicePriceRow(
                    service = selectedService,
                    isLoadingPricing = isLoadingPricing,
                    manualPrice = manualPrice,
                    onManualPriceChange = onManualPriceChange,
                    onAddToCart = onAddToCart,
                )
            }
        }

        // ── Cart summary ──────────────────────────────────────────────
        if (cartItems.isNotEmpty()) {
            item(key = "cart_header") {
                Text("Added (${cartItems.size})", style = MaterialTheme.typography.labelMedium)
            }
            items(cartItems, key = { "cart_${it.id}" }) { item ->
                CartItemRow(item = item, onRemove = { onRemoveFromCart(item.id) })
            }
        }
    }
}

// ── Private sub-composables ─────────────────────────────────────────────────

@Composable
private fun QuickAddTiles(
    services: List<RepairServiceItem>,
    selectedService: RepairServiceItem?,
    onSelect: (RepairServiceItem) -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        services.forEach { svc ->
            FilterChip(
                selected = selectedService?.id == svc.id,
                onClick = { onSelect(svc) },
                label = { Text(svc.name, maxLines = 1) },
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun ServiceRow(
    service: RepairServiceItem,
    isSelected: Boolean,
    onSelect: () -> Unit,
) {
    ListItem(
        headlineContent = { Text(service.name) },
        trailingContent = {
            if (isSelected) Icon(Icons.Default.Check, contentDescription = "Selected", tint = MaterialTheme.colorScheme.primary)
        },
        modifier = Modifier.clickable(onClick = onSelect),
    )
    HorizontalDivider()
}

@Composable
private fun SelectedServicePriceRow(
    service: RepairServiceItem,
    isLoadingPricing: Boolean,
    manualPrice: String,
    onManualPriceChange: (String) -> Unit,
    onAddToCart: () -> Unit,
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Column(Modifier.weight(1f)) {
                Text(service.name, style = MaterialTheme.typography.bodyMedium)
                if (isLoadingPricing) {
                    CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                } else {
                    OutlinedTextField(
                        value = manualPrice,
                        onValueChange = onManualPriceChange,
                        label = { Text("Labor price") },
                        prefix = { Text("$") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
            Button(
                onClick = onAddToCart,
                enabled = !isLoadingPricing,
            ) {
                Icon(Icons.Default.Add, contentDescription = null)
                Spacer(Modifier.width(4.dp))
                Text("Add")
            }
        }
    }
}

@Composable
private fun CartItemRow(item: RepairCartItem, onRemove: () -> Unit) {
    ListItem(
        headlineContent = { Text(item.deviceName) },
        supportingContent = { Text(item.serviceName ?: "—") },
        trailingContent = {
            TextButton(onClick = onRemove) { Text("Remove") }
        },
    )
    HorizontalDivider()
}
