package com.bizarreelectronics.crm.ui.screens.importdata.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.screens.importdata.ColumnMapping

/** Well-known CRM fields that source columns can be mapped to. */
val CRM_FIELD_OPTIONS: List<String> = listOf(
    "(skip)",
    // Customer fields
    "customer.first_name", "customer.last_name", "customer.email",
    "customer.phone", "customer.address", "customer.notes",
    // Ticket fields
    "ticket.title", "ticket.device", "ticket.serial", "ticket.problem",
    "ticket.status", "ticket.due_date", "ticket.technician",
    // Invoice fields
    "invoice.number", "invoice.total", "invoice.date", "invoice.status",
    // Inventory fields
    "inventory.name", "inventory.sku", "inventory.qty", "inventory.cost",
    "inventory.price", "inventory.category",
)

/**
 * Column mapping table — shown in Step COLUMN_MAP.
 * Each row: source column label (left) → CRM field dropdown (right).
 */
@Composable
fun ColumnMapTable(
    mappings: List<ColumnMapping>,
    onMappingChanged: (index: Int, crmField: String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 8.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(
                text = "Source Column",
                style = MaterialTheme.typography.labelMedium,
                modifier = Modifier.weight(1f),
            )
            Text(
                text = "CRM Field",
                style = MaterialTheme.typography.labelMedium,
                modifier = Modifier.weight(1f),
            )
        }
        LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            itemsIndexed(mappings) { index, mapping ->
                MappingRow(
                    mapping = mapping,
                    onFieldChanged = { field -> onMappingChanged(index, field) },
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MappingRow(
    mapping: ColumnMapping,
    onFieldChanged: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    var expanded by remember { mutableStateOf(false) }
    val displayValue = mapping.crmField.ifBlank { "(skip)" }

    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = mapping.sourceColumn,
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.weight(1f),
        )
        ExposedDropdownMenuBox(
            expanded = expanded,
            onExpandedChange = { expanded = !expanded },
            modifier = Modifier.weight(1f),
        ) {
            OutlinedTextField(
                value = displayValue,
                onValueChange = {},
                readOnly = true,
                trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
                modifier = Modifier
                    .fillMaxWidth()
                    .menuAnchor(),
                textStyle = MaterialTheme.typography.bodySmall,
            )
            ExposedDropdownMenu(
                expanded = expanded,
                onDismissRequest = { expanded = false },
            ) {
                CRM_FIELD_OPTIONS.forEach { option ->
                    DropdownMenuItem(
                        text = { Text(option, style = MaterialTheme.typography.bodySmall) },
                        onClick = {
                            onFieldChanged(if (option == "(skip)") "" else option)
                            expanded = false
                        },
                    )
                }
            }
        }
    }
}
