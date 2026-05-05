package com.bizarreelectronics.crm.ui.screens.customers.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/**
 * Active filter state for the customer list (plan:L876).
 * Immutable — VMs copy-on-update.
 */
data class CustomerFilter(
    val ltvTier: String? = null,          // null = all; "VIP" | "Regular" | "At-Risk"
    val hasBalance: Boolean = false,
    val hasOpenTickets: Boolean = false,
    val city: String? = null,
    val state: String? = null,
)

val CustomerFilter.filterKey: String
    get() = buildList {
        ltvTier?.let { add("tier:$it") }
        if (hasBalance) add("balance")
        if (hasOpenTickets) add("open_tickets")
        city?.let { add("city:$it") }
    }.joinToString("|").ifBlank { "" }

private val LTV_TIERS = listOf("VIP", "Regular", "At-Risk")

/**
 * ModalBottomSheet filter panel for the customer list.
 * Mirrors the TicketSavedViewSheet layout style.
 *
 * @param filter         Current filter state.
 * @param onFilterChange Callback when any filter control changes.
 * @param onDismiss      Callback to close the sheet.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun CustomerFilterSheet(
    filter: CustomerFilter,
    onFilterChange: (CustomerFilter) -> Unit,
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
                .verticalScroll(rememberScrollState())
                .padding(bottom = 32.dp),
        ) {
            // Header
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "Filter customers",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                TextButton(
                    onClick = { onFilterChange(CustomerFilter()); onDismiss() },
                ) {
                    Text("Clear all")
                }
            }

            HorizontalDivider()
            Spacer(modifier = Modifier.height(8.dp))

            // LTV tier
            Text(
                "LTV tier",
                modifier = Modifier.padding(horizontal = 16.dp),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(modifier = Modifier.height(4.dp))
            FlowRow(
                modifier = Modifier.padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                LTV_TIERS.forEach { tier ->
                    FilterChip(
                        selected = filter.ltvTier == tier,
                        onClick = {
                            onFilterChange(
                                filter.copy(ltvTier = if (filter.ltvTier == tier) null else tier)
                            )
                        },
                        label = { Text(tier) },
                    )
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            // Toggles
            SwitchRow(
                label = "Has unpaid balance",
                checked = filter.hasBalance,
                onCheckedChange = { onFilterChange(filter.copy(hasBalance = it)) },
            )
            SwitchRow(
                label = "Has open tickets",
                checked = filter.hasOpenTickets,
                onCheckedChange = { onFilterChange(filter.copy(hasOpenTickets = it)) },
            )

            Spacer(modifier = Modifier.height(8.dp))
        }
    }
}

@Composable
private fun SwitchRow(
    label: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = MaterialTheme.typography.bodyMedium)
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}
