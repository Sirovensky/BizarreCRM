package com.bizarreelectronics.crm.ui.screens.inventory.components

import androidx.compose.foundation.layout.Box
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Sort
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.text.font.FontWeight

/**
 * Sort options for the inventory list.
 * Default is [NameAZ] (alphabetical by name).
 */
enum class InventorySort(val label: String) {
    SkuAZ("SKU"),
    NameAZ("Name A–Z"),
    StockDesc("Stock (high → low)"),
    LastRestocked("Last restocked"),
    PriceAsc("Price (low → high)"),
    CostAsc("Cost (low → high)"),
}

/**
 * Applies [InventorySort] ordering to a list.
 * Called from the ViewModel and from unit tests.
 */
fun applyInventorySortOrder(
    items: List<com.bizarreelectronics.crm.data.local.db.entities.InventoryItemEntity>,
    sort: InventorySort,
): List<com.bizarreelectronics.crm.data.local.db.entities.InventoryItemEntity> =
    when (sort) {
        InventorySort.SkuAZ       -> items.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.sku ?: "" })
        InventorySort.NameAZ      -> items.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name })
        InventorySort.StockDesc   -> items.sortedByDescending { it.inStock }
        InventorySort.LastRestocked -> items.sortedByDescending { it.updatedAt }
        InventorySort.PriceAsc    -> items.sortedBy { it.retailPriceCents }
        InventorySort.CostAsc     -> items.sortedBy { it.costPriceCents }
    }

/**
 * Overflow icon that expands a [DropdownMenu] for all [InventorySort] options.
 * Currently selected sort is highlighted in primary.
 */
@Composable
fun InventorySortDropdown(
    currentSort: InventorySort,
    onSortSelected: (InventorySort) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }

    Box(contentAlignment = Alignment.TopEnd) {
        IconButton(onClick = { expanded = true }) {
            Icon(
                imageVector = Icons.Default.Sort,
                contentDescription = "Sort inventory",
                tint = MaterialTheme.colorScheme.onSurface,
            )
        }
        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
        ) {
            InventorySort.entries.forEach { sort ->
                val isSelected = sort == currentSort
                DropdownMenuItem(
                    text = {
                        Text(
                            text = sort.label,
                            color = if (isSelected) {
                                MaterialTheme.colorScheme.primary
                            } else {
                                MaterialTheme.colorScheme.onSurface
                            },
                            style = if (isSelected) {
                                MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold)
                            } else {
                                MaterialTheme.typography.bodyMedium
                            },
                        )
                    },
                    onClick = {
                        onSortSelected(sort)
                        expanded = false
                    },
                )
            }
        }
    }
}
