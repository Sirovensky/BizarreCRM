package com.bizarreelectronics.crm.ui.screens.tickets.detail.tablet.cards

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay

/**
 * Tablet ticket-detail Bench Timer card.
 *
 * Shows a tabular monospace clock counting up while the bench timer
 * is running. Cream FAB toggles play / pause. Tech name is shown as
 * a small pill on the right of the section label.
 *
 * The "now" timestamp drives the clock's elapsed display via a 1-second
 * `LaunchedEffect` ticker — only when [isRunning] is true. Idle state
 * shows a static `00:00:00` (or the last accumulated elapsed if the
 * timer was paused; that accumulation lives in the VM, this card only
 * displays).
 *
 * @param isRunning whether the bench timer is actively running.
 * @param techName optional tech display name shown as a pill.
 * @param onStart fires when the play FAB is tapped.
 * @param onStop fires when the pause FAB is tapped.
 */
@Composable
internal fun BenchTimerCard(
    isRunning: Boolean,
    techName: String? = null,
    onStart: () -> Unit = {},
    onStop: () -> Unit = {},
) {
    // Accumulated elapsed across pause/resume cycles for THIS composition.
    // `rememberSaveable` survives recomposition + configuration change but
    // not process death. The server bench_started_at column is the
    // authoritative cross-session source — wire that in a follow-up.
    var accumulatedMs by rememberSaveable { mutableLongStateOf(0L) }
    var anchorMs by rememberSaveable { mutableLongStateOf(0L) }
    var nowMs by remember { mutableLongStateOf(System.currentTimeMillis()) }

    LaunchedEffect(isRunning) {
        if (isRunning) {
            // Resume: anchor to (now - already-accumulated) so the visible
            // clock continues where it stopped.
            anchorMs = System.currentTimeMillis() - accumulatedMs
            while (isRunning) {
                nowMs = System.currentTimeMillis()
                delay(1000L)
            }
        } else if (anchorMs > 0L) {
            // Pause: freeze accumulated to whatever the clock showed.
            accumulatedMs = (System.currentTimeMillis() - anchorMs).coerceAtLeast(0L)
        }
    }

    val elapsedMs = if (isRunning) {
        (nowMs - anchorMs).coerceAtLeast(0L)
    } else {
        accumulatedMs
    }
    val display = remember(elapsedMs) { formatHms(elapsedMs) }

    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp)) {
            // Header: section label + tech pill.
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "Bench Timer",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f),
                )
                if (!techName.isNullOrBlank()) {
                    Surface(
                        color = MaterialTheme.colorScheme.surfaceVariant,
                        shape = CircleShape,
                    ) {
                        Text(
                            "Tech: $techName",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
                        )
                    }
                }
            }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(
                    display,
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.Medium,
                    fontFamily = FontFamily.Monospace,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.weight(1f),
                )
                Surface(
                    color = MaterialTheme.colorScheme.primary,
                    contentColor = MaterialTheme.colorScheme.onPrimary,
                    shape = CircleShape,
                    onClick = if (isRunning) onStop else onStart,
                    modifier = Modifier
                        .size(44.dp)
                        .semantics {
                            contentDescription = if (isRunning) "Stop bench timer"
                            else "Start bench timer"
                        },
                ) {
                    Box(modifier = Modifier.size(44.dp), contentAlignment = Alignment.Center) {
                        Icon(
                            if (isRunning) Icons.Default.Pause else Icons.Default.PlayArrow,
                            contentDescription = null,
                            modifier = Modifier.size(20.dp),
                        )
                    }
                }
            }
        }
    }
}

private fun formatHms(elapsedMs: Long): String {
    val totalSec = elapsedMs / 1000L
    val h = totalSec / 3600L
    val m = (totalSec % 3600L) / 60L
    val s = totalSec % 60L
    return "%02d:%02d:%02d".format(h, m, s)
}
