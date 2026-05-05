package com.bizarreelectronics.crm.ui.screens.inventory.components

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.theme.LocalExtendedColors

/**
 * Stock status badge rendered per inventory row.
 *
 * - stockQty == 0             → "Out of stock" (errorContainer)
 * - 0 < stockQty < reorderLevel/2 → "Critical low" with pulse animation
 *                                    (pulse is static when ReduceMotion is active)
 * - stockQty < reorderLevel   → "Low stock" (warningContainer)
 * - stockQty >= reorderLevel  → no badge rendered
 *
 * ReduceMotion: reads [android.provider.Settings.Global.TRANSITION_ANIMATION_SCALE];
 * when <= 0 the pulse transition is skipped entirely.
 */
@Composable
fun InventoryStockBadge(
    stockQty: Int,
    reorderLevel: Int,
    modifier: Modifier = Modifier,
) {
    if (stockQty >= reorderLevel && reorderLevel > 0) return
    if (reorderLevel == 0 && stockQty > 0) return

    val extColors = LocalExtendedColors.current
    val scheme = MaterialTheme.colorScheme

    val isCriticalLow = reorderLevel > 0 && stockQty > 0 && stockQty < (reorderLevel / 2.0)
    val isOutOfStock = stockQty == 0

    val reduceMotion = reduceMotionEnabled()

    val alpha: Float = if (isCriticalLow && !reduceMotion) {
        val transition = rememberInfiniteTransition(label = "stockPulse")
        val a by transition.animateFloat(
            initialValue = 1f,
            targetValue = 0.3f,
            animationSpec = infiniteRepeatable(
                animation = tween(durationMillis = 700),
                repeatMode = RepeatMode.Reverse,
            ),
            label = "pulseAlpha",
        )
        a
    } else {
        1f
    }

    val containerColor = when {
        isOutOfStock   -> scheme.errorContainer
        isCriticalLow  -> extColors.warningContainer
        else           -> extColors.warningContainer
    }
    val textColor = when {
        isOutOfStock   -> scheme.onErrorContainer
        isCriticalLow  -> extColors.warning
        else           -> extColors.warning
    }
    val label = when {
        isOutOfStock  -> "Out of stock"
        isCriticalLow -> "Critical low"
        else          -> "Low stock"
    }

    Surface(
        modifier = modifier.alpha(alpha),
        shape = MaterialTheme.shapes.small,
        color = containerColor,
    ) {
        Text(
            text = label,
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
            style = MaterialTheme.typography.labelSmall,
            color = textColor,
            fontWeight = FontWeight.Medium,
        )
    }
}

/**
 * Returns true when the system's transition-animation scale is effectively zero,
 * indicating the user has enabled Reduce Motion / disabled animations.
 *
 * Falls back to false (animations on) when the setting is unavailable.
 */
@Composable
private fun reduceMotionEnabled(): Boolean {
    val context = LocalContext.current
    return try {
        val scale = android.provider.Settings.Global.getFloat(
            context.contentResolver,
            android.provider.Settings.Global.TRANSITION_ANIMATION_SCALE,
        )
        scale <= 0f
    } catch (_: android.provider.Settings.SettingNotFoundException) {
        false
    }
}
