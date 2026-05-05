package com.bizarreelectronics.crm.ui.screens.expenses.components

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Sort
import androidx.compose.material3.*
import androidx.compose.runtime.*

enum class ExpenseSort(val label: String) {
    DATE("Date"),
    AMOUNT("Amount"),
    CATEGORY("Category"),
}

@Composable
fun ExpenseSortDropdown(
    currentSort: ExpenseSort,
    onSortSelected: (ExpenseSort) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }

    IconButton(onClick = { expanded = true }) {
        Icon(Icons.Default.Sort, contentDescription = "Sort expenses by ${currentSort.label}")
    }
    DropdownMenu(
        expanded = expanded,
        onDismissRequest = { expanded = false },
    ) {
        ExpenseSort.entries.forEach { sort ->
            DropdownMenuItem(
                text = { Text(sort.label) },
                onClick = {
                    onSortSelected(sort)
                    expanded = false
                },
                trailingIcon = {
                    if (sort == currentSort) {
                        Icon(
                            Icons.Default.Sort,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    }
                },
            )
        }
    }
}
