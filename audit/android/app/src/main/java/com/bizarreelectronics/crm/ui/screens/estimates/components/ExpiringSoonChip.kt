package com.bizarreelectronics.crm.ui.screens.estimates.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.LocalMinimumInteractiveComponentSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.SuggestionChipDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Returns true when [validUntilIso] is within 7 days of today (or already expired).
 *
 * Parses "yyyy-MM-dd" or "yyyy-MM-dd HH:mm:ss" prefixes. Returns false on parse failure
 * so a chip is never shown for malformed dates.
 */
fun isExpiringSoon(validUntilIso: String?): Boolean {
    if (validUntilIso.isNullOrBlank()) return false
    return runCatching {
        val datePart = validUntilIso.take(10)   // "yyyy-MM-dd"
        val parts = datePart.split("-")
        if (parts.size != 3) return false
        val year = parts[0].toInt()
        val month = parts[1].toInt()
        val day = parts[2].toInt()

        val cal = java.util.Calendar.getInstance()
        val todayYear = cal.get(java.util.Calendar.YEAR)
        val todayMonth = cal.get(java.util.Calendar.MONTH) + 1
        val todayDay = cal.get(java.util.Calendar.DAY_OF_MONTH)

        // Convert both dates to day-offsets from epoch-year for simple subtraction
        fun daysFromEpoch(y: Int, m: Int, d: Int): Long {
            // Zeller-lite: each month adds 28-31 days. Good enough for a 7-day window.
            val leapAdj = if (m <= 2) y - 1 else y
            val leapDays = leapAdj / 4 - leapAdj / 100 + leapAdj / 400
            val monthDays = longArrayOf(0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334)
            return y * 365L + leapDays + monthDays[m - 1] + d
        }

        val expiryDays = daysFromEpoch(year, month, day)
        val todayDays = daysFromEpoch(todayYear, todayMonth, todayDay)
        expiryDays - todayDays <= 7
    }.getOrDefault(false)
}

/**
 * Small warning chip shown when an estimate expires within 7 days.
 *
 * Animation: gentle 1-second alpha pulse to draw attention.
 * ReduceMotion: when the system "Remove Animations" accessibility toggle is on,
 * the chip renders static (alpha = 1f) — no animation.
 */
@Composable
fun ExpiringSoonChip(
    daysRemaining: Int,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val reduceMotion = android.provider.Settings.Global.getFloat(
        context.contentResolver,
        "transition_animation_scale",
        1f,
    ) == 0f

    val alpha by if (reduceMotion) {
        // Static — no composition overhead
        androidx.compose.runtime.remember { androidx.compose.runtime.mutableFloatStateOf(1f) }.let {
            object {
                val value get() = it.floatValue
            }
        }
        // Fallback via simple state
        @Suppress("UNCHECKED_CAST")
        (androidx.compose.runtime.remember { androidx.compose.runtime.mutableFloatStateOf(1f) } as androidx.compose.runtime.State<Float>)
    } else {
        val transition = rememberInfiniteTransition(label = "expiring-pulse")
        transition.animateFloat(
            initialValue = 1f,
            targetValue = 0.45f,
            animationSpec = infiniteRepeatable(
                animation = tween(durationMillis = 900, easing = LinearEasing),
                repeatMode = RepeatMode.Reverse,
            ),
            label = "expiring-alpha",
        )
    }

    val label = when {
        daysRemaining <= 0 -> "Expired"
        daysRemaining == 1 -> "Expires tomorrow"
        else -> "Expires in $daysRemaining days"
    }

    CompositionLocalProvider(LocalMinimumInteractiveComponentSize provides Dp.Unspecified) {
        SuggestionChip(
            onClick = {},
            label = {
                Text(
                    label,
                    style = MaterialTheme.typography.labelSmall,
                    modifier = Modifier.padding(horizontal = 2.dp),
                )
            },
            modifier = modifier
                .alpha(alpha)
                .semantics { contentDescription = label },
            colors = SuggestionChipDefaults.suggestionChipColors(
                containerColor = MaterialTheme.colorScheme.errorContainer,
                labelColor = MaterialTheme.colorScheme.onErrorContainer,
            ),
            border = null,
        )
    }
}
