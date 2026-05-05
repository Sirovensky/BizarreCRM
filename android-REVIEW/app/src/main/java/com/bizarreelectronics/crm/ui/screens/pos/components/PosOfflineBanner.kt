package com.bizarreelectronics.crm.ui.screens.pos.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

/**
 * Full-width banner that appears whenever the device loses connectivity.
 *
 * Wraps [AnimatedVisibility] so it slides in/out smoothly as [isOnline] changes.
 * Announces itself to accessibility services via [LiveRegionMode.Polite] so
 * TalkBack reads the offline state without interrupting ongoing speech.
 *
 * Placement: render this at the top of [PosCartScreen] / [PosTenderScreen],
 * directly below the top app bar.  It collapses to zero height while online,
 * so it imposes no layout cost during normal operation.
 *
 * @param isOnline          True when network/server is reachable.  Banner is
 *   visible when this is **false**.
 * @param pendingSaleCount  Number of sales queued in local storage waiting to
 *   sync once connectivity is restored.
 * @param modifier          Optional modifier passed to the outer [AnimatedVisibility].
 */
@Composable
fun PosOfflineBanner(
    isOnline: Boolean,
    pendingSaleCount: Int,
    modifier: Modifier = Modifier,
) {
    AnimatedVisibility(
        visible = !isOnline,
        enter = expandVertically(),
        exit = shrinkVertically(),
        modifier = modifier,
    ) {
        Surface(
            tonalElevation = 4.dp,
            color = MaterialTheme.colorScheme.tertiaryContainer,
            modifier = Modifier
                .fillMaxWidth()
                .height(48.dp)
                .semantics { liveRegion = LiveRegionMode.Polite },
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 12.dp),
            ) {
                Icon(
                    imageVector = Icons.Filled.WifiOff,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onTertiaryContainer,
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = "Offline · $pendingSaleCount sale(s) queued",
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onTertiaryContainer,
                )
            }
        }
    }
}
