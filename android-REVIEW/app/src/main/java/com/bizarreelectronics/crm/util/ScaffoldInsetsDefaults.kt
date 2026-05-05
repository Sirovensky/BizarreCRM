package com.bizarreelectronics.crm.util

import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.systemBars
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable

/**
 * ScaffoldInsetsDefaults — §23.5 window-insets rules for Scaffold.contentWindowInsets.
 *
 * ## Problem
 * The app uses edge-to-edge rendering (`WindowCompat.setDecorFitsSystemWindows(window, false)`).
 * Without careful inset delegation every nested Scaffold compounds the insets, producing
 * double status-bar padding or clipping content behind the navigation bar.
 *
 * ## Three tiers
 *
 * ### 1. Root scaffold (AppNavGraph)
 * The single outermost `Scaffold` wrapping the `NavHost` must claim only the
 * *horizontal* side insets and the *bottom* navigation-bar inset. The top
 * (status-bar) inset is deliberately left for each child screen's own
 * `TopAppBar` to consume via `TopAppBarDefaults` color + surface elevation.
 *
 * ```kotlin
 * // AppNavGraph.kt
 * Scaffold(
 *     contentWindowInsets = ScaffoldInsetsDefaults.rootScaffold(),
 *     ...
 * )
 * ```
 *
 * ### 2. Full-screen modal scaffolds (auth / POS entry)
 * Screens that are displayed *without* a parent Scaffold (e.g. LoginScreen,
 * PosEntryScreen drawn over the full window) must zero the insets on the
 * Scaffold itself and re-apply `Modifier.safeDrawingPadding()` manually so
 * they own the complete inset space without double-counting.
 *
 * ```kotlin
 * // LoginScreen.kt / PosEntryScreen.kt
 * Scaffold(
 *     contentWindowInsets = ScaffoldInsetsDefaults.standaloneModal,
 * ) { padding ->
 *     Box(
 *         modifier = Modifier
 *             .fillMaxSize()
 *             .safeDrawingPadding()   // ← explicit ownership
 *             .padding(padding),
 *     )
 * }
 * ```
 *
 * ### 3. Leaf screens inside NavHost (default)
 * Child screens rendered inside the NavHost inheriting from tier 1 should use
 * the **default** `contentWindowInsets` (i.e. omit the parameter). Material 3
 * Scaffold's default is `ScaffoldDefaults.contentWindowInsets` which passes
 * `WindowInsets.safeContent`. This is correct because the parent root scaffold
 * (tier 1) already consumed the status-bar top and the bottom navigation-bar
 * insets — the child's default will resolve to empty for those sides and still
 * provide correct IME + cutout protection.
 *
 * ```kotlin
 * // TicketListScreen.kt, CustomerDetailScreen.kt, etc. — no override needed
 * Scaffold(
 *     topBar = { BrandTopAppBar("Tickets", ...) },
 * ) { innerPadding ->
 *     LazyColumn(modifier = Modifier.padding(innerPadding))
 * }
 * ```
 *
 * ## IME (keyboard) padding
 * Screens with text input that scrolls behind the IME should add
 * `Modifier.imePadding()` to the scrollable content container, **not** to the
 * Scaffold itself. The Scaffold's `contentWindowInsets` already excludes IME
 * when using [rootScaffold] — adding it again at the root would cause
 * double-inset on foldables and desktop windows where the soft keyboard is
 * free-floating.
 *
 * ## Foldable / desktop considerations (§23.5)
 * On foldable devices in **tabletop** posture the hinge splits the display
 * horizontally. `WindowInsets.safeDrawing` on Android 12L+ includes the hinge
 * area in its insets, so using [rootScaffold] (which preserves horizontal
 * insets) means content is never drawn on the hinge. On **book** posture
 * (vertical hinge), the horizontal side insets in [rootScaffold] achieve the
 * same result.
 *
 * On **desktop / freeform** windows the status bar may not be present at all;
 * `WindowInsets.systemBars` degrades gracefully to zero for absent bars, so no
 * special handling is needed.
 */
object ScaffoldInsetsDefaults {

    /**
     * Insets for the single root [androidx.compose.material3.Scaffold] that hosts
     * the [androidx.navigation.compose.NavHost].
     *
     * Keeps horizontal side insets (cutouts, side nav gestures) and the bottom
     * navigation-bar inset. Drops the top status-bar inset so child screens'
     * own [androidx.compose.material3.TopAppBar] instances take ownership.
     *
     * Must be read inside a `@Composable` context because [WindowInsets.systemBars]
     * is resolved from the composition tree.
     */
    val rootScaffold: WindowInsets
        @Composable
        get() = WindowInsets.systemBars.only(
            WindowInsetsSides.Horizontal + WindowInsetsSides.Bottom,
        )

    /**
     * Insets for full-screen modal scaffolds that are drawn without a parent
     * scaffold above them (e.g. LoginScreen, PosEntryScreen).
     *
     * Pass this as `contentWindowInsets` and apply `Modifier.safeDrawingPadding()`
     * explicitly on the root content Box so the screen owns all insets itself.
     *
     * This is a compile-time constant — no composition ambient reads required.
     */
    val standaloneModal: WindowInsets = WindowInsets(0)
}
