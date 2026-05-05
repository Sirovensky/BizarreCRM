package com.bizarreelectronics.crm.ui.components.shared

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearWavyProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/**
 * Unified scaffold for the POS-to-Ticket flow (PosEntry → CheckInEntry →
 * CheckInHost → Cart → Tender → Receipt). Locks the visual contract:
 *
 *   ┌──── Top app bar (64dp) — back arrow + title/subtitle stack ─────┐
 *   ├──── LinearWavyProgressIndicator (4dp) — continuous across flow ─┤
 *   │     (Optional CustomerHeaderPill slot below wave — caller-owned)│
 *   │     content                                                     │
 *   ├──── Bottom shelf (72dp) — surface tonal elev1, content slot ────┤
 *   └──────────────────────────────────────────────────────────────────┘
 *
 * Cohesion comes from container shape (height + elevation + padding),
 * not container content. The bottom slot is contextual — search bar on
 * POS Home, CTA pill on flow steps, hint text on read-only screens —
 * but the shelf geometry is constant so the user's eye trains "back is
 * top-left, action is bottom-center" once and never has to re-learn.
 *
 * Step indicator: full POS-to-Ticket flow is 8 logical steps. Caller
 * passes [stepIndex] (0-indexed) and the wave fraction is computed as
 * (stepIndex + 1) / [totalSteps]. Skip the wave entirely by passing
 * `stepIndex = null`.
 *
 * @param title Top-bar headline (e.g. "POS", "Check-in", "Cart").
 * @param subtitle Step indicator under title (e.g. "Step 2 of 8 · Device").
 * @param stepIndex 0-indexed flow step. null = no wave bar.
 * @param totalSteps Total flow steps (default 8).
 * @param onBack Top-bar back-arrow handler. null = no back arrow.
 * @param bottomBar Slot for the contextual shelf content. Must respect
 *                  height ≤ 72dp; caller decides what fills it.
 * @param content The page body (caller owns padding inside).
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun PosFlowScaffold(
    title: String,
    subtitle: String? = null,
    stepIndex: Int? = null,
    totalSteps: Int = 8,
    onBack: (() -> Unit)? = null,
    /**
     * Optional override for the title slot. When non-null, [title] / [subtitle]
     * are ignored and the caller provides custom title content (e.g. a clickable
     * customer-name pill in PosCart). Use sparingly — defeats the
     * one-screen-fits-all premise of PosFlowScaffold.
     */
    titleContent: @Composable (() -> Unit)? = null,
    /**
     * Optional trailing icons / overflow menu for the top app bar (scan
     * barcode, …). Hosted in TopAppBar's standard actions slot — no styling
     * imposed; caller owns icon choice + tint.
     */
    actions: @Composable (RowScope.() -> Unit)? = null,
    /**
     * Optional snackbar host. Material 3 Scaffold expects the host *and* its
     * state to live in the same composition; provide the slot here so flow
     * screens can route Polite/Assertive announcements through standard
     * Compose plumbing without re-implementing the host inside content.
     */
    snackbarHost: @Composable () -> Unit = {},
    bottomBar: @Composable (RowScope.() -> Unit)? = null,
    content: @Composable (paddingValues: androidx.compose.foundation.layout.PaddingValues) -> Unit,
) {
    Scaffold(
        // Match LoginScreen wave-1 fix: don't double-count IME with explicit
        // safeDrawingPadding. POS flow screens use system-bars only — IME
        // handled via .imePadding() on input fields where present.
        contentWindowInsets = WindowInsets.systemBars.only(
            WindowInsetsSides.Horizontal + WindowInsetsSides.Top,
        ),
        snackbarHost = snackbarHost,
        topBar = {
            Column(modifier = Modifier.statusBarsPadding()) {
                TopAppBar(
                    title = {
                        if (titleContent != null) {
                            titleContent()
                        } else {
                            Column(modifier = Modifier.semantics(mergeDescendants = true) { heading() }) {
                                Text(
                                    text = title,
                                    style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold),
                                    color = MaterialTheme.colorScheme.onSurface,
                                )
                                if (subtitle != null) {
                                    Text(
                                        text = subtitle,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                        }
                    },
                    navigationIcon = {
                        if (onBack != null) {
                            IconButton(onClick = onBack) {
                                Icon(
                                    Icons.AutoMirrored.Filled.ArrowBack,
                                    contentDescription = "Back",
                                )
                            }
                        }
                    },
                    actions = actions ?: {},
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = MaterialTheme.colorScheme.background,
                    ),
                )
                if (stepIndex != null) {
                    val fraction = ((stepIndex + 1).coerceAtLeast(1).toFloat() / totalSteps.coerceAtLeast(1))
                        .coerceIn(0f, 1f)
                    LinearWavyProgressIndicator(
                        progress = { fraction },
                        waveSpeed = 5.dp,
                        modifier = Modifier
                            .fillMaxWidth()
                            .semantics {
                                contentDescription = "Step ${stepIndex + 1} of $totalSteps"
                            },
                    )
                }
            }
        },
        bottomBar = {
            // Always-present 72dp shelf — content slot is optional, but the
            // geometry stays constant so vertical rhythm doesn't jump as the
            // user navigates between flow screens.
            Surface(
                tonalElevation = 1.dp,
                color = MaterialTheme.colorScheme.background,
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .navigationBarsPadding()
                        .padding(horizontal = 16.dp, vertical = 12.dp)
                        // defaultMinSize, not fixed height: PosCart's
                        // totals+tender bar needs ~80dp content; the
                        // single-CTA flow steps still get the constant 48dp
                        // floor so vertical rhythm is consistent across the
                        // small-content screens.
                        .defaultMinSize(minHeight = 48.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    if (bottomBar != null) {
                        androidx.compose.foundation.layout.Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            content = bottomBar,
                        )
                    } else {
                        // No-content fallback — keep the shelf height with a
                        // subtle hint so the layout doesn't collapse.
                        Text(
                            text = "",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        },
        containerColor = MaterialTheme.colorScheme.background,
    ) { padding ->
        // Standard Scaffold idiom: do NOT pre-pad the inner Box. Pass the
        // PaddingValues through to the content lambda; the caller owns where
        // to apply it (so headers can stretch full-width while scrollable
        // bodies still respect the topBar/bottomBar insets). Pre-padding here
        // and forwarding to caller produced doubled top/bottom inset → empty
        // top space + tail content covered by the bottom shelf.
        Box(modifier = Modifier.fillMaxSize()) {
            content(padding)
        }
    }
}
