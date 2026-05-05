package com.bizarreelectronics.crm.ui.screens.invoices.components

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
import com.bizarreelectronics.crm.data.local.db.entities.InvoiceEntity

/**
 * Sort options for the invoice list.
 *
 * Default is [Newest] (most recently created first).
 */
enum class InvoiceSort(val label: String) {
    Newest("Newest first"),
    Oldest("Oldest first"),
    AmountHigh("Amount: High → Low"),
    AmountLow("Amount: Low → High"),
    DueDate("Due date"),
    Status("Status"),
}

/**
 * Applies [sort] to [invoices]. Returns a new list; never mutates the input.
 */
fun applyInvoiceSortOrder(invoices: List<InvoiceEntity>, sort: InvoiceSort): List<InvoiceEntity> =
    when (sort) {
        InvoiceSort.Newest     -> invoices.sortedByDescending { it.createdAt }
        InvoiceSort.Oldest     -> invoices.sortedBy { it.createdAt }
        InvoiceSort.AmountHigh -> invoices.sortedByDescending { it.total }
        InvoiceSort.AmountLow  -> invoices.sortedBy { it.total }
        InvoiceSort.DueDate    -> invoices.sortedWith(
            compareBy(
                { it.dueOn == null }, // nulls last
                { it.dueOn ?: "" },
            )
        )
        InvoiceSort.Status     -> invoices.sortedBy { it.status.lowercase() }
    }

/**
 * Overflow icon button + [DropdownMenu] for all [InvoiceSort] options.
 *
 * The currently selected sort has its label highlighted in primary color.
 */
@Composable
fun InvoiceSortDropdown(
    currentSort: InvoiceSort,
    onSortSelected: (InvoiceSort) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }

    Box(contentAlignment = Alignment.TopEnd) {
        IconButton(onClick = { expanded = true }) {
            Icon(
                imageVector = Icons.Default.Sort,
                contentDescription = "Sort invoices",
                tint = MaterialTheme.colorScheme.onSurface,
            )
        }
        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
        ) {
            InvoiceSort.entries.forEach { sort ->
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
                                MaterialTheme.typography.bodyMedium.copy(
                                    fontWeight = FontWeight.SemiBold,
                                )
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
