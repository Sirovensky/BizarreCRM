package com.bizarreelectronics.crm.ui.screens.tickets.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/**
 * §4.18 L849-L856 — Label chips displayed on ticket list rows and detail views.
 *
 * Labels are separate from ticket status. Each label is colour-coded based on a
 * stable hash of its name so the same label always renders with the same tint.
 *
 * Auto-rules are computed server-side; Android just renders what the server sends.
 * Bulk apply/remove is handled via [TicketBulkActionBar] → [onBulkTag].
 *
 * ### API endpoints (wired in [TicketApi])
 * - PUT  /tickets/:id/labels         { labels: List<String> }  (setLabels)
 * - POST /tickets/bulk-labels        { ids: List<Long>, label: String }
 *
 * @param labels            Labels to display. May be empty.
 * @param selectedLabel     Currently active filter label (for the list screen).
 *                          When non-null, the matching chip appears selected.
 * @param onLabelClick      Emitted when a label is tapped (for filter toggle in list).
 * @param onLabelRemove     Emitted when the remove icon is tapped (for detail editing).
 *                          Pass null to hide the remove icon.
 * @param modifier          Layout modifier.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun TicketLabelChips(
    labels: List<String>,
    selectedLabel: String? = null,
    onLabelClick: ((label: String) -> Unit)? = null,
    onLabelRemove: ((label: String) -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    if (labels.isEmpty()) return

    FlowRow(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        labels.forEach { label ->
            LabelChip(
                label = label,
                isSelected = label == selectedLabel,
                onClick = { onLabelClick?.invoke(label) },
                onRemove = if (onLabelRemove != null) {
                    { onLabelRemove(label) }
                } else null,
            )
        }
    }
}

// ─── Single chip ─────────────────────────────────────────────────────────────

@Composable
private fun LabelChip(
    label: String,
    isSelected: Boolean,
    onClick: () -> Unit,
    onRemove: (() -> Unit)?,
) {
    val (containerColor, labelColor) = labelColors(label)

    FilterChip(
        selected = isSelected,
        onClick = onClick,
        label = {
            Text(
                text = label,
                style = MaterialTheme.typography.labelSmall,
                modifier = Modifier.padding(horizontal = 2.dp),
            )
        },
        trailingIcon = if (onRemove != null) {
            {
                Icon(
                    Icons.Default.Close,
                    contentDescription = "Remove $label label",
                )
            }
        } else null,
        colors = FilterChipDefaults.filterChipColors(
            containerColor = containerColor,
            labelColor = labelColor,
            selectedContainerColor = containerColor.copy(alpha = 0.9f),
            selectedLabelColor = labelColor,
        ),
    )
}

// ─── Color derivation ─────────────────────────────────────────────────────────

/**
 * Derive a stable (container, label) color pair from a label string.
 *
 * Uses a djb2-style hash of the label to pick from a fixed palette of
 * 6 tints. This ensures the same label always renders with the same color
 * across recompositions and devices without server-side color storage.
 */
@Composable
private fun labelColors(label: String): Pair<Color, Color> {
    val scheme = MaterialTheme.colorScheme
    val palette: List<Pair<Color, Color>> = listOf(
        scheme.primary.copy(alpha = 0.15f)   to scheme.primary,
        scheme.secondary.copy(alpha = 0.15f) to scheme.secondary,
        scheme.tertiary.copy(alpha = 0.15f)  to scheme.tertiary,
        scheme.error.copy(alpha = 0.12f)     to scheme.error,
        Color(0xFF6750A4).copy(alpha = 0.12f) to Color(0xFF6750A4),  // brand violet
        Color(0xFF00796B).copy(alpha = 0.12f) to Color(0xFF00796B),  // teal accent
    )
    val hash = label.fold(5381) { acc, c -> acc * 31 + c.code }
    val idx = Math.floorMod(hash, palette.size)
    return palette[idx]
}
