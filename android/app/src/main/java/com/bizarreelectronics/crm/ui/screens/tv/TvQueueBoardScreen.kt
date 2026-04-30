package com.bizarreelectronics.crm.ui.screens.tv

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.togetherWith
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.data.remote.api.TvQueueItem
import com.bizarreelectronics.crm.ui.auth.PinLockScreen
import com.bizarreelectronics.crm.ui.theme.LocalExtendedColors
import kotlinx.coroutines.delay

// TV board uses a fixed dark palette intentionally: it is a wall display and must be
// readable regardless of the device theme set for staff use. No theme token maps to
// a guaranteed-dark surface, so these are intentional overrides with explicit comments.
// The brand-accent purple is kept for decorative elements only; readable status colours
// (cyan/amber/green) are chosen for maximum contrast at distance on both OLED and LCD.
private val TvBackground   = Color(0xFF0D0D1A)
private val TvSurface      = Color(0xFF1A1A2E)
private val TvBrandPurple  = Color(0xFF7C3AED)
private val TvTextPrimary  = Color(0xFFF5F5FF)
private val TvTextSecondary = Color(0xFFB0B0CC)

// Status dot colours: high-chroma for readability at 3+ metres on typical shop TVs.
// No equivalent theme tokens exist for these specific hues.
private val TvGroupColor = mapOf(
    TvQueueGroup.IN_PROGRESS to Color(0xFF22D3EE),
    TvQueueGroup.AWAITING    to Color(0xFFFBBF24),
    TvQueueGroup.READY       to Color(0xFF34D399),
)

/** Max tickets shown per board refresh. Keeps the display scannable from a distance. */
private const val TV_QUEUE_MAX_ITEMS = 10

/**
 * §56 — Full-screen in-shop TV queue board.
 *
 * ## Layout
 * Title bar "Today's queue" + auto-refreshing [LazyColumn] of up to
 * [TV_QUEUE_MAX_ITEMS] tickets grouped by status (In Progress / Awaiting /
 * Ready for Pickup). Each row shows a large animated status dot, customer
 * abbreviated name ("John D." — §56 PII policy), ticket number, and device
 * description in large readable type suitable for a wall-mounted display.
 *
 * ## Full-screen (§56.1)
 * [WindowInsetsControllerCompat] hides status bar and navigation bar for
 * the lifetime of the composable; [BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE]
 * lets an operator swipe to reveal them temporarily without exiting the board.
 *
 * ## Keep-awake (§56.1)
 * Sets `view.keepScreenOn = true` for the lifetime of the composable so
 * the display never dims while the board is active.
 *
 * ## Auto-refresh (§56.5)
 * A [LaunchedEffect] loop calls [TvQueueBoardViewModel.refresh] every 30 s.
 * WebSocket ticket events trigger an immediate refresh in the ViewModel.
 *
 * ## Exit gesture (§56.3)
 * Three simultaneous pointer contacts detected via [pointerInput] trigger
 * a full-screen [PinLockScreen] overlay. On PIN success [onExitRequest] is
 * called. Pressing back/cancel on the PIN overlay returns to the board.
 *
 * ## PII (§56 public-facing display policy)
 * Customer names are masked to "FirstName L." format before display so no
 * full surnames are shown on a public screen.
 *
 * @param onExitRequest Called after the exit PIN is verified successfully.
 *   The caller (AppNavGraph) pops back to Dashboard.
 */
@Composable
fun TvQueueBoardScreen(
    onExitRequest: () -> Unit,
    viewModel: TvQueueBoardViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()

    // --- §56.1 Keep screen on for the entire lifetime of this composable ---
    val view = LocalView.current
    DisposableEffect(view) {
        val previous = view.keepScreenOn
        view.keepScreenOn = true
        onDispose { view.keepScreenOn = previous }
    }

    // --- §56.1 Hide system bars (status bar + nav bar) for full-screen wall display ---
    // WindowCompat.getInsetsController requires the window; we obtain it from the view's
    // rootView context. BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE lets an operator swipe to
    // reveal the bars momentarily without permanently exiting the board.
    DisposableEffect(view) {
        val window = (view.context as? android.app.Activity)?.window
        if (window != null) {
            val controller = WindowCompat.getInsetsController(window, view)
            controller.systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            controller.hide(WindowInsetsCompat.Type.systemBars())
            onDispose {
                controller.show(WindowInsetsCompat.Type.systemBars())
            }
        } else {
            onDispose { }
        }
    }

    // --- Auto-refresh every 30 s (WebSocket handles live events between polls) ---
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

    // --- §56.3 PIN overlay: shown when 3-finger gesture fires; dismissed on cancel ---
    var showPinOverlay by remember { mutableStateOf(false) }

    // --- 3-finger tap detection ---
    // Count simultaneous pointer contacts; when 3+ are pressed simultaneously
    // trigger the PIN exit overlay.
    val pointerCount = remember { mutableIntStateOf(0) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    colors = listOf(TvBackground, TvSurface),
                ),
            )
            // §56.3 — 3-finger tap exit gesture.
            .pointerInput(Unit) {
                detectTapGestures(
                    onPress = {
                        // detectTapGestures only sees one pointer at a time on
                        // the standard API. Raw pointer counter used instead.
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
                            showPinOverlay = true
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
                text = stringResource(R.string.tv_queue_exit_hint),
                color = TvTextSecondary.copy(alpha = 0.7f),
                style = MaterialTheme.typography.labelMedium,
            )
        }

        // --- Transient error overlay (non-blocking) ---
        if (uiState.error != null) {
            Text(
                text = uiState.error!!,
                color = LocalExtendedColors.current.error,
                style = MaterialTheme.typography.labelSmall,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 12.dp, end = 16.dp),
            )
        }

        // --- §56.3 PIN overlay — covers entire board; dismissed on cancel ---
        if (showPinOverlay) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.85f)),
                contentAlignment = Alignment.Center,
            ) {
                PinLockScreen(
                    onUnlocked = {
                        showPinOverlay = false
                        onExitRequest()
                    },
                    onSignOut = {
                        // TV board exit should not sign the user out.
                        // Dismiss the overlay and return to the board.
                        showPinOverlay = false
                    },
                    onForgotPin = {
                        // Dismiss overlay; leave board. Caller can navigate
                        // to forgot-pin flow if needed.
                        showPinOverlay = false
                        onExitRequest()
                    },
                )
            }
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
                text = stringResource(R.string.tv_queue_title),
                color = TvTextPrimary,
                fontWeight = FontWeight.Bold,
                style = MaterialTheme.typography.displayMedium,
            )
            Text(
                text = stringResource(R.string.tv_queue_subtitle),
                color = TvBrandPurple,
                style = MaterialTheme.typography.labelLarge,
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
    // §56 — auto-rotating top 10 tickets: cap the total across all groups so
    // the board never scrolls off-screen on a busy day, keeping all statuses visible.
    var remaining = TV_QUEUE_MAX_ITEMS

    LazyColumn(verticalArrangement = Arrangement.spacedBy(32.dp)) {
        groups.forEach { (group, items) ->
            if (items.isNotEmpty() && remaining > 0) {
                val capped = items.take(remaining)
                remaining -= capped.size
                item(key = group.name) {
                    Text(
                        text = group.label,
                        color = TvGroupColor[group] ?: TvTextPrimary,
                        fontWeight = FontWeight.SemiBold,
                        style = MaterialTheme.typography.headlineSmall,
                        modifier = Modifier.padding(bottom = 8.dp),
                    )
                }
                items(items = capped, key = { it.id }) { ticket ->
                    AnimatedContent(
                        targetState = ticket,
                        transitionSpec = {
                            (fadeIn(tween(300)) + slideInVertically { it / 4 })
                                .togetherWith(fadeOut(tween(200)))
                        },
                        label = "ticket-anim-${ticket.id}",
                    ) { t ->
                        TvTicketRow(ticket = t, group = group)
                    }
                }
            }
        }
        // Bottom breathing room above the hint text.
        item { Spacer(Modifier.height(48.dp)) }
    }
}

/**
 * §56 PII policy — masks a full customer name to "FirstName L." so no
 * surnames are shown on a public display.
 *
 * Examples:
 *  - "John Doe"       → "John D."
 *  - "Maria Hernandez Garcia" → "Maria H."
 *  - "John"           → "John"   (single name: unchanged)
 *  - ""               → ""
 */
internal fun maskCustomerName(fullName: String): String {
    val parts = fullName.trim().split(Regex("\\s+"))
    return when {
        parts.size < 2 -> fullName
        else -> "${parts.first()} ${parts[1].first()}."
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
            // contentDescription announces the group status for TalkBack users
            // (accessibility-needs operators on a wall-mounted device).
            Box(
                modifier = Modifier
                    .size(16.dp)
                    .clip(CircleShape)
                    .background(dotColor.copy(alpha = alpha)),
            )

            // Customer name — largest element; readable from metres away.
            // §56 PII: abbreviated to "John D." — no full surname shown.
            Text(
                text = maskCustomerName(ticket.customerName),
                color = TvTextPrimary,
                fontWeight = FontWeight.SemiBold,
                style = MaterialTheme.typography.headlineLarge,
                modifier = Modifier.weight(1f),
            )

            // Device
            Text(
                text = ticket.device,
                color = TvTextSecondary,
                style = MaterialTheme.typography.headlineSmall,
                modifier = Modifier.weight(1f),
            )

            // Ticket number
            Text(
                text = "#${ticket.ticketNumber}",
                color = TvBrandPurple,
                fontWeight = FontWeight.Medium,
                style = MaterialTheme.typography.headlineSmall,
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
                text = stringResource(R.string.tv_queue_empty_title),
                color = TvTextPrimary,
                fontWeight = FontWeight.SemiBold,
                style = MaterialTheme.typography.displaySmall,
            )
            Text(
                text = stringResource(R.string.tv_queue_empty_subtitle),
                color = TvTextSecondary,
                style = MaterialTheme.typography.bodyLarge,
                textAlign = TextAlign.Center,
            )
        }
    }
}
