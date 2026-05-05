package com.bizarreelectronics.crm.ui.screens.dashboard.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * §3.14 L570 — Sticky cached-data banner.
 *
 * Shown when there is a network error but the dashboard has previously-cached
 * data to display. Uses [MaterialTheme.colorScheme.tertiaryContainer] surface
 * so it reads as informational (not critical error) — the data is usable, just
 * stale.
 *
 * ReduceMotion: when [reduceMotion] is true the fade animation is skipped and
 * the banner appears/disappears instantly (zero-duration tween).
 *
 * @param visible          Whether the banner should be shown.
 * @param onRetry          Called when the user taps "Retry".
 * @param reduceMotion     When true, skip enter/exit animation.
 * @param modifier         Applied to the outermost [Surface].
 */
@Composable
fun DashboardCachedBanner(
    visible: Boolean,
    onRetry: () -> Unit,
    reduceMotion: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val animDuration = if (reduceMotion) 0 else 300

    AnimatedVisibility(
        visible = visible,
        enter = fadeIn(animationSpec = tween(durationMillis = animDuration)),
        exit = fadeOut(animationSpec = tween(durationMillis = animDuration)),
        modifier = modifier,
    ) {
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp),
            color = MaterialTheme.colorScheme.tertiaryContainer,
            shape = MaterialTheme.shapes.small,
        ) {
            Row(
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    imageVector = Icons.Default.CloudOff,
                    // decorative — sibling Text carries the announcement
                    contentDescription = null,
                    modifier = Modifier.size(16.dp),
                    tint = MaterialTheme.colorScheme.onTertiaryContainer.copy(alpha = 0.9f),
                )
                Text(
                    text = "Showing cached data.",
                    style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.sp),
                    color = MaterialTheme.colorScheme.onTertiaryContainer.copy(alpha = 0.9f),
                    modifier = Modifier.weight(1f),
                )
                TextButton(
                    onClick = onRetry,
                    modifier = Modifier.padding(0.dp),
                ) {
                    Text(
                        text = "Retry",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onTertiaryContainer,
                    )
                }
            }
        }
    }
}
