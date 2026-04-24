package com.bizarreelectronics.crm.ui.screens.dashboard.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.random.Random

/**
 * §3.5 L531 — Celebratory modal shown when the My Queue transitions from
 * non-zero → zero (all queue tickets closed) once per calendar day.
 *
 * **Show logic**: Controlled by [DashboardViewModel.showCelebratoryModal]. The
 * ViewModel gates on [AppPreferences.lastCelebrationDate] vs today's ISO date
 * and only sets the flag true when the queue was previously non-zero. The
 * caller observes [showCelebratoryModal] and passes it here.
 *
 * **Confetti**: 30 coloured rectangles falling with an offset animation driven
 * by [rememberInfiniteTransition]. When [reduceMotion] is true the animation
 * is replaced by a static "\uD83C\uDF89" emoji — no particle rendering.
 *
 * @param visible        Whether to show the sheet. Callers observe the StateFlow.
 * @param onDismiss      Called when user taps "Dismiss" or swipes the sheet away.
 * @param reduceMotion   From [rememberReduceMotion]. True → static emoji, no animation.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CelebratoryModal(
    visible: Boolean,
    onDismiss: () -> Unit,
    reduceMotion: Boolean,
) {
    if (!visible) return

    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        modifier = Modifier.semantics {
            contentDescription = "Queue clear celebration"
        },
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp, vertical = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // Confetti area
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(120.dp),
                contentAlignment = Alignment.Center,
            ) {
                if (reduceMotion) {
                    // Static fallback
                    Text(text = "\uD83C\uDF89", fontSize = 56.sp)
                } else {
                    ConfettiAnimation()
                    // Overlay the party emoji in the centre
                    Text(text = "\uD83C\uDF89", fontSize = 48.sp)
                }
            }

            Text(
                text = "Queue clear! Nice work.",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
                color = MaterialTheme.colorScheme.onSurface,
            )

            Text(
                text = "All your assigned tickets are resolved. Take a breath.",
                style = MaterialTheme.typography.bodyMedium,
                textAlign = TextAlign.Center,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Spacer(modifier = Modifier.height(8.dp))

            Button(
                onClick = onDismiss,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Dismiss")
            }

            Spacer(modifier = Modifier.height(8.dp))
        }
    }
}

// ---------------------------------------------------------------------------
// Confetti particle animation (30 coloured rectangles)
// ---------------------------------------------------------------------------

private val confettiColors = listOf(
    Color(0xFFFF6B6B), Color(0xFFFFD93D), Color(0xFF6BCB77),
    Color(0xFF4D96FF), Color(0xFFC77DFF), Color(0xFFFF9F1C),
)

@Composable
private fun ConfettiAnimation() {
    // Stable per-particle configuration — seeded so recompositions don't shuffle them
    val particles = remember {
        List(30) { i ->
            ConfettiParticle(
                xFraction = Random(seed = i * 17).nextFloat(),
                startYFraction = Random(seed = i * 31).nextFloat() * -0.5f,
                size = 6.dp + (Random(seed = i * 7).nextFloat() * 8).dp,
                color = confettiColors[i % confettiColors.size],
                durationMs = 1200 + Random(seed = i * 13).nextInt(800),
                delayMs = Random(seed = i * 19).nextInt(400),
            )
        }
    }

    val infiniteTransition = rememberInfiniteTransition(label = "confetti")

    Box(modifier = Modifier.fillMaxWidth().height(120.dp)) {
        particles.forEach { p ->
            val offsetY by infiniteTransition.animateFloat(
                initialValue = p.startYFraction * 120f,
                targetValue = 120f,
                animationSpec = infiniteRepeatable(
                    animation = tween(
                        durationMillis = p.durationMs,
                        delayMillis = p.delayMs,
                        easing = LinearEasing,
                    ),
                    repeatMode = RepeatMode.Restart,
                ),
                label = "confetti_y_${p.durationMs}",
            )

            Box(
                modifier = Modifier
                    .offset(
                        x = (p.xFraction * 360).dp,
                        y = offsetY.dp,
                    )
                    .size(p.size)
                    .clip(MaterialTheme.shapes.extraSmall)
                    .background(p.color),
            )
        }
    }
}

private data class ConfettiParticle(
    val xFraction: Float,
    val startYFraction: Float,
    val size: androidx.compose.ui.unit.Dp,
    val color: Color,
    val durationMs: Int,
    val delayMs: Int,
)
