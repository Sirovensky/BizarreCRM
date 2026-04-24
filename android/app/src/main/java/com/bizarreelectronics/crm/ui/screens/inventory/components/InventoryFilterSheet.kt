package com.bizarreelectronics.crm.ui.screens.inventory.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp

/**
 * Stock-status filter values.
 */
enum class StockStatus(val label: String) {
    All("All"),
    InStock("In stock"),
    LowStock("Low stock"),
    OutOfStock("Out of stock"),
}

/**
 * Immutable filter state returned from [InventoryFilterSheet].
 *
 * An "empty" filter (all defaults) produces [InventoryFilter.Empty].
 */
data class InventoryFilter(
    val category: String? = null,
    val supplier: String? = null,
    val stockStatus: StockStatus = StockStatus.All,
    val bin: String? = null,
    val minPriceCents: Long? = null,
    val maxPriceCents: Long? = null,
    val tag: String? = null,
) {
    companion object {
        val Empty = InventoryFilter()
    }

    /** Number of non-default filter fields — drives the badge on the filter icon. */
    val activeCount: Int
        get() = listOfNotNull(
            category,
            supplier,
            if (stockStatus != StockStatus.All) stockStatus else null,
            bin,
            minPriceCents,
            maxPriceCents,
            tag,
        ).size
}

/**
 * Modal bottom-sheet filter drawer for the inventory list.
 *
 * Sections: category, supplier, stock-status chips, bin location, price range, tag.
 * The [Apply] button returns the constructed [InventoryFilter] via [onApply].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InventoryFilterSheet(
    current: InventoryFilter,
    onApply: (InventoryFilter) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    var category by remember { mutableStateOf(current.category ?: "") }
    var supplier by remember { mutableStateOf(current.supplier ?: "") }
    var stockStatus by remember { mutableStateOf(current.stockStatus) }
    var bin by remember { mutableStateOf(current.bin ?: "") }
    var minPrice by remember { mutableStateOf(current.minPriceCents?.let { (it / 100.0).toString() } ?: "") }
    var maxPrice by remember { mutableStateOf(current.maxPriceCents?.let { (it / 100.0).toString() } ?: "") }
    var tag by remember { mutableStateOf(current.tag ?: "") }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text("Filter inventory", style = MaterialTheme.typography.titleMedium)

            HorizontalDivider()

            // Category
            FilterTextField(
                label = "Category",
                value = category,
                onValueChange = { category = it },
            )

            // Supplier
            FilterTextField(
                label = "Supplier",
                value = supplier,
                onValueChange = { supplier = it },
            )

            // Stock status chips
            Text(
                "Stock status",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items(StockStatus.entries, key = { it.name }) { status ->
                    FilterChip(
                        selected = stockStatus == status,
                        onClick = { stockStatus = status },
                        label = { Text(status.label) },
                    )
                }
            }

            // Bin
            FilterTextField(
                label = "Bin location",
                value = bin,
                onValueChange = { bin = it },
            )

            // Price range
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                OutlinedTextField(
                    value = minPrice,
                    onValueChange = { minPrice = it },
                    label = { Text("Min price ($)") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                )
                OutlinedTextField(
                    value = maxPrice,
                    onValueChange = { maxPrice = it },
                    label = { Text("Max price ($)") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                )
            }

            // Tag
            FilterTextField(
                label = "Tag",
                value = tag,
                onValueChange = { tag = it },
            )

            Spacer(modifier = Modifier.height(4.dp))

            // Action row
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TextButton(
                    onClick = {
                        onApply(InventoryFilter.Empty)
                        onDismiss()
                    },
                ) {
                    Text("Clear all")
                }
                Spacer(modifier = Modifier.width(8.dp))
                Button(
                    onClick = {
                        onApply(
                            InventoryFilter(
                                category = category.trim().takeIf { it.isNotEmpty() },
                                supplier = supplier.trim().takeIf { it.isNotEmpty() },
                                stockStatus = stockStatus,
                                bin = bin.trim().takeIf { it.isNotEmpty() },
                                minPriceCents = minPrice.trim().toDoubleOrNull()
                                    ?.let { (it * 100).toLong() },
                                maxPriceCents = maxPrice.trim().toDoubleOrNull()
                                    ?.let { (it * 100).toLong() },
                                tag = tag.trim().takeIf { it.isNotEmpty() },
                            )
                        )
                        onDismiss()
                    },
                ) {
                    Text("Apply")
                }
            }
        }
    }
}

@Composable
private fun FilterTextField(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { Text(label) },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
    )
}
