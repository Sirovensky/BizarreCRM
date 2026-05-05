package com.bizarreelectronics.crm.ui.components

import android.content.Intent
import android.provider.Settings
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bizarreelectronics.crm.util.ClockDrift
import kotlin.math.abs

/**
 * Sticky banner surfaced near the top of the root scaffold when the device clock
 * drifts more than [ClockDrift.WARN_DRIFT_MS] from the server (ActionPlan §1 L251).
 *
 * Collects [ClockDrift.state] via [collectAsStateWithLifecycle]. Renders nothing
 * when `state.warnThresholdCrossed = false`. When true, shows:
 *
 *   [warning icon] Device clock is off by X minutes.  [Open settings]
 *
 * Tapping "Open settings" fires an Intent to [Settings.ACTION_DATE_SETTINGS].
 *
 * Caller wires once in the root scaffold (TODO: AppNavGraph root Box — a later wave).
 * For now this composable is importable and ready for root mount.
 *
 * @param clockDrift        [ClockDrift] singleton; state is collected as a lifecycle-
 *                          aware flow so updates stop when the host is paused.
 * @param modifier          Applied to the banner row.
 * @param reduceMotion      When true, the slide-in/out animation is replaced with an
 *                          instant cut (no translate). Callers should derive this from
 *                          [com.bizarreelectronics.crm.util.ReduceMotion].
 * @param onOpenDateSettings Optional callback for tests or alternative hosts. When non-null,
 *                          overrides the default [Settings.ACTION_DATE_SETTINGS] intent.
 */
@Composable
fun ClockDriftBanner(
    clockDrift: ClockDrift,
    modifier: Modifier = Modifier,
    reduceMotion: Boolean = false,
    onOpenDateSettings: (() -> Unit)? = null,
) {
    val state by clockDrift.state.collectAsStateWithLifecycle()

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
        visible = state.warnThresholdCrossed,
        enter = enterAnim,
        exit = exitAnim,
    ) {
        val context = LocalContext.current
        val driftText = driftToText(state.driftMs)
        val bannerDescription = "Warning: Device clock is off by $driftText. This may cause sign-in issues."

        Row(
            modifier = modifier
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.errorContainer)
                .padding(horizontal = 12.dp, vertical = 6.dp)
                .semantics(mergeDescendants = true) {
                    liveRegion = LiveRegionMode.Polite
                    contentDescription = bannerDescription
                },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(
                imageVector = Icons.Default.Warning,
                contentDescription = null, // merged into parent semantics
                tint = MaterialTheme.colorScheme.onErrorContainer,
                modifier = Modifier.size(18.dp),
            )

            Text(
                text = "Device clock is off by $driftText. This may cause sign-in issues.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onErrorContainer,
                modifier = Modifier.weight(1f),
            )

            TextButton(
                onClick = {
                    if (onOpenDateSettings != null) {
                        onOpenDateSettings()
                    } else {
                        val intent = Intent(Settings.ACTION_DATE_SETTINGS).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        context.startActivity(intent)
                    }
                },
            ) {
                Text(
                    text = "Open settings",
                    color = MaterialTheme.colorScheme.onErrorContainer,
                    style = MaterialTheme.typography.labelMedium,
                )
            }
        }
    }
}

/**
 * Converts a signed drift in milliseconds to a human-readable string for use in the banner.
 *
 * Examples:
 *   - `150_000L`  →  "2 minutes fast"  (server is 2.5 min ahead of device → device is fast)
 *   - `-190_000L` →  "3 minutes slow"  (server is 3.2 min behind device → device is slow)
 *   - `45_000L`   →  "45 seconds fast"
 *   - `-29_000L`  →  "29 seconds slow"
 *
 * Sign convention (mirrors [ClockDrift]):
 *   driftMs = serverEpochMs − deviceMs
 *   - positive drift → server is ahead → device clock is running slow → label "slow"
 *   - negative drift → device is ahead → device clock is running fast → label "fast"
 *
 * Internal visibility allows direct testing without a Compose environment.
 */
internal fun driftToText(driftMs: Long): String {
    val absDrift = abs(driftMs)
    // positive driftMs means server > device, i.e. device is behind/slow
    val direction = if (driftMs >= 0) "slow" else "fast"

    return if (absDrift >= 60_000L) {
        val minutes = (absDrift / 60_000L).toInt()
        "$minutes ${if (minutes == 1) "minute" else "minutes"} $direction"
    } else {
        val seconds = (absDrift / 1_000L).toInt()
        "$seconds ${if (seconds == 1) "second" else "seconds"} $direction"
    }
}
