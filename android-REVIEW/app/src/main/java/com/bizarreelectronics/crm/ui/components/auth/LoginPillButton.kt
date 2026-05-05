package com.bizarreelectronics.crm.ui.components.auth

import android.provider.Settings
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/**
 * Shared pill-shaped primary CTA used across all login-flow steps:
 * Connect (server step), Create Shop (register step), Sign In (credentials step),
 * Continue (2FA verify step).
 *
 * Spec:
 *  - 56dp fixed height
 *  - 28dp corner radius (pill)
 *  - fillMaxWidth (caller controls width via [modifier])
 *  - containerColor = colorScheme.primary (cream in dark theme)
 *  - contentColor = colorScheme.onPrimary
 *  - disabled: onSurface @ 0.24f container / 0.48f content
 *  - spinner (20dp, 2dp stroke) when [isLoading]; label (titleMedium semibold) otherwise
 *
 * LOGIN-MOCK-049
 * LOGIN-MOCK-145: explicit ripple color = onPrimary @ 0.24f so the press ripple is
 *   visible on the cream (#FDEED0) container. Default ripple resolves to near-white,
 *   which is imperceptible on the cream surface.
 * LOGIN-MOCK-149: AnimatedContent cross-fade between label and spinner eliminates
 *   the hard-cut pop when isLoading changes.
 */
@Composable
fun LoginPillButton(
    onClick: () -> Unit,
    enabled: Boolean,
    isLoading: Boolean,
    label: String,
    modifier: Modifier = Modifier,
) {
    // LOGIN-MOCK-088: animate enabled→disabled color transitions over 150ms so the
    // cream→grey flip is a smooth fade rather than an instant cut.
    // Reduce Motion: read ANIMATOR_DURATION_SCALE; collapse to 0ms when disabled.
    val ctx = LocalContext.current
    val colorAnimDuration = remember(ctx) {
        if (Settings.Global.getFloat(
                ctx.contentResolver,
                Settings.Global.ANIMATOR_DURATION_SCALE,
                1f,
            ) == 0f
        ) 0 else 150
    }

    val targetContainerColor = if (enabled) MaterialTheme.colorScheme.primary
                               else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.24f)
    val targetContentColor  = if (enabled) MaterialTheme.colorScheme.onPrimary
                               else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.48f)

    val animatedContainerColor by animateColorAsState(
        targetValue = targetContainerColor,
        animationSpec = tween(durationMillis = colorAnimDuration),
        label = "pill_container_color",
    )
    val animatedContentColor by animateColorAsState(
        targetValue = targetContentColor,
        animationSpec = tween(durationMillis = colorAnimDuration),
        label = "pill_content_color",
    )

    // LOGIN-MOCK-145: override ripple color to onPrimary @ 0.24f so the press is
    // clearly visible on the cream primary container.
    val interactionSource = remember { MutableInteractionSource() }
    CompositionLocalProvider(
        // LOGIN-MOCK-145: use onPrimary as ripple color; default alpha (omitted) is fine
        LocalRippleConfiguration provides RippleConfiguration(
            color = MaterialTheme.colorScheme.onPrimary,
        ),
    ) {
        Button(
            onClick = onClick,
            enabled = enabled,
            interactionSource = interactionSource,
            modifier = modifier
                .fillMaxWidth()
                .height(56.dp),
            shape = RoundedCornerShape(28.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = animatedContainerColor,
                contentColor = animatedContentColor,
                // disabledContainer/Content are overridden by animated values above;
                // keep matching fallbacks here in case the Button ignores enabled=false
                // and falls back to the disabled slot directly.
                disabledContainerColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.24f),
                disabledContentColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.48f),
            ),
        ) {
            // LOGIN-MOCK-149: cross-fade between label and spinner over 150ms.
            AnimatedContent(
                targetState = isLoading,
                transitionSpec = {
                    fadeIn(animationSpec = tween(150)) togetherWith
                        fadeOut(animationSpec = tween(100))
                },
                label = "btn_loading",
            ) { loading ->
                if (loading) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onPrimary,
                    )
                } else {
                    Text(
                        text = label,
                        style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold),
                    )
                }
            }
        }
    }
}
