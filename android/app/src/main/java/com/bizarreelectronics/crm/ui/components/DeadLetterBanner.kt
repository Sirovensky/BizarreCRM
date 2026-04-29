package com.bizarreelectronics.crm.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.theme.LocalExtendedColors

/**
 * §20.7 — Persistent banner shown on a screen when one or more of that screen's
 * entities are stuck in the dead-letter sync queue.
 *
 * Shown above the screen's content (below the top app bar). Vanishes automatically
 * once the count drops to zero (user retried, or the entry was discarded by the
 * 30-day purge).
 *
 * ## Usage
 *
 * ```kotlin
 * // In a screen Composable that hosts tickets:
 * val deadLetterCount by viewModel.deadLetterCount.collectAsState()
 * DeadLetterBanner(
 *     failedCount = deadLetterCount,
 *     entityLabel = "ticket",
 *     onViewIssues = { navController.navigate(Screen.SyncIssues.route) },
 * )
 * ```
 *
 * @param failedCount   Number of dead-letter entries for this screen's entity type.
 *                      When 0, the banner is hidden.
 * @param entityLabel   Singular human label for the entity, e.g. `"ticket"`,
 *                      `"customer"`, `"item"`. Used to form the copy
 *                      "1 ticket failed to sync" / "3 tickets failed to sync".
 * @param onViewIssues  Navigates to Settings → Data → Sync Issues. When null, only
 *                      the count text is shown (no action button).
 */
@Composable
fun DeadLetterBanner(
    failedCount: Int,
    entityLabel: String,
    onViewIssues: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val extColors = LocalExtendedColors.current
    val visible = failedCount > 0

    val noun = if (failedCount == 1) entityLabel else "${entityLabel}s"
    val bannerText = "$failedCount $noun failed to sync"

    AnimatedVisibility(
        visible = visible,
        enter = expandVertically(animationSpec = tween(200)) + fadeIn(animationSpec = tween(200)),
        exit = shrinkVertically(animationSpec = tween(200)) + fadeOut(animationSpec = tween(200)),
        modifier = modifier,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.errorContainer)
                .semantics(mergeDescendants = true) {
                    liveRegion = LiveRegionMode.Polite
                    contentDescription = "$bannerText. Tap to view sync issues."
                },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // 2dp error-color left accent bar — mirrors OfflineBanner's warning bar
            // pattern but uses errorContainer + error accent for severity distinction.
            Box(
                modifier = Modifier
                    .width(2.dp)
                    .height(IntrinsicSize.Max)
                    .background(MaterialTheme.colorScheme.error),
            )

            Row(
                modifier = Modifier
                    .weight(1f)
                    .padding(horizontal = 14.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.weight(1f),
                ) {
                    Icon(
                        Icons.Default.Error,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onErrorContainer,
                        modifier = Modifier.size(18.dp),
                    )
                    Text(
                        text = bannerText,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onErrorContainer,
                    )
                }

                if (onViewIssues != null) {
                    TextButton(onClick = onViewIssues) {
                        Icon(
                            Icons.Default.Refresh,
                            contentDescription = null,
                            modifier = Modifier.size(14.dp),
                            tint = MaterialTheme.colorScheme.onErrorContainer,
                        )
                        Text(
                            "View",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onErrorContainer,
                        )
                    }
                }
            }
        }
    }
}
