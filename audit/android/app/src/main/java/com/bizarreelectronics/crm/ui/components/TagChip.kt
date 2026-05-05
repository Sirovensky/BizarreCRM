package com.bizarreelectronics.crm.ui.components

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.LocalOffer
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

/**
 * TAG-PALETTE-001: default 8-hue cycle used when GET /settings/tag-palette
 * returns 404 or does not contain the requested tag label. Colors are chosen
 * to be readable at label-size text on both light and dark M3 surfaces.
 */
private val DEFAULT_TAG_HUES: List<Color> = listOf(
    Color(0xFF6650A4), // M3 primary violet
    Color(0xFF0B6E4F), // teal-green
    Color(0xFFB86200), // amber-orange
    Color(0xFF006874), // cyan-deep
    Color(0xFF7D5260), // mauve
    Color(0xFF375FA6), // royal blue
    Color(0xFF5C6200), // olive
    Color(0xFF8B1A1A), // dark red
)

/**
 * Deterministically map a tag label to one of the 8 default hues by hashing
 * the label string. Produces stable assignments across recompositions without
 * storing state: same label always gets the same color from the cycle.
 */
fun hashTagToColor(label: String, palette: Map<String, Color> = emptyMap()): Color {
    palette[label.trim()]?.let { return it }
    val index = Math.abs(label.trim().hashCode()) % DEFAULT_TAG_HUES.size
    return DEFAULT_TAG_HUES[index]
}

/**
 * Reusable Material 3 chip for customer/ticket/inventory tags.
 *
 * Visual:
 *   - [containerColor] derived from tenant tag palette (TAG-PALETTE-001) or
 *     the default 8-hue hash cycle when no palette entry exists.
 *   - White/near-white text on the derived background for contrast.
 *   - LocalOffer leading icon (when not removable).
 *   - Close trailing icon shown when [onRemove] is non-null.
 *   - 8dp rounded corners — tighter than the 12dp card/button token.
 *
 * Accessibility:
 *   - contentDescription = "Tag: $label" for TalkBack sweep.
 *
 * Click behaviour:
 *   - [onClick] null → non-interactive display chip.
 *   - [onClick] supplied → tappable AssistChip (filter-by-tag flow).
 *   - [onRemove] supplied → trailing × icon for chip removal (create/edit form).
 *
 * Empty / blank labels are rejected early — this composable renders nothing.
 */
@Composable
fun TagChip(
    label: String,
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    onRemove: (() -> Unit)? = null,
    tagPalette: Map<String, Color> = emptyMap(),
) {
    val trimmed = label.trim()
    if (trimmed.isEmpty()) return

    val shape = RoundedCornerShape(8.dp)
    val containerColor = hashTagToColor(trimmed, tagPalette)
    // Derive on-container text: use white for dark containers, near-black for light.
    val luminance = (0.299f * containerColor.red + 0.587f * containerColor.green +
        0.114f * containerColor.blue)
    val onContainerColor = if (luminance < 0.55f) Color.White else Color(0xFF1C1B1F)

    val a11yModifier = modifier.semantics {
        contentDescription = "Tag: $trimmed"
    }

    if (onRemove != null) {
        // InputChip-style — used in the tag editor on create/edit forms.
        InputChip(
            selected = false,
            onClick = onClick ?: {},
            label = { Text(trimmed, style = MaterialTheme.typography.labelMedium, color = onContainerColor) },
            leadingIcon = {
                Icon(
                    imageVector = Icons.Default.LocalOffer,
                    contentDescription = null,
                    tint = onContainerColor,
                )
            },
            trailingIcon = {
                IconButton(onClick = onRemove) {
                    Icon(
                        imageVector = Icons.Default.Close,
                        contentDescription = "Remove tag $trimmed",
                        tint = onContainerColor,
                    )
                }
            },
            shape = shape,
            colors = InputChipDefaults.inputChipColors(
                containerColor = containerColor,
                selectedContainerColor = containerColor,
                labelColor = onContainerColor,
                leadingIconColor = onContainerColor,
                trailingIconColor = onContainerColor,
            ),
            border = null,
            modifier = a11yModifier,
        )
    } else if (onClick != null) {
        AssistChip(
            onClick = onClick,
            label = { Text(trimmed, style = MaterialTheme.typography.labelMedium, color = onContainerColor) },
            leadingIcon = {
                Icon(
                    imageVector = Icons.Default.LocalOffer,
                    contentDescription = null,
                    tint = onContainerColor,
                )
            },
            shape = shape,
            colors = AssistChipDefaults.assistChipColors(
                containerColor = containerColor,
                labelColor = onContainerColor,
                leadingIconContentColor = onContainerColor,
            ),
            border = null,
            modifier = a11yModifier,
        )
    } else {
        SuggestionChip(
            onClick = {},
            label = { Text(trimmed, style = MaterialTheme.typography.labelMedium, color = onContainerColor) },
            icon = {
                Icon(
                    imageVector = Icons.Default.LocalOffer,
                    contentDescription = null,
                    tint = onContainerColor,
                )
            },
            shape = shape,
            colors = SuggestionChipDefaults.suggestionChipColors(
                containerColor = containerColor,
                labelColor = onContainerColor,
                iconContentColor = onContainerColor,
            ),
            border = null,
            modifier = a11yModifier,
        )
    }
}
