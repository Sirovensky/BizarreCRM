package com.bizarreelectronics.crm.ui.screens.tickets.detail.tablet

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/**
 * Tablet ticket-detail lifecycle progress strip.
 *
 * Maps the current ticket status name to one of four canonical phases
 * (`Created → In Progress → Ready → Picked up`) and renders an inline
 * dot+label row. The "now" phase pulses gently via an
 * [infiniteRepeatable] tween, matching the M3-Expressive breathing
 * marker in `mockups/android-tablet-ticket-detail.html`.
 *
 * Phase mapping uses substring-keyword matching on the status name
 * because the server's status enum is admin-configurable and varies
 * per tenant. New labels just slot into one of the four buckets via
 * keyword extension below.
 */
@Composable
internal fun LifecycleStrip(currentStatusName: String?) {
    val phase = remember(currentStatusName) {
        val s = currentStatusName.orEmpty().lowercase()
        when {
            "picked" in s || "collected" in s || "closed" in s || "cancelled" in s -> 3
            "repaired" in s || "ready" in s || "qc" in s || "completed" in s -> 2
            "progress" in s || "diagnosis" in s || "waiting" in s || "ordered" in s -> 1
            "created" in s || "new" in s || "open" in s -> 0
            else -> 0
        }
    }

    Surface(
        color = MaterialTheme.colorScheme.surface,
        modifier = Modifier
            .fillMaxWidth()
            .height(34.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            PHASES.forEachIndexed { idx, label ->
                LifecyclePhase(
                    label = label,
                    state = when {
                        idx < phase -> PhaseState.Done
                        idx == phase -> PhaseState.Now
                        else -> PhaseState.Pending
                    },
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}

private enum class PhaseState { Done, Now, Pending }

@Composable
private fun LifecyclePhase(
    label: String,
    state: PhaseState,
    modifier: Modifier = Modifier,
) {
    val isNow = state == PhaseState.Now
    val cream = MaterialTheme.colorScheme.primary
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    val passive = MaterialTheme.colorScheme.surfaceVariant

    val dotColor = when (state) {
        PhaseState.Done -> muted
        PhaseState.Now -> cream
        PhaseState.Pending -> passive
    }
    val textColor = when (state) {
        PhaseState.Done -> muted
        PhaseState.Now -> cream
        PhaseState.Pending -> muted.copy(alpha = 0.5f)
    }

    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(modifier = Modifier.size(10.dp), contentAlignment = Alignment.Center) {
            if (isNow) {
                val transition = rememberInfiniteTransition(label = "phase_pulse")
                val scale by transition.animateFloat(
                    initialValue = 1f,
                    targetValue = 1.6f,
                    animationSpec = infiniteRepeatable(
                        animation = tween(1400),
                        repeatMode = RepeatMode.Reverse,
                    ),
                    label = "scale",
                )
                Surface(
                    color = cream.copy(alpha = 0.25f),
                    shape = CircleShape,
                    modifier = Modifier
                        .size(10.dp)
                        .scale(scale),
                ) {}
            }
            Surface(
                color = dotColor,
                shape = CircleShape,
                modifier = Modifier.size(8.dp),
            ) {}
        }
        Text(
            label.uppercase(),
            style = MaterialTheme.typography.labelSmall,
            color = textColor,
            fontWeight = if (isNow) FontWeight.SemiBold else FontWeight.Normal,
        )
    }
}

private val PHASES = listOf("Created", "In Progress", "Ready", "Picked up")
