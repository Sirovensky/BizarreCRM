package com.bizarreelectronics.crm.ui.components

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
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bizarreelectronics.crm.util.RateLimiter

/**
 * Thin banner surfaced near the top of the root scaffold when the rate-limiter
 * queue is sustained above [RateLimiter.SLOW_DOWN_QUEUE_DEPTH] (ActionPlan §1 L257).
 *
 * Collects [RateLimiter.queueState] via [collectAsStateWithLifecycle]. Renders nothing
 * when `slowDownBannerActive = false`. When true, shows a tonal surface with:
 *
 *   [clock icon] The server is limiting requests. Retrying automatically…
 *
 * The message is informational — the rate limiter handles retries itself; the
 * user does not need a Retry button here. The banner disappears once the queue
 * drains below the threshold.
 *
 * Caller wires once in the root scaffold (mounting deferred to a later wave).
 *
 * @param rateLimiter   [RateLimiter] singleton; state is collected as a lifecycle-
 *                      aware flow so updates stop when the host is paused.
 * @param modifier      Applied to the banner row.
 * @param reduceMotion  When true, the slide-in/out animation is replaced with an
 *                      instant cut (no translate). Callers should derive this from
 *                      [com.bizarreelectronics.crm.util.ReduceMotion].
 */
@Composable
fun RateLimitBanner(
    rateLimiter: RateLimiter,
    modifier: Modifier = Modifier,
    reduceMotion: Boolean = false,
) {
    val queue by rateLimiter.queueState.collectAsStateWithLifecycle()

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
        visible = queue.slowDownBannerActive,
        enter = enterAnim,
        exit = exitAnim,
    ) {
        val pendingLabel = "(${queue.depth} pending)"
        val bannerDescription =
            "Server is limiting requests. Retrying automatically. $pendingLabel"

        Row(
            modifier = modifier
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.tertiaryContainer)
                .padding(horizontal = 12.dp, vertical = 6.dp)
                .semantics(mergeDescendants = true) {
                    liveRegion = LiveRegionMode.Polite
                    contentDescription = bannerDescription
                },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(
                imageVector = Icons.Default.Schedule,
                contentDescription = null, // merged into parent semantics
                tint = MaterialTheme.colorScheme.onTertiaryContainer,
                modifier = Modifier.size(18.dp),
            )

            Text(
                text = "The server is limiting requests. Retrying automatically\u2026 $pendingLabel",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onTertiaryContainer,
                modifier = Modifier.weight(1f),
            )
        }
    }
}
