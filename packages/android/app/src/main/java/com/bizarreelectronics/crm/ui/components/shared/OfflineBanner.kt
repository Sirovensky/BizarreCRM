package com.bizarreelectronics.crm.ui.components.shared

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.theme.WarningAmber

/**
 * Offline status banner. Appears at the top of the screen when the device
 * has no connectivity.
 *
 * Brand direction (de-yellowed):
 * - Background: `surface1` (`colorScheme.surface`) — calm, not alarming.
 * - Left accent bar: 2dp WarningAmber (`#E8A33D`) — attention signal without screaming.
 * - "OFFLINE" label: Barlow Condensed (`headlineMedium` typography slot) — brand moment.
 * - Body text: muted `onSurfaceVariant` — readable, quiet.
 * - Expand/shrink animation retained.
 *
 * The `#FFD600` yellow fill and `#1A1A1A` black text are removed.
 *
 * @param isOffline         When true, the banner is visible.
 * @param pendingSyncCount  Number of pending sync operations (shown in subtitle).
 * @param isSyncing         When true, shows a "Syncing..." subtitle.
 */
@Composable
fun OfflineBanner(
    isOffline: Boolean,
    pendingSyncCount: Int = 0,
    isSyncing: Boolean = false,
) {
    AnimatedVisibility(
        visible = isOffline,
        enter = fadeIn(animationSpec = tween(durationMillis = 200)),
        exit = fadeOut(animationSpec = tween(durationMillis = 200)),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.surface), // surface1 bg
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // 2dp WarningAmber left accent bar
            Box(
                modifier = Modifier
                    .width(2.dp)
                    .height(IntrinsicSize.Max)
                    .background(WarningAmber),
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
                ) {
                    Icon(
                        Icons.Default.WifiOff,
                        contentDescription = "Offline",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(18.dp),
                    )
                    Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                        // "Offline" in Barlow Condensed (headlineMedium slot from Wave 1 Typography)
                        Text(
                            "Offline",
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
