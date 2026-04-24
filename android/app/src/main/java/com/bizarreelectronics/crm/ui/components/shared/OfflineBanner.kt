package com.bizarreelectronics.crm.ui.components.shared

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.theme.LocalExtendedColors

/**
 * Offline status banner. Appears at the top of the screen when the device
 * has no connectivity (ActionPlan §1, L166).
 *
 * Brand direction (de-yellowed):
 * - Background: `surface1` (`colorScheme.surface`) — calm, not alarming.
 * - Left accent bar: 2dp WarningAmber (`#E8A33D`) — attention signal without screaming.
 * - "Offline" label: Barlow Condensed (`headlineMedium` typography slot) — brand moment.
 * - Body text: muted `onSurfaceVariant` — readable, quiet.
 * - Retry button: invokes [onRetry] lambda when tapped.
 * - Smooth fade-in/out; reduced-motion mode replaces slide with instant cut.
 *
 * @param isOffline         When true, the banner is visible.
 * @param pendingSyncCount  Number of pending sync operations (shown in subtitle).
 * @param isSyncing         When true, shows a "Syncing..." subtitle.
 * @param onRetry           Optional callback for the Retry button. When null, the button
 *                          is hidden (backwards-compatible with existing call sites).
 * @param reduceMotion      When true, slide-in/out animation is replaced with instant
 *                          fade (no translate). Derive from
 *                          [com.bizarreelectronics.crm.util.ReduceMotion.isReduceMotion].
 */
@Composable
fun OfflineBanner(
    isOffline: Boolean,
    pendingSyncCount: Int = 0,
    isSyncing: Boolean = false,
    onRetry: (() -> Unit)? = null,
    reduceMotion: Boolean = false,
) {
    val extColors = LocalExtendedColors.current

    val enterAnim = if (reduceMotion) {
        fadeIn(animationSpec = tween(durationMillis = 0))
    } else {
        expandVertically(animationSpec = tween(durationMillis = 200)) +
            fadeIn(animationSpec = tween(durationMillis = 200))
    }
    val exitAnim = if (reduceMotion) {
        fadeOut(animationSpec = tween(durationMillis = 0))
    } else {
        shrinkVertically(animationSpec = tween(durationMillis = 200)) +
            fadeOut(animationSpec = tween(durationMillis = 200))
    }

    AnimatedVisibility(
        visible = isOffline,
        enter = enterAnim,
        exit = exitAnim,
    ) {
        val bannerDescription = buildString {
            append("Offline — showing cached data.")
            if (isSyncing) append(" Syncing.")
            else if (pendingSyncCount > 0) append(" $pendingSyncCount changes pending sync.")
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.surface) // surface1 bg
                .semantics(mergeDescendants = true) {
                    liveRegion = LiveRegionMode.Polite
                    contentDescription = bannerDescription
                },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // 2dp warning-color left accent bar (AND-036: via LocalExtendedColors)
            Box(
                modifier = Modifier
                    .width(2.dp)
                    .height(IntrinsicSize.Max)
                    .background(extColors.warning),
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
                        Icons.Default.WifiOff,
                        contentDescription = null, // merged into parent semantics
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(18.dp),
                    )
                    Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                        // "Offline — showing cached data" message
                        Text(
                            "Offline \u2014 showing cached data",
                            style = MaterialTheme.typography.headlineMedium,
                            color = MaterialTheme.colorScheme.onSurface,
                        )
                        // Subtitle in muted body-sans
                        when {
                            isSyncing -> {
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                                ) {
                                    Icon(
                                        Icons.Default.Sync,
                                        // decorative — sibling "Syncing…" Text
                                        // provides the accessible name (D5-1)
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                        modifier = Modifier.size(12.dp),
                                    )
                                    Text(
                                        "Syncing\u2026",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                            pendingSyncCount > 0 -> {
                                Text(
                                    "$pendingSyncCount change${if (pendingSyncCount != 1) "s" else ""} pending sync",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                }

                // Retry button — only shown when a retry callback is provided.
                if (onRetry != null) {
                    TextButton(onClick = onRetry) {
                        Icon(
                            Icons.Default.Refresh,
                            contentDescription = null, // merged into parent semantics
                            modifier = Modifier.size(14.dp),
                            tint = MaterialTheme.colorScheme.primary,
                        )
                        Spacer(Modifier.width(4.dp))
                        Text(
                            "Retry",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun SyncIndicator(isSyncing: Boolean) {
    AnimatedVisibility(
        visible = isSyncing,
        enter = fadeIn(animationSpec = tween(durationMillis = 200)),
        exit = fadeOut(animationSpec = tween(durationMillis = 200)),
    ) {
        Icon(
            Icons.Default.Sync,
            contentDescription = "Syncing",
            modifier = Modifier.size(20.dp),
            tint = MaterialTheme.colorScheme.primary,
        )
    }
}
