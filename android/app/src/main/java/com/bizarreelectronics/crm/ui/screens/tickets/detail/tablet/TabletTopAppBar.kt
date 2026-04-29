package com.bizarreelectronics.crm.ui.screens.tickets.detail.tablet

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.screens.tickets.detail.tablet.shared.AsymmetricStatusShape

/**
 * Tablet ticket-detail top app bar.
 *
 * Geometry from `mockups/android-tablet-ticket-detail.html`:
 *
 *   ┌────────────────────────────────────────────────────────────────┐
 *   │ ←  T-1232   [↔ In Progress (cream pill)]   [actions slot] ⋮    │
 *   └────────────────────────────────────────────────────────────────┘
 *
 * The cream Status pill uses the brand asymmetric shape
 * ([AsymmetricStatusShape] — `RoundedCornerShape(22, 8, 22, 8)`) for
 * the M3-Expressive shape token, with a subtle hover/press
 * animation to suggest the shape-morph affordance even though we
 * don't perform a true Material3 shape-morph in v1.
 *
 * The right-side action row (Print actions / Pin / overflow `⋮`) is
 * a slot — the host screen passes the same composables it uses on the
 * phone path so behaviour stays identical, only the visual treatment
 * changes here on tablet.
 *
 * @param onBack invoked when the back arrow is tapped.
 * @param ticketTitle short title, e.g. `T-1232` or the order id.
 * @param currentStatusName name of the active ticket status, shown on
 *   the cream pill. Empty string falls back to "Status" so the pill
 *   always has visible content.
 * @param onStatusPillClick tap handler — host opens [StatusPickerSheet].
 * @param actions trailing-action `RowScope` slot. Host plugs in
 *   `TicketPrintActions`, the Pin icon, and the existing `⋮` overflow
 *   menu so feature parity with phone is preserved.
 */
@Composable
internal fun TabletTopAppBar(
    onBack: () -> Unit,
    ticketTitle: String,
    currentStatusName: String,
    onStatusPillClick: () -> Unit,
    actions: @Composable RowScope.() -> Unit,
    deviceChipLabel: String? = null,
) {
    Surface(
        color = MaterialTheme.colorScheme.background,
        modifier = Modifier
            .fillMaxWidth()
            .height(64.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            // Back arrow
            IconButton(onClick = onBack) {
                Icon(
                    Icons.AutoMirrored.Filled.ArrowBack,
                    contentDescription = "Back",
                )
            }

            // Ticket id title
            Text(
                ticketTitle,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.semantics { contentDescription = "Ticket $ticketTitle" },
            )

            // Device chip — model + service summary in a pill, surface bg.
            if (!deviceChipLabel.isNullOrBlank()) {
                Surface(
                    color = MaterialTheme.colorScheme.surfaceVariant,
                    shape = RoundedCornerShape(999.dp),
                    modifier = Modifier
                        .padding(start = 6.dp)
                        .height(32.dp),
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Text(
                            deviceChipLabel,
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                        )
                    }
                }
            }

            // Spacer
            Box(modifier = Modifier.weight(1f))

            // Cream Status pill — primary action affordance.
            StatusPill(
                statusName = currentStatusName.ifBlank { "Status" },
                onClick = onStatusPillClick,
            )

            // Right-side action row — Print, Pin, ⋮ slot.
            actions()
        }
    }
}

/**
 * Cream status pill with brand asymmetric shape and a subtle
 * hover/press radius animation. Tap → host opens the picker sheet.
 *
 * Idle:   `(22, 8, 22, 8)` — strongest brand shape token.
 * Hover:  `(22, 14, 22, 14)` — softer, signals interactivity.
 * Press:  `(14, 22, 14, 22)` — flips the asymmetry, M3-Expressive
 *         shape-morph echo. Reverts on release.
 */
@Composable
private fun StatusPill(
    statusName: String,
    onClick: () -> Unit,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()
    val isHovered by interactionSource.collectIsHoveredAsState()

    // Choose the four corner radii based on interaction state.
    val (tl, tr, br, bl) = when {
        isPressed -> arrayOf(14, 22, 14, 22)
        isHovered -> arrayOf(22, 14, 22, 14)
        else -> arrayOf(22, 8, 22, 8)
    }
    val animTl by animateDpAsState(tl.dp, animationSpec = tween(220), label = "pill_tl")
    val animTr by animateDpAsState(tr.dp, animationSpec = tween(220), label = "pill_tr")
    val animBr by animateDpAsState(br.dp, animationSpec = tween(220), label = "pill_br")
    val animBl by animateDpAsState(bl.dp, animationSpec = tween(220), label = "pill_bl")

    Surface(
        onClick = onClick,
        interactionSource = interactionSource,
        color = MaterialTheme.colorScheme.primaryContainer,
        contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
        shape = RoundedCornerShape(
            topStart = animTl,
            topEnd = animTr,
            bottomEnd = animBr,
            bottomStart = animBl,
        ),
        modifier = Modifier
            .height(38.dp)
            .semantics { contentDescription = "Current status: $statusName. Tap to change." },
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(
                imageVector = Icons.Default.SwapHoriz,
                contentDescription = null,
                modifier = Modifier.size(16.dp),
            )
            Text(
                statusName,
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.Medium,
            )
        }
    }
}

// Avoid unused-import warning when AsymmetricStatusShape is not
// directly referenced; the file imports the constant so future
// commits that swap to a static shape can drop the animation easily.
@Suppress("unused")
private val SilencerForAsymmetricShape = AsymmetricStatusShape

// Suppress unused-import warning on Color until a future commit uses it.
@Suppress("unused")
private val SilencerForColor: Color = Color.Unspecified

// Suppress unused-import warning on width until added to action slot.
@Suppress("unused")
private val SilencerForWidth = Modifier.width(0.dp)

// Suppress unused-import on clip until shape morph extracted.
@Suppress("unused")
private val SilencerForClip = Modifier.clip(RoundedCornerShape(0.dp))
