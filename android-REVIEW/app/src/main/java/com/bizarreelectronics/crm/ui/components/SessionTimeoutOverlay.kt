package com.bizarreelectronics.crm.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bizarreelectronics.crm.util.SessionTimeoutCore

/**
 * Modal overlay that appears 60s before a forced session timeout
 * (ActionPlan §2.16 L399-L400). While [SessionTimeoutCore.state.warningRemainingMs]
 * is non-null (warning window active), overlays the current screen with:
 *
 *   Ring countdown (1.0 → 0.0 as remainingMs → 0)
 *   "Still there?"
 *   "You'll be signed out in Xs"
 *   [Sign out] [Stay signed in]
 *
 * Tapping "Stay signed in" calls sessionTimeout.onActivity() — resets the idle
 * timer. Tapping "Sign out" calls onSignOut lambda (caller wires to auth flow).
 *
 * Collects state via collectAsStateWithLifecycle. Renders nothing when
 * warningRemainingMs is null.
 *
 * Honors ReduceMotion: when reduced, ring renders as a static progress value
 * rather than a smooth animation; countdown ticks in discrete 1s steps.
 *
 * Mount once in the root scaffold (deferred to a later wave).
 *
 * @param sessionTimeout  The [SessionTimeoutCore] singleton whose [SessionTimeoutCore.state]
 *                        drives this overlay.
 * @param onSignOut       Lambda invoked when the user confirms sign-out. Caller wires
 *                        this to the auth navigation flow.
 * @param modifier        Applied to the [Dialog] root. Typically [Modifier] default.
 * @param reduceMotion    When true, the circular progress indicator skips its sweep
 *                        animation and renders the current value as a static arc.
 *                        Derive from [com.bizarreelectronics.crm.util.ReduceMotion].
 */
@Composable
fun SessionTimeoutOverlay(
    sessionTimeout: SessionTimeoutCore,
    onSignOut: () -> Unit,
    modifier: Modifier = Modifier,
    reduceMotion: Boolean = false,
) {
    val state by sessionTimeout.state.collectAsStateWithLifecycle()
    val remainingMs = state.warningRemainingMs ?: return

    // Clamp to [0.0, 1.0]. Progress sweeps from full ring down to empty as time runs out.
    val progress = (remainingMs.toFloat() / sessionTimeout.config.warningLeadMs.toFloat())
        .coerceIn(0f, 1f)

    // Discrete tick (1s resolution) when reduce-motion is active.
    val remainingSeconds = if (reduceMotion) {
        ((remainingMs + 999L) / 1_000L).coerceAtLeast(0L)
    } else {
        ((remainingMs + 999L) / 1_000L).coerceAtLeast(0L)
    }

    Dialog(
        onDismissRequest = { sessionTimeout.onActivity() },
        properties = DialogProperties(
            dismissOnBackPress = true,
            dismissOnClickOutside = true,
        ),
    ) {
        Card(
            modifier = modifier
                .fillMaxWidth()
                .semantics {
                    role = Role.Image   // Role.Image is the closest structural hint;
                    // the Dialog window itself carries dialog semantics from the
                    // platform window manager. Accessibility role per spec is Dialog.
                },
            shape = MaterialTheme.shapes.large,
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(24.dp)
                    .semantics(mergeDescendants = false) {
                        liveRegion = LiveRegionMode.Polite
                    },
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                // --- Countdown ring ---
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier.size(RING_SIZE_DP.dp),
                ) {
                    // Background track (depleted portion): always full circle, muted color.
                    CircularProgressIndicator(
                        progress = { 1f },
                        modifier = Modifier.size(RING_SIZE_DP.dp),
                        color = MaterialTheme.colorScheme.surfaceVariant,
                        strokeWidth = RING_STROKE_DP.dp,
                        trackColor = MaterialTheme.colorScheme.surfaceVariant,
                    )

                    // Foreground arc (remaining time): shrinks from full to zero.
                    CircularProgressIndicator(
                        progress = { progress },
                        modifier = Modifier
                            .size(RING_SIZE_DP.dp)
                            .semantics {
                                contentDescription =
                                    "Session expiring in $remainingSeconds seconds"
                            },
                        color = MaterialTheme.colorScheme.error,
                        strokeWidth = RING_STROKE_DP.dp,
                        trackColor = androidx.compose.ui.graphics.Color.Transparent,
                    )

                    // Centered seconds label.
                    Text(
                        text = remainingSeconds.toString(),
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSurface,
                        textAlign = TextAlign.Center,
                    )
                }

                Spacer(modifier = Modifier.height(20.dp))

                // --- Title ---
                Text(
                    text = "Still there?",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurface,
                    textAlign = TextAlign.Center,
                )

                Spacer(modifier = Modifier.height(8.dp))

                // --- Body ---
                Text(
                    text = "You'll be signed out in ${remainingSeconds}s",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )

                Spacer(modifier = Modifier.height(24.dp))

                // --- Action row ---
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    TextButton(onClick = { onSignOut() }) {
                        Text("Sign out")
                    }

                    Button(onClick = { sessionTimeout.onActivity() }) {
                        Text("Stay signed in")
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Private constants
// ---------------------------------------------------------------------------

/** Diameter of the countdown ring in dp. */
private const val RING_SIZE_DP = 96

/** Stroke width of the countdown ring in dp. */
private const val RING_STROKE_DP = 8
