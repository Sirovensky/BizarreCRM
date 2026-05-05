package com.bizarreelectronics.crm.ui.theme

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.graphics.Color

/**
 * Semantic color extensions for the Bizarre CRM design system.
 *
 * AND-036: Material3's ColorScheme does not have first-class success/warning/info
 * slots. Rather than using hardcoded theme-file constants (SuccessGreen, WarningAmber,
 * ErrorRed, InfoBlue) directly at call sites — which ignores the active theme — this
 * CompositionLocal lets callers read `LocalExtendedColors.current.success` and always
 * get the correct value for the current light/dark theme.
 *
 * ## Usage
 * ```kotlin
 * val ext = LocalExtendedColors.current
 * Text("Ready", color = ext.success)
 * Surface(color = ext.successContainer) { ... }
 * ```
 *
 * ## Migration
 * 43 call sites import SuccessGreen / WarningAmber / ErrorRed / InfoBlue directly.
 * This PR migrates the 5 highest-traffic sites (see below). The remaining 38 are
 * flagged for follow-up — they still compile because the old top-level vals are kept
 * in Theme.kt as deprecated aliases.
 *
 * ## Wire-up
 * [BizarreCrmTheme] provides this via [CompositionLocalProvider]:
 *   `CompositionLocalProvider(LocalExtendedColors provides extendedColors) { content() }`
 */
@Immutable
data class ExtendedColors(
    val success: Color,
    val warning: Color,
    val error: Color,
    val info: Color,
    val successContainer: Color,
    val warningContainer: Color,
    val errorContainer: Color,
    val infoContainer: Color,
)

/** Default light-theme extended colors. */
fun lightExtended(): ExtendedColors = ExtendedColors(
    success          = Color(0xFF1F7A4A),   // darker green for light-bg AA contrast
    warning          = Color(0xFF8A5200),   // darker amber for light-bg
    error            = Color(0xFFBA1A2E),   // matches LightColorScheme.error
    info             = Color(0xFF006878),   // teal darker for light-bg
    successContainer = Color(0xFFB8F0D5),
    warningContainer = Color(0xFFFFDDB8),
    errorContainer   = Color(0xFFFFDADC),
    infoContainer    = Color(0xFFCCF0F5),
)

/** Default dark-theme extended colors. */
fun darkExtended(): ExtendedColors = ExtendedColors(
    success          = SuccessGreen,        // Color(0xFF34C47E)
    warning          = WarningAmber,        // Color(0xFFE8A33D)
    error            = ErrorRed,            // Color(0xFFE2526C)
    info             = InfoBlue,            // Color(0xFF4DB8C9)
    successContainer = SuccessBg,           // Color(0xFF0A2B1C)
    warningContainer = WarningBg,           // Color(0xFF2B1F0A)
    errorContainer   = ErrorBg,            // Color(0xFF2B0E14)
    infoContainer    = Color(0xFF012D35),
)

/**
 * CompositionLocal providing [ExtendedColors] for the current theme.
 * Default value is [darkExtended()] so previews without a Theme wrapper
 * get reasonable colours rather than crashing.
 */
val LocalExtendedColors = compositionLocalOf { darkExtended() }
