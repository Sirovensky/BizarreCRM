package com.bizarreelectronics.crm.ui.auth

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Backspace
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.ripple
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * §2.5 PIN lock — numeric keypad Composable.
 *
 * 3×4 grid: 1/2/3 · 4/5/6 · 7/8/9 · (blank)/0/backspace. Each key is a 64dp
 * circle with haptic feedback on tap and a Material ripple. Layout caps the
 * keypad at 320dp wide so it doesn't stretch on tablets/ChromeOS.
 */
@Composable
fun PinKeypad(
    onDigit: (Char) -> Unit,
    onBackspace: () -> Unit,
    enabled: Boolean = true,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .widthIn(max = 320.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        KeyRow(enabled, listOf("1", "2", "3"), onDigit, onBackspace)
        KeyRow(enabled, listOf("4", "5", "6"), onDigit, onBackspace)
        KeyRow(enabled, listOf("7", "8", "9"), onDigit, onBackspace)
        KeyRow(enabled, listOf("", "0", BACKSPACE_KEY), onDigit, onBackspace)
    }
}

@Composable
private fun KeyRow(
    enabled: Boolean,
    keys: List<String>,
    onDigit: (Char) -> Unit,
    onBackspace: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        keys.forEach { label ->
            Box(
                modifier = Modifier
                    .weight(1f)
                    .aspectRatio(1f),
                contentAlignment = Alignment.Center,
            ) {
                when (label) {
                    "" -> Spacer(Modifier) // visual spacer — no interaction
                    BACKSPACE_KEY -> KeyButton(
                        enabled = enabled,
                        onClick = onBackspace,
                        contentDescription = "Backspace",
                    ) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.Backspace,
                            contentDescription = null,
                            tint = LocalContentColor.current,
                        )
                    }
                    else -> KeyButton(
                        enabled = enabled,
                        onClick = { onDigit(label.first()) },
                        contentDescription = label,
                    ) {
                        Text(
                            text = label,
                            style = MaterialTheme.typography.headlineMedium,
                            fontWeight = FontWeight.Medium,
                            color = LocalContentColor.current,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun KeyButton(
    enabled: Boolean,
    onClick: () -> Unit,
    contentDescription: String,
    content: @Composable () -> Unit,
) {
    val haptics = LocalHapticFeedback.current
    val interactionSource = remember { MutableInteractionSource() }
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .aspectRatio(1f)
            .clip(CircleShape)
            .background(
                if (enabled) MaterialTheme.colorScheme.surfaceContainerHigh
                else MaterialTheme.colorScheme.surfaceContainer.copy(alpha = 0.5f)
            )
            .clickable(
                enabled = enabled,
                interactionSource = interactionSource,
                indication = ripple(bounded = true),
            ) {
                haptics.performHapticFeedback(androidx.compose.ui.hapticfeedback.HapticFeedbackType.TextHandleMove)
                onClick()
            }
            .semantics {
                this.contentDescription = contentDescription
                role = Role.Button
            },
        contentAlignment = Alignment.Center,
    ) {
        content()
    }
}

/**
 * Row of dots representing entered digits.
 *
 * Supports:
 *  - Shake animation fired via [shakeTrigger] — increment to retrigger on wrong PIN.
 *  - §2.15 tap-hold reveal: when [revealDigits] is true, filled dots are replaced
 *    with the corresponding digit character from [enteredDigits]. The reveal state
 *    is driven externally by [PinLockViewModel.onPinRevealStart] / [onPinRevealEnd].
 *    The caller applies the [pointerInput] modifier via [modifier].
 *
 * @param entered       Number of digits entered so far.
 * @param length        Total PIN length (number of dot slots).
 * @param shakeTrigger  Increment to trigger the shake animation.
 * @param revealDigits  When true, show actual digit characters instead of filled dots.
 * @param enteredDigits The raw digit string entered so far (used when [revealDigits] is true).
 * @param reduceMotion  §26.4 — when true the shake animation is suppressed; a static red outline
 *                      is shown instead to communicate the wrong-PIN feedback without motion.
 *                      Derive from [com.bizarreelectronics.crm.util.ReduceMotion.isReduceMotion].
 * @param modifier      Applied to the outer container; pass the [pointerInput] reveal modifier here.
 */
@Composable
fun PinDots(
    entered: Int,
    length: Int,
    shakeTrigger: Int = 0,
    revealDigits: Boolean = false,
    enteredDigits: String = "",
    reduceMotion: Boolean = false,
    modifier: Modifier = Modifier,
) {
    // §26.4 — when reduceMotion=false the classic horizontal shake fires.
    // When reduceMotion=true we skip the translate animation entirely and
    // instead show a red rounded-rect border around the dot row so the
    // error is still visible without any displacement.
    val offset = remember { Animatable(0f) }
    val showErrorBorder = reduceMotion && shakeTrigger > 0

    LaunchedEffect(shakeTrigger) {
        if (shakeTrigger == 0) return@LaunchedEffect
        if (reduceMotion) return@LaunchedEffect // §26.4: skip shake; border replaces it
        // Asymmetric 4-stop shake: gives an honest "no" wobble without
        // overselling the rejection.
        val kick = 18f
        listOf(-kick, kick, -kick * 0.6f, kick * 0.4f, 0f).forEach { target ->
            offset.animateTo(target, tween(durationMillis = 50))
        }
    }

    // §26.1 — announce wrong-PIN outcome to TalkBack via liveRegion so
    // users relying on screen readers hear "Wrong PIN" on shake / outline.
    val a11yStateDesc = if (shakeTrigger > 0) "Wrong PIN entered" else ""
    Row(
        modifier = modifier
            .graphicsLayer { translationX = offset.value }
            .then(
                if (showErrorBorder) {
                    // §26.4: static error outline replaces shake when motion is reduced.
                    Modifier.border(
                        width = 2.dp,
                        color = MaterialTheme.colorScheme.error,
                        shape = RoundedCornerShape(12.dp),
                    ).padding(horizontal = 8.dp, vertical = 4.dp)
                } else Modifier,
            )
            .semantics {
                // §26.1 — liveRegion.Assertive so screen readers interrupt
                // whatever they are reading and announce the error immediately.
                liveRegion = LiveRegionMode.Assertive
                stateDescription = a11yStateDesc
            },
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        repeat(length) { index ->
            val filled = index < entered
            if (filled && revealDigits && index < enteredDigits.length) {
                // §2.15 tap-hold reveal: show the actual digit character.
                Text(
                    text = enteredDigits[index].toString(),
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.width(18.dp),
                )
            } else {
                Box(
                    modifier = Modifier
                        .size(18.dp)
                        .clip(CircleShape)
                        .background(
                            if (filled) MaterialTheme.colorScheme.primary
                            else MaterialTheme.colorScheme.outlineVariant
                        ),
                )
            }
        }
    }
}

private const val BACKSPACE_KEY = "\u232B" // ERASE TO THE LEFT — internal sentinel only
