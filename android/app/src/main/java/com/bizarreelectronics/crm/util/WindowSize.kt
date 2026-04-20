package com.bizarreelectronics.crm.util

import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.platform.LocalConfiguration

/**
 * §22 / §23 — adaptive layout helper.
 *
 * Width-based mode classification without pulling in extra adaptive artifacts.
 * Uses [LocalConfiguration.screenWidthDp] which Compose recomposes on
 * configuration changes (rotation, multi-window resize, foldable posture).
 *
 * Breakpoints follow Material Design window-size-class guidance:
 *   - Compact  width < 600dp  → [WindowMode.Phone]
 *   - Medium   600–839dp      → [WindowMode.Tablet]
 *   - Expanded ≥ 840dp        → [WindowMode.Desktop]
 *
 * Section guidance from the plan:
 *   - Phone   → bottom NavigationBar, single-pane stacks.
 *   - Tablet  → NavigationRail + list-detail two-pane scaffold.
 *   - Desktop → PermanentNavigationDrawer + multi-pane.
 */
enum class WindowMode {
    Phone,
    Tablet,
    Desktop,
}

private const val TABLET_MIN_DP = 600
private const val DESKTOP_MIN_DP = 840

@Composable
@ReadOnlyComposable
fun rememberWindowMode(): WindowMode = widthDpToMode(LocalConfiguration.current.screenWidthDp)

@Composable
@ReadOnlyComposable
fun isCompactWidth(): Boolean = rememberWindowMode() == WindowMode.Phone

@Composable
@ReadOnlyComposable
fun isMediumOrExpandedWidth(): Boolean = rememberWindowMode() != WindowMode.Phone

fun widthDpToMode(widthDp: Int): WindowMode = when {
    widthDp < TABLET_MIN_DP -> WindowMode.Phone
    widthDp < DESKTOP_MIN_DP -> WindowMode.Tablet
    else -> WindowMode.Desktop
}
