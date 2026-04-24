package com.bizarreelectronics.crm.ui.screens.tv

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.remote.api.TvQueueItem
import kotlinx.coroutines.delay

// Brand palette constants for the TV board — deep dark background, accent purple.
private val TvBackground   = Color(0xFF0D0D1A)
private val TvSurface      = Color(0xFF1A1A2E)
private val TvBrandPurple  = Color(0xFF7C3AED)
private val TvTextPrimary  = Color(0xFFF5F5FF)
private val TvTextSecondary = Color(0xFFB0B0CC)

/** Status dot colour per group, visible at distance. */
private val TvGroupColor = mapOf(
    TvQueueGroup.IN_PROGRESS to Color(0xFF22D3EE),
    TvQueueGroup.AWAITING    to Color(0xFFFBBF24),
    TvQueueGroup.READY       to Color(0xFF34D399),
)

/**
 * §3.13 L565–L567 — Full-screen in-shop TV queue board.
 *
 * ## Layout
 * Title bar "Today's queue" + auto-refreshing [LazyColumn] of tickets
 * grouped by status (In Progress / Awaiting / Ready for Pickup).  Each
 * row shows a large animated status dot, customer name, ticket number,
 * and device description in large readable type suitable for a wall-
 * mounted display.
 *
 * ## Keep-awake
 * Sets `view.keepScreenOn = true` for the lifetime of the composable so
 * the display never dims while the board is active.
 *
 * ## Auto-refresh
 * A [LaunchedEffect] loop calls [TvQueueBoardViewModel.refresh] every 30 s.
 *
 * ## Exit gesture (3-finger tap)
 * Three simultaneous pointer contacts detected via [pointerInput] trigger
 * [onExitRequest].  A fading "Exit" hint visible for 3 s in the bottom-
 * right corner makes the gesture discoverable without cluttering the board.
 * On ChromeOS / keyboards, the hardware Escape key also calls [onExitRequest]
 * via the [androidx.compose.ui.input.key.KeyEvent] handler wired by the
 * caller (AppNavGraph handles key events at the activity layer and translates
 * Escape → popBackStack for full-screen routes).
 *
 * @param onExitRequest Called when the 3-finger gesture is detected. The
 *   caller (AppNavGraph) navigates to PinLockScreen; on PIN success it pops
 *   back to Dashboard.
 */
@Composable
fun TvQueueBoardScreen(
    onExitRequest: () -> Unit,
    viewModel: TvQueueBoardViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()

    // --- Keep screen on for the entire lifetime of this composable ---
    val view = LocalView.current
    DisposableEffect(view) {
        val previous = view.keepScreenOn
        view.keepScreenOn = true
        onDispose { view.keepScreenOn = previous }
    }

    // --- Auto-refresh every 30 s ---
    LaunchedEffect(Unit) {
        while (true) {
            delay(30_000L)
            viewModel.refresh()
        }
    }

    // --- Exit hint: visible for 3 s then fades out ---
    var showExitHint by remember { mutableStateOf(true) }
    LaunchedEffect(Unit) {
        delay(3_000L)
        showExitHint = false
    }

    // --- 3-finger tap detection ---
    // Count simultaneous pointer contacts; when 3+ are pressed simultaneously
    // invoke onExitRequest so the caller can route to the PIN lock screen.
    val pointerCount = remember { mutableIntStateOf(0) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    colors = listOf(TvBackground, TvSurface),
                ),
            )
            // §3.13 — 3-finger tap exit gesture.
            // Each pointer-down increments a count; when the count reaches 3
            // onExitRequest is fired. The count resets on any pointer-up event
            // so brief mis-taps don't accumulate across separate gestures.
            .pointerInput(Unit) {
                detectTapGestures(
                    onPress = {
                        // detectTapGestures only sees one pointer at a time on
                        // the standard API. We use a raw pointer counter instead.
                    },
                )
            }
            .pointerInput(Unit) {
                awaitPointerEventScope {
                    while (true) {
                        val event = awaitPointerEvent()
                        val pressed = event.changes.count { it.pressed }
                        pointerCount.intValue = pressed
                        if (pressed >= 3) {
                            // Consume all changes to prevent accidental taps
                            // on list items during the gesture.
                            event.changes.forEach { it.consume() }
                            onExitRequest()
                        }
                    }
                }
            },
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 32.dp, vertical = 24.dp),
        ) {
            // --- Title bar ---
            TvTitleBar()

            Spacer(Modifier.height(24.dp))

            when {
                uiState.isLoading -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = TvBrandPurple)
                    }
                }

                uiState.isEmpty -> {
                    TvEmptyState()
                }

                else -> {
                    TvGroupedList(groups = uiState.groups)
                }
            }
        }

        // --- Fading "Exit" hint in the bottom-right corner ---
        AnimatedVisibility(
            visible = showExitHint,
            exit = fadeOut(animationSpec = tween(600)),
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(24.dp),
        ) {
            Text(
                text = "Tap with 3 fingers to exit",
                color = TvTextSecondary.copy(alpha = 0.7f),
                style = MaterialTheme.typography.labelMedium,
            )
        }

        // --- Transient error overlay (non-blocking) ---
        if (uiState.error != null) {
            Text(
                text = uiState.error!!,
                color = Color(0xFFFC8181),
                style = MaterialTheme.typography.labelSmall,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 12.dp, end = 16.dp),
            )
        }
    }
}

@Composable
private fun TvTitleBar() {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Column {
            Text(
                text = "Today's queue",
                color = TvTextPrimary,
                fontWeight = FontWeight.Bold,
                fontSize = 36.sp,
            )
            Text(
                text = "Bizarre Electronics — Repair Status",
                color = TvBrandPurple,
                fontSize = 14.sp,
            )
        }
    }

    HorizontalDivider(
        color = TvBrandPurple.copy(alpha = 0.4f),
        thickness = 1.dp,
        modifier = Modifier.padding(top = 16.dp),
    )
}

@Composable
private fun TvGroupedList(groups: Map<TvQueueGroup, List<TvQueueItem>>) {
    LazyColumn(verticalArrangement = Arrangement.spacedBy(32.dp)) {
        groups.forEach { (group, items) ->
            if (items.isNotEmpty()) {
                item(key = group.name) {
                    Text(
                        text = group.label,
                        color = TvGroupColor[group] ?: TvTextPrimary,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 20.sp,
                        modifier = Modifier.padding(bottom = 8.dp),
                    )
                }
                items(items = items, key = { it.id }) { ticket ->
                    TvTicketRow(ticket = ticket, group = group)
                }
            }
        }
        // Bottom breathing room above the hint text.
        item { Spacer(Modifier.height(48.dp)) }
    }
}

@Composable
private fun TvTicketRow(ticket: TvQueueItem, group: TvQueueGroup) {
    val dotColor = TvGroupColor[group] ?: TvTextPrimary

    // Animated pulse on the status dot so the board feels alive.
    val infiniteTransition = rememberInfiniteTransition(label = "dot-pulse-${ticket.id}")
    val alpha by infiniteTransition.animateFloat(
        initialValue = 0.5f,
        targetValue = 1.0f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 1_200, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "dot-alpha-${ticket.id}",
    )

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = TvSurface),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            // Animated status dot
            Box(
                modifier = Modifier
                    .size(16.dp)
                    .clip(CircleShape)
                    .background(dotColor.copy(alpha = alpha)),
            )

            // Customer name — largest element; readable from metres away
            Text(
                text = ticket.customerName,
                color = TvTextPrimary,
                fontWeight = FontWeight.SemiBold,
                fontSize = 26.sp,
                modifier = Modifier.weight(1f),
            )

            // Device
            Text(
                text = ticket.device,
                color = TvTextSecondary,
                fontSize = 20.sp,
                modifier = Modifier.weight(1f),
            )

            // Ticket number
            Text(
                text = "#${ticket.ticketNumber}",
                color = TvBrandPurple,
                fontWeight = FontWeight.Medium,
                fontSize = 20.sp,
            )
        }
    }
}

@Composable
private fun TvEmptyState() {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = "No tickets in queue",
                color = TvTextPrimary,
                fontWeight = FontWeight.SemiBold,
                fontSize = 28.sp,
            )
            Text(
                text = "Connect TV mode to display queue.\nGo to Settings → Display → Activate queue board.",
                color = TvTextSecondary,
                fontSize = 16.sp,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
        }
    }
}
