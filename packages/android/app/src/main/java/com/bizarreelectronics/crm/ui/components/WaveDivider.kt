package com.bizarreelectronics.crm.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.dp

/**
 * WaveDivider — brand signature cubic-curve divider.
 *
 * Renders a single wave using a cubic Bézier path:
 *   - Base wave: outline color at ~15% alpha (low-contrast texture)
 *   - Hairline underneath: decorative magenta at ~60% alpha (single accent line)
 *
 * ## Color policy (CROSS19/CROSS45-ext — brand accent is ORANGE, not magenta):
 * The hairline uses a HARDCODED magenta (#BC398F) that is deliberately
 * orthogonal to `MaterialTheme.colorScheme.primary`. The wave is the only
 * sanctioned decorative flourish using the magenta hue — every other primary
 * CTA, link, and selection indicator must route through `colorScheme.primary`
 * (orange). Do NOT pull this hairline color from `colorScheme.tertiary` — if
 * a future theme bump changes tertiary, the wave must still render magenta.
 *
 * Height: ~24dp. Horizontal fill follows the modifier.
 *
 * ## Sanctioned placements (at most ONE per screen):
 *   - LoginScreen.kt:506    — under the "Bizarre CRM" wordmark
 *   - DashboardScreen.kt:290 — above the greeting block
 *   - TicketSuccessScreen.kt:33 — above the checkmark Surface
 *   - SharedComponents.kt EmptyState composable — framing empty states
 *
 * ## Forbidden placements:
 *   - Card borders
 *   - List row separators
 *   - Top-bar bottoms
 *   - Form section dividers
 *   - FAB backgrounds
 *   - Settings group headers
 *   - Any location that would result in more than one WaveDivider visible
 *     on the same screen simultaneously
 *
 * Rule of thumb: if you can see another WaveDivider anywhere on screen,
 * do not add a second one.
 */

/**
 * Hardcoded magenta for the wave hairline. Intentionally decoupled from
 * `MaterialTheme.colorScheme` so the decorative flourish stays magenta
 * regardless of primary/tertiary theme changes. See CROSS45-ext.
 */
private val WaveMagenta = Color(0xFFBC398F)

@Composable
fun WaveDivider(modifier: Modifier = Modifier) {
    val outlineColor = MaterialTheme.colorScheme.outline
    val magenta = WaveMagenta

    Canvas(
        modifier = modifier
            .fillMaxWidth()
            .height(24.dp),
    ) {
        val w = size.width
        val h = size.height

        // Control point heights for a gentle single-cycle wave.
        // The wave crests at ~30% height and troughs at ~70% height.
        val wavePath = Path().apply {
            moveTo(0f, h * 0.5f)
            cubicTo(
                w * 0.25f, h * 0.1f,   // first control point — upswing
                w * 0.75f, h * 0.9f,   // second control point — downswing
                w,          h * 0.5f,  // end point
            )
        }

        // Base wave: outline color at 15% alpha
        drawPath(
            path = wavePath,
            color = outlineColor.copy(alpha = 0.15f),
            style = Stroke(width = 1.5.dp.toPx()),
        )

        // Magenta hairline: shifted 2dp below, single-pixel
        val hairlinePath = Path().apply {
            val offset = 2.dp.toPx()
            moveTo(0f, h * 0.5f + offset)
            cubicTo(
                w * 0.25f, h * 0.1f + offset,
                w * 0.75f, h * 0.9f + offset,
                w,          h * 0.5f + offset,
            )
        }
        drawPath(
            path = hairlinePath,
            color = magenta.copy(alpha = 0.60f),
            style = Stroke(width = 1.dp.toPx()),
        )
    }
}
