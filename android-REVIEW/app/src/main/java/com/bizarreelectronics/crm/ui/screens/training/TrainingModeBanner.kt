package com.bizarreelectronics.crm.ui.screens.training

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Science
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.R

/**
 * §53.1 — Training Mode top-bar banner.
 *
 * Displayed at the top of every screen (above the NavHost) whenever training
 * mode is enabled.  Uses [MaterialTheme.colorScheme.tertiaryContainer] as
 * required by the §53 spec so it is visually distinct from the offline /
 * clock-drift / rate-limit banners without using a hardcoded colour.
 *
 * The banner uses [LiveRegionMode.Polite] so TalkBack announces the mode
 * change without interrupting ongoing speech.
 *
 * @param isTrainingMode  When true the banner is visible.
 * @param reduceMotion    When true the slide animation is replaced with an
 *                        instant fade (matches the app-wide reduce-motion pref).
 */
@Composable
fun TrainingModeBanner(
    isTrainingMode: Boolean,
    reduceMotion: Boolean = false,
) {
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
        visible = isTrainingMode,
        enter = enterAnim,
        exit = exitAnim,
    ) {
        val bannerCd = stringResource(R.string.training_mode_banner_cd)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.tertiaryContainer)
                .padding(horizontal = 12.dp, vertical = 6.dp)
                .semantics(mergeDescendants = true) {
                    liveRegion = LiveRegionMode.Polite
                    contentDescription = bannerCd
                },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(
                Icons.Default.Science,
                // merged into parent semantics row
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onTertiaryContainer,
                modifier = Modifier.size(16.dp),
            )
            Text(
                text = stringResource(R.string.training_mode_banner_label),
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onTertiaryContainer,
                modifier = Modifier.weight(1f),
            )
        }
    }
}
