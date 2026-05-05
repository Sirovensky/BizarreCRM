package com.bizarreelectronics.crm.ui.components.shared

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.theme.LocalExtendedColors

/**
 * §20.7 — Persistent per-screen banner shown when any sync-queue entry for the current
 * screen's entity type is in the `dead_letter` state.
 *
 * Example (ticket detail screen showing that 1 ticket change failed to sync):
 * ```
 * [!] 1 ticket change failed to sync  →  View sync issues
 * ```
 *
 * ## Usage
 *
 * Collect [deadLetterCount] from [SyncQueueDao.getDeadLetterCount] (or a filtered
 * variant scoped to the entity type) in the ViewModel and pass it here. Pair with
 * [onOpenIssues] to navigate to `SyncIssuesScreen`.
 *
 * ## Design
 * - Background: `errorContainer` (not error itself — error is for critical breakdowns,
 *   errorContainer is the container variant that reads as a warning without screaming).
 * - Left accent bar: 2dp `error` colour — same visual grammar as [OfflineBanner].
 * - Text: `onErrorContainer` for legibility on the container tint.
 * - Tapping the row (or the "View issues" text) fires [onOpenIssues].
 * - Animated in/out at 200 ms so the banner doesn't snap in jarring layout jumps.
 *
 * @param deadLetterCount  Number of dead-letter entries for this screen. Pass 0 to hide.
 * @param entityLabel      Human-readable entity label, singular (e.g. "ticket", "customer").
 * @param onOpenIssues     Callback invoked when the user taps the banner.
 * @param modifier         Optional parent modifier.
 */
@Composable
fun DeadLetterBanner(
    deadLetterCount: Int,
    entityLabel: String,
    onOpenIssues: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val extColors = LocalExtendedColors.current

    AnimatedVisibility(
        visible = deadLetterCount > 0,
        enter = expandVertically(animationSpec = tween(durationMillis = 200)) +
            fadeIn(animationSpec = tween(durationMillis = 200)),
        exit = shrinkVertically(animationSpec = tween(durationMillis = 200)) +
            fadeOut(animationSpec = tween(durationMillis = 200)),
    ) {
        val label = if (deadLetterCount == 1) {
            "1 $entityLabel change failed to sync"
        } else {
            "$deadLetterCount $entityLabel changes failed to sync"
        }
        val semanticDesc = "$label. Tap to view sync issues."

        Row(
            modifier = modifier
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.errorContainer)
                .clickable(onClick = onOpenIssues)
                .semantics(mergeDescendants = true) {
                    role = Role.Button
                    liveRegion = LiveRegionMode.Polite
                    contentDescription = semanticDesc
                },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // 2dp error-colour left accent bar — matches OfflineBanner grammar.
            Box(
                modifier = Modifier
                    .width(2.dp)
                    .fillMaxHeight()
                    .background(MaterialTheme.colorScheme.error),
            )

            Row(
                modifier = Modifier
                    .weight(1f)
                    .padding(horizontal = 14.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    imageVector = Icons.Default.CloudOff,
                    // decorative — row semantics provides the accessible label
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onErrorContainer,
                    modifier = Modifier
                        .size(16.dp)
                        .padding(end = 0.dp),
                )

                Text(
                    text = label,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onErrorContainer,
                    modifier = Modifier
                        .weight(1f)
                        .padding(start = 8.dp),
                )

                Text(
                    text = "View issues",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(start = 8.dp),
                )
            }
        }
    }
}
