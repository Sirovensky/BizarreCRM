package com.bizarreelectronics.crm.ui.auth

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
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
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
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
 * Row of dots representing entered digits. Supports a shake animation fired
 * via `shakeTrigger` — increment it in the caller to retrigger on wrong PIN.
 */
@Composable
fun PinDots(
    entered: Int,
    length: Int,
    shakeTrigger: Int = 0,
    modifier: Modifier = Modifier,
) {
    val offset = remember { Animatable(0f) }
    LaunchedEffect(shakeTrigger) {
        if (shakeTrigger == 0) return@LaunchedEffect
        // Asymmetric 4-stop shake: gives an honest "no" wobble without
        // overselling the rejection.
        val kick = 18f
        listOf(-kick, kick, -kick * 0.6f, kick * 0.4f, 0f).forEach { target ->
            offset.animateTo(target, tween(durationMillis = 50))
        }
    }
    Row(
        modifier = modifier.graphicsLayer { translationX = offset.value },
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        repeat(length) { index ->
            val filled = index < entered
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

private const val BACKSPACE_KEY = "\u232B" // ERASE TO THE LEFT — internal sentinel only
