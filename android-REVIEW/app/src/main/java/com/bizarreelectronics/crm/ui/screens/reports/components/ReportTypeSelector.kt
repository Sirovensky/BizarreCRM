package com.bizarreelectronics.crm.ui.screens.reports.components

import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MultiChoiceSegmentedButtonRow
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

/**
 * SegmentedButton row for selecting the active report type (ActionPlan §15 L1722).
 *
 * Selecting a type routes the caller to the appropriate sub-screen. The
 * [onSelect] callback receives the chosen [ReportType]; the parent
 * composable is responsible for navigating to the correct route.
 *
 * Types match the plan spec:
 *   Sales / Tickets / Employees / Inventory / Tax / Insights / Custom
 *
 * For screen widths that cannot fit all 7 labels, the row scrolls horizontally
 * via [SingleChoiceSegmentedButtonRow]'s scroll behaviour.
 */
enum class ReportType(val label: String) {
    SALES("Sales"),
    TICKETS("Tickets"),
    EMPLOYEES("Employees"),
    INVENTORY("Inventory"),
    TAX("Tax"),
    INSIGHTS("Insights"),
    CUSTOM("Custom"),
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReportTypeSelector(
    selected: ReportType,
    onSelect: (ReportType) -> Unit,
    modifier: Modifier = Modifier,
) {
    val types = ReportType.values()
    SingleChoiceSegmentedButtonRow(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .semantics { contentDescription = "Report type selector: ${selected.label} selected" },
    ) {
        types.forEachIndexed { index, type ->
            SegmentedButton(
                selected = type == selected,
                onClick = { onSelect(type) },
                shape = SegmentedButtonDefaults.itemShape(index = index, count = types.size),
                label = {
                    Text(
                        text = type.label,
                        style = MaterialTheme.typography.labelSmall,
                    )
                },
            )
        }
    }
}
