package com.bizarreelectronics.crm.ui.components

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LocalOffer
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

/**
 * Reusable Material 3 chip for customer/ticket/inventory tags.
 *
 * Visual:
 *   - secondaryContainer background / onSecondaryContainer text
 *   - LocalOffer leading icon
 *   - 8dp rounded corners — tighter than the 12dp card/button token;
 *     tags are dense, compact radius reads better at small height.
 *   - 32dp height target via Compose chip defaults (ChipDefaults already
 *     produces ~32dp; no explicit height override required).
 *
 * Accessibility:
 *   - contentDescription = "Tag: $label" for TalkBack sweep.
 *
 * Click behaviour:
 *   - If [onClick] is null (default), renders a non-interactive [SuggestionChip]
 *     styled to look identical but carrying no ripple/role semantics.
 *   - If [onClick] is supplied, renders an [AssistChip] — enables filter-by-tag
 *     flow in future waves without a new composable.
 *
 * Empty / blank labels must be filtered by the caller; this composable renders
 * nothing (early-return) if [label] is blank after trimming, providing a
 * defensive backstop.
 */
@Composable
fun TagChip(
    label: String,
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
) {
    val trimmed = label.trim()
    if (trimmed.isEmpty()) return

    val shape = RoundedCornerShape(8.dp)
    val chipColors = SuggestionChipDefaults.suggestionChipColors(
        containerColor = MaterialTheme.colorScheme.secondaryContainer,
        labelColor = MaterialTheme.colorScheme.onSecondaryContainer,
        iconContentColor = MaterialTheme.colorScheme.onSecondaryContainer,
    )

    val a11yModifier = modifier.semantics {
        contentDescription = "Tag: $trimmed"
    }

    if (onClick != null) {
        AssistChip(
            onClick = onClick,
            label = { Text(trimmed, style = MaterialTheme.typography.labelMedium) },
            leadingIcon = {
                Icon(
                    imageVector = Icons.Default.LocalOffer,
                    contentDescription = null, // parent semantics cover it
                    tint = MaterialTheme.colorScheme.onSecondaryContainer,
                )
            },
            shape = shape,
            colors = AssistChipDefaults.assistChipColors(
                containerColor = MaterialTheme.colorScheme.secondaryContainer,
                labelColor = MaterialTheme.colorScheme.onSecondaryContainer,
                leadingIconContentColor = MaterialTheme.colorScheme.onSecondaryContainer,
            ),
            border = null,
            modifier = a11yModifier,
        )
    } else {
        SuggestionChip(
            onClick = {},
            label = { Text(trimmed, style = MaterialTheme.typography.labelMedium) },
            icon = {
                Icon(
                    imageVector = Icons.Default.LocalOffer,
                    contentDescription = null, // parent semantics cover it
                    tint = MaterialTheme.colorScheme.onSecondaryContainer,
                )
            },
            shape = shape,
            colors = chipColors,
            border = null,
            modifier = a11yModifier,
        )
    }
}
