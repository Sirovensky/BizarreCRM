package com.bizarreelectronics.crm.ui.screens.inventory.components

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AssignmentReturn
import androidx.compose.material.icons.filled.Business
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.components.shared.BrandCard

/**
 * Supplier detail panel for an inventory item (L1074).
 *
 * Shows the supplier name, contact info (if available from the extended detail),
 * last-known cost, a "Place PO" stub button, and (§61.5) a "Log Return" button
 * that navigates to the RMA create flow.
 *
 * @param supplierName  Display name of the supplier, or null if unset.
 * @param supplierId    Server ID of the supplier for deep-link / PO stub.
 * @param lastCostLabel Pre-formatted last cost string, e.g. "$12.50".
 * @param onPlacePo     Invoked when the "Place PO" button is tapped.
 * @param onLogReturn   Invoked when the "Log Return" button is tapped; navigates to RMA create.
 *                      Null hides the button (backward-compatible default).
 * @param modifier      Applied to the root [BrandCard].
 */
@Composable
fun InventorySupplierPanel(
    supplierName: String?,
    supplierId: Long?,
    lastCostLabel: String,
    onPlacePo: () -> Unit,
    onLogReturn: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    BrandCard(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    Icons.Default.Business,
                    contentDescription = null,
                    modifier = Modifier.size(18.dp),
                    tint = MaterialTheme.colorScheme.primary,
                )
                Text("Supplier", style = MaterialTheme.typography.titleSmall)
            }

            if (supplierName.isNullOrBlank()) {
                Text(
                    "No supplier linked",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                Text(
                    supplierName,
                    style = MaterialTheme.typography.bodyMedium,
                )

                if (lastCostLabel.isNotBlank()) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(
                            "Last cost:",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            lastCostLabel,
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                }

                Spacer(modifier = Modifier.height(4.dp))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    OutlinedButton(
                        onClick = onPlacePo,
                        modifier = Modifier.weight(1f),
                    ) {
                        Icon(
                            Icons.Default.ShoppingCart,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp),
                        )
                        Spacer(modifier = Modifier.width(4.dp))
                        Text("Place PO")
                    }

                    if (onLogReturn != null) {
                        OutlinedButton(
                            onClick = onLogReturn,
                            modifier = Modifier.weight(1f),
                        ) {
                            Icon(
                                Icons.Default.AssignmentReturn,
                                contentDescription = null,
                                modifier = Modifier.size(16.dp),
                            )
                            Spacer(modifier = Modifier.width(4.dp))
                            Text("Log Return")
                        }
                    }
                }
            }
        }
    }
}
