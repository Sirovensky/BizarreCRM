package com.bizarreelectronics.crm.ui.screens.tickets.components

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.service.LiveUpdateNotifier
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import kotlinx.coroutines.delay

/**
 * BenchTimerCard — §4.2 L678
 *
 * Small card widget tracking active bench time for this ticket.
 *
 * - Start button calls [onStart] which should invoke `TicketApi.startBenchTimer`.
 * - Stop button calls [onStop] which should invoke `TicketApi.stopBenchTimer`.
 * - While running, shows a live HH:MM:SS ticker updated every second.
 * - Fires [LiveUpdateNotifier.showLiveUpdate] on each tick so the elapsed
 *   time appears in the notification shade while the app is backgrounded.
 *
 * Notification management: the card allocates a notification ID on start and
 * cancels it on stop via [LiveUpdateNotifier.cancelLiveUpdate].
 *
 * @param ticketId  Ticket ID used in the notification deep-link.
 * @param orderId   Ticket order ID for the notification title.
 * @param isRunning Whether a bench session is currently active (from VM state).
 * @param onStart   Callback fired when the user taps Start.
 * @param onStop    Callback fired when the user taps Stop.
 */
@Composable
fun BenchTimerCard(
    ticketId: Long,
    orderId: String,
    isRunning: Boolean,
    onStart: () -> Unit,
    onStop: () -> Unit,
) {
    val context = LocalContext.current

    // Elapsed seconds since start (reset when stopped)
    var elapsedSeconds by rememberSaveable { mutableLongStateOf(0L) }
    // Notification ID so we can cancel on stop
    var liveNotifId by remember { mutableStateOf<Int?>(null) }

    // Ticker coroutine — runs while isRunning
    LaunchedEffect(isRunning) {
        if (isRunning) {
            while (true) {
                delay(1_000L)
                elapsedSeconds += 1L
                val progressText = formatElapsed(elapsedSeconds)
                val notifId = LiveUpdateNotifier.showLiveUpdate(
                    context = context,
                    title = "Working on #$orderId",
                    progressText = progressText,
                    deepLink = "tickets/$ticketId",
                    existingId = liveNotifId,
                )
                liveNotifId = notifId
            }
        } else {
            // Cancel the live notification when timer is stopped
            liveNotifId?.let { id ->
                LiveUpdateNotifier.cancelLiveUpdate(context, id)
                liveNotifId = null
            }
        }
    }

    BrandCard(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(
                    Icons.Default.Timer,
                    contentDescription = null,
                    tint = if (isRunning) MaterialTheme.colorScheme.primary
                    else MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Column {
                    Text(
                        "Bench Timer",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        if (isRunning) formatElapsed(elapsedSeconds) else "Stopped",
                        style = MaterialTheme.typography.bodyMedium.copy(
                            fontFamily = FontFamily.Monospace,
                            fontWeight = FontWeight.SemiBold,
                        ),
                        modifier = Modifier.semantics {
                            contentDescription = if (isRunning)
                                "Bench timer running: ${formatElapsedSpoken(elapsedSeconds)}"
                            else "Bench timer stopped"
                        },
                    )
                }
            }

            if (isRunning) {
                Button(
                    onClick = {
                        elapsedSeconds = 0L
                        onStop()
                    },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.error,
                    ),
                ) {
                    Icon(Icons.Default.Stop, contentDescription = null)
                    Spacer(modifier = Modifier.width(4.dp))
                    Text("Stop")
                }
            } else {
                Button(onClick = onStart) {
                    Icon(Icons.Default.PlayArrow, contentDescription = null)
                    Spacer(modifier = Modifier.width(4.dp))
                    Text("Start")
                }
            }
        }
    }
}

/** Format seconds as HH:MM:SS */
private fun formatElapsed(seconds: Long): String {
    val h = seconds / 3600
    val m = (seconds % 3600) / 60
    val s = seconds % 60
    return "%02d:%02d:%02d".format(h, m, s)
}

/** Spoken format for accessibility (e.g. "1 hour 2 minutes 5 seconds") */
private fun formatElapsedSpoken(seconds: Long): String {
    val h = seconds / 3600
    val m = (seconds % 3600) / 60
    val s = seconds % 60
    return buildString {
        if (h > 0) append("$h hour${if (h != 1L) "s" else ""} ")
        if (m > 0) append("$m minute${if (m != 1L) "s" else ""} ")
        append("$s second${if (s != 1L) "s" else ""}")
    }.trim()
}
