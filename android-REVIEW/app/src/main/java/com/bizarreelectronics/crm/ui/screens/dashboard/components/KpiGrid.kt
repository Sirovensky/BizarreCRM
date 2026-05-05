package com.bizarreelectronics.crm.ui.screens.dashboard.components

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.TrendingDown
import androidx.compose.material.icons.filled.TrendingFlat
import androidx.compose.material.icons.filled.TrendingUp
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.SuggestionChipDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.theme.DashboardDensity
import com.bizarreelectronics.crm.ui.theme.ErrorRed
import com.bizarreelectronics.crm.ui.theme.LocalDashboardDensity
import com.bizarreelectronics.crm.ui.theme.SuccessGreen
import com.bizarreelectronics.crm.ui.theme.WarningAmber
import com.bizarreelectronics.crm.util.WindowMode
import com.bizarreelectronics.crm.util.rememberWindowMode

/**
 * §3 L488 — KPI tile data model.
 *
 * [deltaPercent] is nullable — absent until the backend `/dashboard/compare`
 * endpoint ships. The UI slot is wired but only rendered when non-null.
 * This avoids a separate model migration once the compare API lands.
 */
data class KpiTile(
    val label: String,
    val value: String,
    val iconTint: Color,
    val icon: @Composable () -> Unit,
    /** Positive = gained, negative = lost, null = no prior-period data. */
    val deltaPercent: Double? = null,
    val onClick: (() -> Unit)? = null,
)

/**
 * §3 L488 / §3.19 L613 — Responsive KPI grid with density-mode support.
 *
 * Column count and spacing are driven by [LocalDashboardDensity]:
 *
 * | Density     | Phone | Tablet/Desktop |
 * |-------------|-------|----------------|
 * | Comfortable | 1     | 2              |
 * | Cozy        | 2     | 3              |
 * | Compact     | 3     | 4              |
 *
 * Uses WindowMode from [rememberWindowMode] — same helper used throughout
 * the app so layout reacts to foldable posture and multi-window resize.
 */
@Composable
fun KpiGrid(
    tiles: List<KpiTile>,
    modifier: Modifier = Modifier,
) {
    val windowMode = rememberWindowMode()
    val density = LocalDashboardDensity.current
    val columnCount = density.columnsForWindowSize(windowMode)
    val spacing = density.baseSpacing

    val rows = tiles.chunked(columnCount)
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(spacing),
    ) {
        rows.forEach { rowTiles ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = spacing),
                horizontalArrangement = Arrangement.spacedBy(spacing),
            ) {
                rowTiles.forEach { tile ->
                    KpiTileCard(tile = tile, modifier = Modifier.weight(1f))
                }
                // Pad incomplete last row so columns stay uniform width.
                repeat(columnCount - rowTiles.size) {
                    Spacer(modifier = Modifier.weight(1f))
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// KpiTileCard — M3 card with delta chip
// ---------------------------------------------------------------------------

/**
 * §3 L488 / L492 — single KPI tile card.
 *
 * Renders:
 * - Icon (decorative, tint carries semantic state)
 * - Value (headlineMedium / Barlow Condensed)
 * - Label (bodySmall / muted)
 * - Delta chip (§3 L492): shown only when [KpiTile.deltaPercent] is non-null;
 *   green for positive, red for negative, grey for zero.
 *
 * Accessibility:
 * - mergeDescendants collapses all children into one TalkBack node.
 * - contentDescription spells out value, label, and delta trend in words.
 * - Role.Button only on clickable tiles.
 */
@Composable
private fun KpiTileCard(
    tile: KpiTile,
    modifier: Modifier = Modifier,
) {
    val deltaA11y = when {
        tile.deltaPercent == null -> ""
        tile.deltaPercent > 0 -> ". Up ${String.format("%.1f", tile.deltaPercent)}% versus last period"
        tile.deltaPercent < 0 -> ". Down ${String.format("%.1f", -tile.deltaPercent)}% versus last period"
        else -> ". No change versus last period"
    }

    val semanticsModifier = if (tile.onClick != null) {
        Modifier.semantics(mergeDescendants = true) {
            contentDescription = "${tile.label}: ${tile.value}$deltaA11y. Tap to view list."
            role = Role.Button
        }
    } else {
        Modifier.semantics(mergeDescendants = true) {
            contentDescription = "${tile.label}: ${tile.value}$deltaA11y."
        }
    }

    val clickModifier = tile.onClick?.let { Modifier.clickable(onClick = it) } ?: Modifier

    Card(
        modifier = modifier
            .defaultMinSize(minHeight = 48.dp)
            .then(semanticsModifier)
            .border(
                width = 1.dp,
                color = MaterialTheme.colorScheme.outline,
                shape = MaterialTheme.shapes.medium,
            )
            .then(clickModifier)
            .animateContentSize(),
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(
            modifier = Modifier.padding(
                start = 16.dp,
                end = 16.dp,
                top = 20.dp,
                bottom = 16.dp,
            ),
        ) {
            tile.icon()
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = tile.value,
                style = MaterialTheme.typography.headlineMedium,
                color = tile.iconTint,
            )
            Text(
                text = tile.label,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            // §3 L492 — delta chip: only rendered when prior-period data is available.
            if (tile.deltaPercent != null) {
                Spacer(modifier = Modifier.height(4.dp))
                DeltaChip(deltaPercent = tile.deltaPercent)
            }
        }
    }
}

// ---------------------------------------------------------------------------
// DeltaChip — period-over-period comparison indicator
// ---------------------------------------------------------------------------

/**
 * §3 L492 — delta chip showing period-over-period change.
 *
 * Green ↗ for positive, red ↘ for negative, grey → for zero.
 * Color assignment satisfies WCAG AA on both M3 surface variants.
 */
@Composable
private fun DeltaChip(deltaPercent: Double) {
    val (icon, color, label) = when {
        deltaPercent > 0 -> Triple(
            Icons.Default.TrendingUp,
            SuccessGreen,
            "+${String.format("%.1f", deltaPercent)}%",
        )
        deltaPercent < 0 -> Triple(
            Icons.Default.TrendingDown,
            ErrorRed,
            "${String.format("%.1f", deltaPercent)}%",
        )
        else -> Triple(
            Icons.Default.TrendingFlat,
            MaterialTheme.colorScheme.onSurfaceVariant,
            "0%",
        )
    }

    SuggestionChip(
        onClick = {},
        label = { Text(text = label, style = MaterialTheme.typography.labelSmall) },
        icon = {
            Icon(
                imageVector = icon,
                contentDescription = null, // chip label + parent contentDescription covers a11y
                modifier = Modifier.size(14.dp),
                tint = color,
            )
        },
        colors = SuggestionChipDefaults.suggestionChipColors(
            labelColor = color,
        ),
        border = SuggestionChipDefaults.suggestionChipBorder(
            enabled = true,
            borderColor = color.copy(alpha = 0.4f),
        ),
    )
}
