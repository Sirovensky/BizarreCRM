package com.bizarreelectronics.crm.ui.screens.importdata.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.screens.importdata.ImportSource

/**
 * Step 1 — Source picker card.
 * Shows all [ImportSource] options as selectable chips.
 */
@Composable
fun SourcePickerCard(
    selected: ImportSource,
    onSelect: (ImportSource) -> Unit,
    modifier: Modifier = Modifier,
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = "Select import source",
                style = MaterialTheme.typography.titleMedium,
            )
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ImportSource.entries.forEach { source ->
                    FilterChip(
                        selected = source == selected,
                        onClick = { onSelect(source) },
                        label = { Text(source.label) },
                    )
                }
            }
            Text(
                text = when (selected) {
                    ImportSource.REPAIR_DESK ->
                        "Export a full CSV backup from RepairDesk → Reports → Data Export."
                    ImportSource.SHOPR ->
                        "Export from Shopr POS → Admin → Export Data."
                    ImportSource.MRA ->
                        "Export from Mobile Repair Automation (MRA) backup file."
                    ImportSource.GENERIC_CSV ->
                        "Any CSV with a header row. You will map columns manually."
                },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
