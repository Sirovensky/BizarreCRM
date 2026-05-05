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
import androidx.compose.foundation.layout.Row
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
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import com.bizarreelectronics.crm.util.HapticEvent
import com.bizarreelectronics.crm.util.LocalAppHapticController
import kotlin.random.Random

/**
 * §36.5 — One-shot onboarding milestone celebration modal.
 *
 * Fires exactly once per [MilestoneCelebration] event on this device. Copy +
 * emoji differ per milestone type, but all share the same confetti animation
 * from [CelebratoryModal]'s particle system (re-implemented here for
 * self-containment and milestone-specific colour accent).
 *
 * **Show logic**: Controlled by [DashboardViewModel.pendingMilestone].
 * The ViewModel calls [AppPreferences.hasCelebratedFirst*] before setting the
 * flag and marks each pref true on dismissal so the modal never repeats.
 *
 * **Confetti**: 35 coloured rectangles + milestone-specific accent colour.
 * When [reduceMotion] is true, replaced by a large static milestone emoji.
 *
 * **Navigation CTA**: [onNavigate] optional deep-link (e.g. to Tickets list
 * for FIRST_TICKET). If null, only the Dismiss button is shown.
 *
 * @param milestone     Which milestone is being celebrated. Drives copy + emoji.
 * @param visible       Whether to show the sheet.
 * @param onDismiss     Called when user taps "Dismiss" or swipes away.
 * @param onNavigate    Optional: navigate to the relevant screen from the CTA.
 * @param reduceMotion  From [rememberReduceMotion]. True → static emoji fallback.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MilestoneCelebrationModal(
    milestone: MilestoneCelebration,
    visible: Boolean,
    onDismiss: () -> Unit,
    onNavigate: (() -> Unit)? = null,
    reduceMotion: Boolean,
) {
    if (!visible) return

    val hapticCtrl = LocalAppHapticController.current
    LaunchedEffect(Unit) {
        hapticCtrl?.fire(HapticEvent.Celebration)
    }

    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        modifier = Modifier.semantics {
            contentDescription = "${milestone.accessibilityLabel} celebration"
        },
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp, vertical = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // Confetti / static fallback area
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(130.dp),
                contentAlignment = Alignment.Center,
            ) {
                if (reduceMotion) {
                    Text(text = milestone.emoji, fontSize = 64.sp)
                } else {
                    MilestoneConfettiAnimation(accentColor = milestone.accentColor)
                    Text(text = milestone.emoji, fontSize = 52.sp)
                }
            }

            Text(
                text = milestone.headline,
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
                color = MaterialTheme.colorScheme.onSurface,
            )

            Text(
                text = milestone.body,
                style = MaterialTheme.typography.bodyMedium,
                textAlign = TextAlign.Center,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Spacer(modifier = Modifier.height(4.dp))

            if (onNavigate != null) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    OutlinedButton(
                        onClick = onDismiss,
                        modifier = Modifier.weight(1f),
                    ) {
                        Text("Dismiss")
                    }
                    Button(
                        onClick = {
                            onDismiss()
                            onNavigate()
                        },
                        modifier = Modifier.weight(1f),
                    ) {
                        Text(milestone.ctaLabel)
                    }
                }
            } else {
                Button(
                    onClick = onDismiss,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Let's go!")
                }
            }

            Spacer(modifier = Modifier.height(8.dp))
        }
    }
}

// ---------------------------------------------------------------------------
// Milestone enum — drives copy, emoji, and confetti accent colour
// ---------------------------------------------------------------------------

/**
 * §36.5 — Each value represents one trackable first-time event on this device.
 *
 * Properties are baked in as `val` on the enum entries to keep the display logic
 * co-located with the enum rather than scattered across composable call-sites.
 */
enum class MilestoneCelebration(
    /** Short celebratory headline. */
    val headline: String,
    /** One-sentence supportive body copy. */
    val body: String,
    /** Large emoji shown above the headline. */
    val emoji: String,
    /** Label for the optional navigation CTA. */
    val ctaLabel: String,
    /** Confetti accent colour woven into the particle mix. */
    val accentColor: Color,
    /** TalkBack label for the modal. */
    val accessibilityLabel: String,
) {
    FIRST_TICKET(
        headline = "First ticket created!",
        body = "Your first repair job is in the system. Keep the momentum going.",
        emoji = "🔧", // 🔧
        ctaLabel = "View Ticket",
        accentColor = Color(0xFF4D96FF),
        accessibilityLabel = "First ticket",
    ),
    FIRST_SALE(
        headline = "First sale — congratulations!",
        body = "You just made your first sale. The register is ringing.",
        emoji = "💰", // 💰
        ctaLabel = "View Invoice",
        accentColor = Color(0xFF6BCB77),
        accessibilityLabel = "First sale",
    ),
    FIRST_CUSTOMER(
        headline = "First customer added!",
        body = "Your first customer is on record. Every business starts with one.",
        emoji = "👋", // 👋
        ctaLabel = "View Customer",
        accentColor = Color(0xFFC77DFF),
        accessibilityLabel = "First customer",
    ),
}

// ---------------------------------------------------------------------------
// Milestone confetti — same particle approach as ConfettiAnimation, with an
// injected accent colour woven in alongside the standard palette.
// ---------------------------------------------------------------------------

private val milestoneConfettiBase = listOf(
    Color(0xFFFF6B6B), Color(0xFFFFD93D), Color(0xFF6BCB77),
    Color(0xFF4D96FF), Color(0xFFC77DFF), Color(0xFFFF9F1C),
)

@Composable
private fun MilestoneConfettiAnimation(accentColor: Color) {
    val colors = remember(accentColor) {
        milestoneConfettiBase + accentColor
    }
    val particles = remember(accentColor) {
        List(35) { i ->
            MilestoneConfettiParticle(
                xFraction = Random(seed = i * 23).nextFloat(),
                startYFraction = Random(seed = i * 37).nextFloat() * -0.6f,
                size = 5.dp + (Random(seed = i * 11).nextFloat() * 9).dp,
                color = colors[i % colors.size],
                durationMs = 1100 + Random(seed = i * 17).nextInt(900),
                delayMs = Random(seed = i * 29).nextInt(500),
            )
        }
    }

    val infiniteTransition = rememberInfiniteTransition(label = "milestone_confetti")

    Box(modifier = Modifier.fillMaxWidth().height(130.dp)) {
        particles.forEach { p ->
            val offsetY by infiniteTransition.animateFloat(
                initialValue = p.startYFraction * 130f,
                targetValue = 130f,
                animationSpec = infiniteRepeatable(
                    animation = tween(
                        durationMillis = p.durationMs,
                        delayMillis = p.delayMs,
                        easing = LinearEasing,
                    ),
                    repeatMode = RepeatMode.Restart,
                ),
                label = "milestone_confetti_y_${p.durationMs}",
            )
            Box(
                modifier = Modifier
                    .offset(x = (p.xFraction * 360).dp, y = offsetY.dp)
                    .size(p.size)
                    .clip(MaterialTheme.shapes.extraSmall)
                    .background(p.color),
            )
        }
    }
}

private data class MilestoneConfettiParticle(
    val xFraction: Float,
    val startYFraction: Float,
    val size: androidx.compose.ui.unit.Dp,
    val color: Color,
    val durationMs: Int,
    val delayMs: Int,
)
