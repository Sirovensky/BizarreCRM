/**
 * ============================================================
 * DESIGN DECISION — NO GLASSMORPHISM ON ANDROID
 * ActionPlan §1.4 line 196
 * ============================================================
 * Android's Compose rendering pipeline does not offer a first-class
 * blur-behind primitive (unlike iOS UIVisualEffectView). Faking it via
 * RenderEffect (API 31+) is expensive, causes jank on mid-range devices,
 * and fails silently on API < 31. Glassmorphism effects are therefore
 * explicitly prohibited in this codebase. Use semi-transparent surfaces
 * backed by a solid scrim instead (Surface + alpha layering).
 *
 * Do NOT add:
 *   - BlurMaskFilter on large layered surfaces
 *   - RenderEffect.createBlurEffect on window decorations
 *   - Any "frosted glass" visual pattern
 *
 * See also: Android_audit.md §1.4, business-context.md § UI constraints.
 * ============================================================
 */
package com.bizarreelectronics.crm.ui.theme

import android.app.Activity
import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat
import com.bizarreelectronics.crm.BuildConfig
import java.util.Calendar

// ---------------------------------------------------------------------------
// Primitive palette — Wave 1 brand foundation
// ---------------------------------------------------------------------------

// Brand primaries (kept as named tokens so callers that import them directly
// keep compiling; they are retuned to the Bizarre palette).
// CROSS19/BRAND: primary accent is ORANGE from the logo, not purple/magenta.
// Earlier commits shipped a purple palette — user directive 2026-04-17 is that
// orange is the canonical brand accent. Teal secondary + magenta decorative
// tertiary remain in place; only primary changes.
val Blue600 = Color(0xFFFDEED0)   // brand cream — primary accent (POS redesign 2026-04-24)
val Blue700 = Color(0xFF2B1400)   // very dark brown — onPrimary for contrast on cream
val Blue50  = Color(0xFF3D2C14)   // warm dark container — primaryContainer
val Green600 = Color(0xFF34C47E)  // was #16A34A — retuned SuccessGreen

val Red600   = Color(0xFFE2526C)  // was #DC2626 — hue-shifted brand error
val Amber500 = Color(0xFFE8A33D)  // was #F59E0B — retuned WarningAmber

// Semantic tokens — retune values, keep names (many callers import these)
val SuccessGreen  = Color(0xFF34C47E)
val ErrorRed      = Color(0xFFE2526C)
val WarningAmber  = Color(0xFFE8A33D)
val InfoBlue      = Color(0xFF4DB8C9)  // repurposed to teal

// Background tokens (used by container colors in callers; retuned for dark ramp)
val WarningBg     = Color(0xFF2B1F0A)  // dark-mode amber bg (~WarningAmber @ 12%)
val WarningText   = Color(0xFFE8A33D)  // was #92400E — now matches WarningAmber on dark
val SuccessBg     = Color(0xFF0A2B1C)  // dark-mode green bg
val ErrorBg       = Color(0xFF2B0E14)  // dark-mode error bg

// One-off semantic tokens preserved for downstream callers
val StarYellow        = Color(0xFFFBBF24)  // star ratings — kept
val RefundedPurple    = Color(0xFFFDEED0)  // token name kept for API; value follows primary (cream)
val OutOfStockOrange  = Color(0xFFE8A33D)  // retuned to WarningAmber family
val ConditionAmberBg  = Color(0xFF2B1F0A)  // dark-mode amber bg
val ConditionAmberText = Color(0xFFE8A33D)

// ---------------------------------------------------------------------------
// Warm dark surface ramp
// ---------------------------------------------------------------------------
val BgDark        = Color(0xFF1C1611)  // background
val Surface1      = Color(0xFF26201A)  // surface / primary surface
val Surface2      = Color(0xFF322A22)  // elevated surface
val OutlineColor  = Color(0xFF4A3C30)  // dividers / borders
val MutedText     = Color(0xFFB09A84)  // onSurfaceVariant muted
val PrimaryText   = Color(0xFFF5E6D3)  // onBackground / onSurface

// Light-mode surface ramp (retained for when user toggles light)
val Surface50  = Color(0xFFFAF4EC)  // slightly warm white
val Surface100 = Color(0xFFEFE4D4)
val Surface200 = Color(0xFFE0D0B5)
val Surface700 = Color(0xFF5A4A38)
val Surface800 = Color(0xFF26201A)
val Surface900 = Color(0xFF1C1611)

/**
 * Returns Color.Black or Color.White based on perceived brightness of the background color.
 * Uses the W3C luminance formula: (R*299 + G*587 + B*114) / 1000.
 */
fun contrastTextColor(bgColor: Color): Color {
    val brightness = (bgColor.red * 299f + bgColor.green * 587f + bgColor.blue * 114f) / 1000f
    return if (brightness > 0.5f) Color.Black else Color.White
}

// ---------------------------------------------------------------------------
// Color schemes
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// §26.3 High-contrast color schemes (WCAG 2.1 AAA — 7:1 minimum)
//
// These schemes are activated when AppPreferences.highContrastEnabled == true.
// They maximise contrast ratios for users with low vision by using pure
// black/white surfaces with brand cream (#FDEED0) preserved for primary
// interactive elements (maintains brand identity at the highest accessible tier).
//
// Dark HC: black bg (#000000), white text (#FFFFFF), cream primary.
// Light HC: white bg (#FFFFFF), black text (#000000), dark-brown primary for AA+ on white.
// ---------------------------------------------------------------------------

private val HighContrastDarkColorScheme = darkColorScheme(
    primary              = Color(0xFFFDEED0),   // brand cream — selected/active accent
    onPrimary            = Color(0xFF000000),   // pure black on cream — 18.5:1
    primaryContainer     = Color(0xFF3D2C14),   // warm container retained; text is white
    onPrimaryContainer   = Color(0xFFFFFFFF),
    secondary            = Color(0xFF6FE8FA),   // brightened teal for contrast on black
    onSecondary          = Color(0xFF000000),
    secondaryContainer   = Color(0xFF003A44),
    onSecondaryContainer = Color(0xFFFFFFFF),
    tertiary             = Color(0xFFFF91D0),   // brightened magenta for contrast on black
    onTertiary           = Color(0xFF000000),
    tertiaryContainer    = Color(0xFF3D0028),
    onTertiaryContainer  = Color(0xFFFFFFFF),
    error                = Color(0xFFFF6B80),   // brightened error for black bg
    onError              = Color(0xFF000000),
    errorContainer       = Color(0xFF410009),
    onErrorContainer     = Color(0xFFFFFFFF),
    background           = Color(0xFF000000),   // pure black — max contrast surface
    onBackground         = Color(0xFFFFFFFF),   // pure white — 21:1 ratio
    surface              = Color(0xFF000000),
    onSurface            = Color(0xFFFFFFFF),
    surfaceVariant       = Color(0xFF1A1A1A),   // near-black surface variant
    onSurfaceVariant     = Color(0xFFEEEEEE),   // near-white — ≥ 12:1 on black
    surfaceContainer     = Color(0xFF1A1A1A),
    surfaceContainerHigh = Color(0xFF2A2A2A),
    outline              = Color(0xFFAAAAAA),   // mid-grey — visible dividers on black
)

private val HighContrastLightColorScheme = lightColorScheme(
    primary              = Color(0xFF4A2F00),   // very dark brown — 9.5:1 on white
    onPrimary            = Color(0xFFFFFFFF),
    primaryContainer     = Color(0xFFFDEED0),   // cream container
    onPrimaryContainer   = Color(0xFF000000),   // pure black on cream — 18.5:1
    secondary            = Color(0xFF003A44),   // very dark teal — high contrast
    onSecondary          = Color(0xFFFFFFFF),
    secondaryContainer   = Color(0xFFB8F0FA),
    onSecondaryContainer = Color(0xFF000000),
    tertiary             = Color(0xFF4A0028),   // very dark magenta
    onTertiary           = Color(0xFFFFFFFF),
    tertiaryContainer    = Color(0xFFFFD8EC),
    onTertiaryContainer  = Color(0xFF000000),
    error                = Color(0xFF6B0000),   // very dark red — 8.5:1 on white
    onError              = Color(0xFFFFFFFF),
    errorContainer       = Color(0xFFFFE0E0),
    onErrorContainer     = Color(0xFF000000),
    background           = Color(0xFFFFFFFF),   // pure white — max contrast surface
    onBackground         = Color(0xFF000000),   // pure black — 21:1 ratio
    surface              = Color(0xFFFFFFFF),
    onSurface            = Color(0xFF000000),
    surfaceVariant       = Color(0xFFF0F0F0),   // near-white variant
    onSurfaceVariant     = Color(0xFF111111),   // near-black — ≥ 16:1 on near-white
    surfaceContainer     = Color(0xFFF0F0F0),
    surfaceContainerHigh = Color(0xFFE0E0E0),
    outline              = Color(0xFF555555),   // dark grey — visible on white
)

private val LightColorScheme = lightColorScheme(
    // POS redesign wave (2026-04-24) — cream `#fdeed0` is the project-wide primary.
    // On light backgrounds cream is too pale for AA, so we shift down to a
    // warm caramel (`#a66d1f`) that reads as "same brand family" but meets AA.
    primary              = Color(0xFFA66D1F),   // caramel (cream shifted darker for light-bg AA)
    onPrimary            = Color(0xFFFFFFFF),
    primaryContainer     = Color(0xFFFDEED0),   // actual cream surface container
    onPrimaryContainer   = Color(0xFF2B1400),
    secondary            = Color(0xFF0E7A8A),   // teal darker for light-bg
    onSecondary          = Color(0xFFFFFFFF),
    secondaryContainer   = Color(0xFFCCF0F5),
    onSecondaryContainer = Color(0xFF012D35),
    tertiary             = Color(0xFFB01E7A),   // magenta darker for light-bg
    onTertiary           = Color(0xFFFFFFFF),
    tertiaryContainer    = Color(0xFFFFD8EC),
    onTertiaryContainer  = Color(0xFF3D0028),
    error                = Color(0xFFBA1A2E),
    onError              = Color(0xFFFFFFFF),
    errorContainer       = Color(0xFFFFDADC),
    onErrorContainer     = Color(0xFF410009),
    background           = Surface50,
    onBackground         = Surface900,
    surface              = Color(0xFFFFF8F0),
    onSurface            = Surface900,
    surfaceVariant       = Surface100,
    onSurfaceVariant     = Surface700,
    surfaceContainer     = Surface100,
    surfaceContainerHigh = Surface200,
    outline              = Surface200,
)

private val DarkColorScheme = darkColorScheme(
    // POS redesign wave (2026-04-24) — cream `#fdeed0` is the project-wide primary.
    // Pairs with dark-brown on-primary for AA contrast on warm dark surfaces.
    primary              = Color(0xFFFDEED0),   // brand cream — primary accent
    onPrimary            = Color(0xFF2B1400),   // near-black brown for contrast on cream
    primaryContainer     = Color(0xFF3D2C14),   // muted warm container (darker cream tint)
    onPrimaryContainer   = Color(0xFFFDEED0),   // cream text on container
    secondary            = Color(0xFF4DB8C9),   // teal
    onSecondary          = Color(0xFF003740),
    secondaryContainer   = Color(0xFF004E5C),
    onSecondaryContainer = Color(0xFFAAE9F5),
    tertiary             = Color(0xFFD94F9B),   // magenta
    onTertiary           = Color(0xFF3D0028),
    tertiaryContainer    = Color(0xFF5A1045),
    onTertiaryContainer  = Color(0xFFFFD8EC),
    error                = Color(0xFFE2526C),   // hue-shifted brand error
    onError              = Color(0xFF410009),
    errorContainer       = Color(0xFF6B0E1E),
    onErrorContainer     = Color(0xFFFFB3BC),
    background           = BgDark,             // #121017
    onBackground         = PrimaryText,        // #ECE9F3
    surface              = Surface1,           // #1A1722
    onSurface            = PrimaryText,
    surfaceVariant       = Surface2,           // #241F2E
    onSurfaceVariant     = MutedText,          // #A79FB8
    surfaceContainer     = Surface1,           // #1A1722
    surfaceContainerHigh = Surface2,           // #241F2E
    outline              = OutlineColor,       // #332C3F
)

// ---------------------------------------------------------------------------
// Shapes — moved to Shapes.kt (CROSS33 / ActionPlan §1.4 line 191)
// ---------------------------------------------------------------------------
// BizarreShapes is now defined in Shapes.kt with the full extraSmall/small/
// medium/large/extraLarge token set. The import is automatic within this
// package — no explicit import needed.

// ---------------------------------------------------------------------------
// Tenant accent — ActionPlan §1.4 line 195
// ---------------------------------------------------------------------------

/**
 * Brand cream: canonical Bizarre Electronics primary accent (POS redesign 2026-04-24).
 * Matches primary in DarkColorScheme and Blue600.
 */
val BrandAccent: Color = Color(0xFFFDEED0)

/**
 * Returns the tenant-supplied accent color when non-null, falling back to
 * [BrandAccent] (brand cream). Future multi-tenant builds can inject a
 * per-tenant override at the theme call site; single-tenant builds simply
 * pass null and always receive the canonical cream.
 */
fun tenantAccentOrFallback(override: Color? = null): Color = override ?: BrandAccent

/**
 * CompositionLocal carrying the active tenant brand accent.
 * Provided by [BizarreCrmTheme] / [DesignSystemTheme] via
 * [CompositionLocalProvider]. Composables read:
 * ```kotlin
 * val accent = LocalBrandAccent.current
 * ```
 * Uses [staticCompositionLocalOf] because the accent does not change during
 * a composition — only at a theme re-entry boundary.
 */
val LocalBrandAccent = staticCompositionLocalOf<Color> { BrandAccent }

// ---------------------------------------------------------------------------
// §30.9 — Tenant accent with auto-contrast bump
// ---------------------------------------------------------------------------

/**
 * Perceived relative luminance of [color] using the W3C sRGB formula.
 *
 * Returns a value in [0, 1] where 0 = black and 1 = white.
 */
private fun relativeLuminance(color: Color): Float {
    fun linearize(c: Float): Float = if (c <= 0.04045f) {
        c / 12.92f
    } else {
        Math.pow(((c + 0.055f) / 1.055f).toDouble(), 2.4).toFloat()
    }
    return 0.2126f * linearize(color.red) +
           0.7152f * linearize(color.green) +
           0.0722f * linearize(color.blue)
}

/**
 * WCAG 2.1 contrast ratio between two colors.
 *
 * Values ≥ 4.5 satisfy AA for normal text; ≥ 3.0 satisfies AA for large text
 * and graphical components (buttons, icons).
 */
fun contrastRatio(fg: Color, bg: Color): Float {
    val l1 = relativeLuminance(fg)
    val l2 = relativeLuminance(bg)
    val lighter = maxOf(l1, l2)
    val darker  = minOf(l1, l2)
    return (lighter + 0.05f) / (darker + 0.05f)
}

/**
 * §30.9 — Returns the tenant accent color, bumped toward white (in dark mode)
 * or toward black (in light mode) until the contrast ratio against the active
 * surface color meets the AA 3.0 threshold for graphical components.
 *
 * If [tenantAccent] is null, returns [BrandAccent] (brand cream) unchanged —
 * cream on the warm dark surface is already > 3.0.
 *
 * The bump is additive HSL lightness in 5% steps (max 6 steps). If no bump
 * achieves AA 3.0, the original color is returned (fail-open — prefer tenant
 * branding over hard rejecting any color). Callers that need strict AA must
 * validate post-call.
 *
 * @param tenantAccent Tenant-provided accent, or null to use brand default.
 * @param surfaceColor The background surface the accent will sit on. Defaults
 *   to dark mode [Surface1] (`0xFF26201A`) — pass [Color.White] for light mode.
 */
fun tenantAccentWithContrastBump(
    tenantAccent: Color?,
    surfaceColor: Color = Surface1,
): Color {
    if (tenantAccent == null) return BrandAccent
    val minContrast = 3.0f
    if (contrastRatio(tenantAccent, surfaceColor) >= minContrast) return tenantAccent

    // Try lightening the accent in 5% steps (up to +30% lightness).
    val lightSurface = relativeLuminance(surfaceColor) > 0.5f
    var bumped: Color = tenantAccent
    repeat(6) {
        val factor = if (lightSurface) 0.85f else 1.15f
        bumped = Color(
            red   = (bumped.red   * factor).coerceIn(0f, 1f),
            green = (bumped.green * factor).coerceIn(0f, 1f),
            blue  = (bumped.blue  * factor).coerceIn(0f, 1f),
            alpha = bumped.alpha,
        )
        if (contrastRatio(bumped, surfaceColor) >= minContrast) return bumped
    }
    return bumped // best effort — caller's choice if still low-contrast
}

// ---------------------------------------------------------------------------
// §26.3 — Color-blind safe palette variants
//
// Three simulation modes based on the most common forms of color vision
// deficiency. Each mode remaps the ExtendedColors semantic slots so that
// success/warning/error/info can be distinguished without relying on
// red-green or blue-yellow hue differences.
//
// Deuteranopia / Protanopia (red-green, ~8% of males):
//   success → blue (#4DB8C9 teal-blue); warning → amber (unchanged, safe);
//   error   → orange-red (#E87D3E, distinguishable from teal);
//   info    → violet (#9B6CF8, distinguishable from orange).
//
// Tritanopia (blue-yellow, ~0.01% prevalence):
//   success → green (#34C47E, unchanged — green/red still distinguishable);
//   warning → magenta (#D94F9B, avoids yellow);
//   error   → red (#E2526C, unchanged);
//   info    → dark-teal (#006878, avoids light blue).
//
// The primary brand accent (cream #FDEED0) is not affected — it is decorative,
// not used as a status color.
// ---------------------------------------------------------------------------

/**
 * §26.3 — Identifies which color-blind accommodation is active.
 *
 * [None] = standard palette; [Deuteranopia] covers both deuteranopia and
 * protanopia (both are red-green deficiencies with very similar safe palettes);
 * [Tritanopia] covers the rarer blue-yellow deficiency.
 *
 * Persisted as a String key in [AppPreferences] so new values can be added
 * without a DB migration.
 */
enum class ColorBlindMode(val key: String, val label: String, val description: String) {
    None(
        key = "none",
        label = "None",
        description = "Standard color palette",
    ),
    Deuteranopia(
        key = "deuteranopia",
        label = "Deuteranopia / Protanopia",
        description = "Red-green safe: replaces green with blue and red with orange",
    ),
    Tritanopia(
        key = "tritanopia",
        label = "Tritanopia",
        description = "Blue-yellow safe: replaces yellow with magenta and blue with teal",
    );

    companion object {
        /** Returns the mode matching [key], falling back to [None] for unknown keys. */
        fun fromKey(key: String): ColorBlindMode =
            entries.firstOrNull { it.key == key } ?: None
    }
}

/**
 * §26.3 — Dark-theme [ExtendedColors] tuned for deuteranopia / protanopia.
 *
 * Avoids hue pairs that red-green deficient viewers cannot distinguish:
 * - success slot changed from green to teal-blue (#4DB8C9) — separable from orange
 * - error   slot changed to orange-red (#E87D3E) — clearly distinct from teal
 * - warning retains amber (#E8A33D) — remains visible in this deficiency
 * - info    changes to violet (#9B6CF8) — adds a third separable hue
 */
fun deuteranopiaExtended(): ExtendedColors = ExtendedColors(
    success          = Color(0xFF4DB8C9),   // teal-blue — safe replacement for green
    warning          = Color(0xFFE8A33D),   // amber — unchanged, visible for red-green
    error            = Color(0xFFE87D3E),   // orange-red — distinct from teal-blue
    info             = Color(0xFF9B6CF8),   // violet — third distinguishable hue
    successContainer = Color(0xFF003740),   // dark teal container
    warningContainer = Color(0xFF2B1F0A),   // dark amber container (unchanged)
    errorContainer   = Color(0xFF3A1A00),   // dark orange container
    infoContainer    = Color(0xFF2A1A50),   // dark violet container
)

/**
 * §26.3 — Light-theme [ExtendedColors] tuned for deuteranopia / protanopia.
 */
fun deuteranopiaLightExtended(): ExtendedColors = ExtendedColors(
    success          = Color(0xFF006878),   // dark teal — AA on white
    warning          = Color(0xFF8A5200),   // dark amber (unchanged)
    error            = Color(0xFFB34700),   // dark orange — distinct from teal
    info             = Color(0xFF5C3DAA),   // dark violet — AA on white
    successContainer = Color(0xFFCCF0F5),   // light teal container
    warningContainer = Color(0xFFFFDDB8),   // light amber container
    errorContainer   = Color(0xFFFFE0CC),   // light orange container
    infoContainer    = Color(0xFFEADDFF),   // light violet container
)

/**
 * §26.3 — Dark-theme [ExtendedColors] tuned for tritanopia (blue-yellow blind).
 *
 * Avoids hue pairs that blue-yellow deficient viewers cannot distinguish:
 * - warning changed from amber/yellow (#E8A33D) to magenta (#D94F9B) — distinguishable from red/green
 * - info    changed from teal-blue (#4DB8C9) to darker teal (#006878) — the blue-yellow axis is shifted
 * - success and error retain green/red — they are still distinguishable in tritanopia
 */
fun tritanopiaExtended(): ExtendedColors = ExtendedColors(
    success          = Color(0xFF34C47E),   // green — unchanged, safe for tritanopia
    warning          = Color(0xFFD94F9B),   // magenta — avoids yellow/amber ambiguity
    error            = Color(0xFFE2526C),   // red — unchanged, safe for tritanopia
    info             = Color(0xFF4FBFDF),   // brighter teal shifted away from blue-yellow axis
    successContainer = Color(0xFF0A2B1C),   // dark green container (unchanged)
    warningContainer = Color(0xFF3D0028),   // dark magenta container
    errorContainer   = Color(0xFF2B0E14),   // dark red container (unchanged)
    infoContainer    = Color(0xFF003A44),   // dark teal container
)

/**
 * §26.3 — Light-theme [ExtendedColors] tuned for tritanopia.
 */
fun tritanopiaLightExtended(): ExtendedColors = ExtendedColors(
    success          = Color(0xFF1F7A4A),   // dark green (unchanged)
    warning          = Color(0xFF7A1A56),   // dark magenta — AA on white
    error            = Color(0xFFBA1A2E),   // dark red (unchanged)
    info             = Color(0xFF00606F),   // dark teal — distinct from magenta
    successContainer = Color(0xFFB8F0D5),
    warningContainer = Color(0xFFFFD8EC),   // light magenta container
    errorContainer   = Color(0xFFFFDADC),
    infoContainer    = Color(0xFFCCEFF5),
)

// ---------------------------------------------------------------------------
// §30.8 — Dark mode after 7pm default
// ---------------------------------------------------------------------------

/**
 * §30.8 — Returns true if the current local time is after 19:00 (7 pm) or
 * before 07:00 (7 am) — the window during which dark mode should default ON
 * when the user has not explicitly chosen a preference ("system" setting).
 *
 * Callers that want this auto-scheduling behaviour should read
 * [AppPreferences.darkMode] first; only when the value is "system" (no
 * user override) should this function influence the theme:
 *
 * ```kotlin
 * val darkTheme = when (darkModePreference) {
 *     "dark"   -> true
 *     "light"  -> false
 *     else     -> shouldDefaultDarkMode() // auto-schedule
 * }
 * ```
 *
 * Note: uses [Calendar.getInstance] (device local timezone). If the user has
 * a timezone override configured via [AppPreferences.timezoneOverride], the
 * ViewModel layer is responsible for injecting the correct wall-clock value
 * rather than relying on this function directly.
 */
fun shouldDefaultDarkMode(): Boolean {
    val hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
    return hour >= 19 || hour < 7
}

// ---------------------------------------------------------------------------
// §75.10 — System-bar appearance (status-bar icon colour)
// ---------------------------------------------------------------------------

/**
 * §75.10 — Adjusts the status-bar and navigation-bar icon colours to match the
 * active theme so the icons remain legible on every screen.
 *
 * Android draws status-bar icons in **dark** (black) or **light** (white) ink.
 * By default [enableEdgeToEdge] in [MainActivity] picks the system's preference,
 * but when the user switches between light and dark themes at runtime the icons
 * need to be updated imperatively via [WindowCompat.getInsetsController].
 *
 * - Dark theme  → light icons (white on dark surface)
 * - Light theme → dark icons (black on light surface)
 *
 * A [DisposableEffect] is used so the previous appearance is restored when the
 * composable leaves the tree (e.g. the user navigates to a screen that manages
 * its own insets, such as [TvQueueBoardScreen]).
 *
 * This composable is intentionally side-effect-only — it emits no UI.
 *
 * @param darkTheme Whether the active theme is dark (true) or light (false).
 */
@Composable
fun SystemBarAppearance(darkTheme: Boolean) {
    val view = LocalView.current
    // Skip in preview / test environments where there is no real window.
    if (view.isInEditMode) return
    DisposableEffect(darkTheme) {
        val window = (view.context as? Activity)?.window ?: return@DisposableEffect onDispose {}
        val controller = WindowCompat.getInsetsController(window, view)
        // isAppearanceLightStatusBars = true  → dark (black) icons, for light surfaces.
        // isAppearanceLightStatusBars = false → light (white) icons, for dark surfaces.
        val lightIcons = !darkTheme
        controller.isAppearanceLightStatusBars = lightIcons
        controller.isAppearanceLightNavigationBars = lightIcons
        onDispose {
            // Restore defaults to avoid bleeding into screens that override insets
            // independently (e.g. TvQueueBoardScreen which hides bars entirely).
            controller.isAppearanceLightStatusBars = false
            controller.isAppearanceLightNavigationBars = false
        }
    }
}

// ---------------------------------------------------------------------------
// Theme entry point
// ---------------------------------------------------------------------------

/**
 * [BizarreCrmTheme] wraps the tree in a Material 3 theme. When
 * `BuildConfig.USE_EXPRESSIVE_THEME` is true (default 2026-04), the inner
 * wrapper is [MaterialExpressiveTheme] (material3 1.5.0-alpha18) which
 * ships the motion-scheme / shape-morph / typography-emphasis tokens.
 * When the flag is flipped off at build time, the tree falls back to
 * plain [MaterialTheme] so ops can hotfix an expressive regression
 * without a rebuild.
 *
 * Reduce-Motion compliance stays in [ui/theme/Motion.kt] — every spring
 * still routes through [ReduceMotion].
 */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun BizarreCrmTheme(
    // Default is true — dark-first. AppPreferences.darkMode overrides from
    // Settings ("dark" | "light" | "system"). Wave 3 wires the Settings toggle;
    // this stub reads the pref so the toggle hook is wired even though the UI
    // doesn't exist yet.
    darkTheme: Boolean = true,
    // ActionPlan §1.4 line 190: dynamicColor reads AppPreferences.dynamicColorEnabled.
    // Defaults FALSE so the Bizarre brand palette always renders out of the box.
    // When true AND Android 12+ (API 31+), Material You derives the color scheme
    // from the user's wallpaper via dynamicLightColorScheme / dynamicDarkColorScheme.
    dynamicColor: Boolean = false,
    // §26.3 — ActionPlan line 3391: high-contrast mode bumps to WCAG AAA 7:1.
    // When true, HighContrastDark/LightColorScheme replaces the standard scheme;
    // dynamicColor is overridden (Material You palette cannot guarantee 7:1).
    // Sourced from AppPreferences.highContrastEnabledFlow in MainActivity.
    highContrast: Boolean = false,
    // §26.3 — Color-blind safe palette. When not [ColorBlindMode.None], the
    // ExtendedColors semantic slots (success/warning/error/info) are replaced
    // with hue combinations safe for the specified color vision deficiency.
    // High-contrast mode takes precedence and ignores this parameter.
    colorBlindMode: ColorBlindMode = ColorBlindMode.None,
    // Tenant accent override — null uses BrandAccent (brand cream).
    tenantAccent: Color? = null,
    content: @Composable () -> Unit,
) {
    val colorScheme = when {
        // High-contrast overrides both dynamic color and standard schemes.
        // DynamicColor is intentionally bypassed — wallpaper-derived palettes
        // cannot guarantee AAA 7:1 contrast ratios.
        highContrast -> if (darkTheme) HighContrastDarkColorScheme else HighContrastLightColorScheme
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        darkTheme -> DarkColorScheme
        else -> LightColorScheme
    }

    // AND-036: provide semantic extended colors matching the active theme so
    // composables can read LocalExtendedColors.current instead of importing
    // hardcoded top-level color vals.
    // §26.3: high-contrast mode uses its own extended color variants that
    // meet AAA 7:1 on their respective black/white surface.
    // §26.3: color-blind modes override success/warning/error/info hues;
    // high-contrast takes precedence (accessibility stacking order).
    val extendedColors = when {
        highContrast && darkTheme -> ExtendedColors(
            success          = Color(0xFF50FA7B),   // bright green — 9:1 on black
            warning          = Color(0xFFFFD080),   // bright amber — 8:1 on black
            error            = Color(0xFFFF6B80),   // bright red — 7:1 on black
            info             = Color(0xFF6FE8FA),   // bright teal — 9:1 on black
            successContainer = Color(0xFF003311),
            warningContainer = Color(0xFF332200),
            errorContainer   = Color(0xFF330008),
            infoContainer    = Color(0xFF003340),
        )
        highContrast -> ExtendedColors(
            success          = Color(0xFF004422),   // very dark green — 9:1 on white
            warning          = Color(0xFF5A3500),   // very dark amber — 8:1 on white
            error            = Color(0xFF6B0000),   // very dark red — 8.5:1 on white
            info             = Color(0xFF003A44),   // very dark teal — 9:1 on white
            successContainer = Color(0xFFB8F0D5),
            warningContainer = Color(0xFFFFDDB8),
            errorContainer   = Color(0xFFFFE0E0),
            infoContainer    = Color(0xFFCCF0F5),
        )
        // §26.3 — Color-blind extended colors. High-contrast already handled above.
        colorBlindMode == ColorBlindMode.Deuteranopia && darkTheme  -> deuteranopiaExtended()
        colorBlindMode == ColorBlindMode.Deuteranopia               -> deuteranopiaLightExtended()
        colorBlindMode == ColorBlindMode.Tritanopia && darkTheme    -> tritanopiaExtended()
        colorBlindMode == ColorBlindMode.Tritanopia                 -> tritanopiaLightExtended()
        darkTheme -> darkExtended()
        else -> lightExtended()
    }

    // §30.9: resolve tenant accent with auto-contrast bump.
    // Falls back to brand cream when null; bumps toward AA 3.0 when the
    // tenant-supplied color is too pale against the active surface.
    // §26.3: in high-contrast mode the surface is black/white — always use
    // brand cream directly (cream on black is already ≥ 12:1).
    val activeSurface = when {
        highContrast -> if (darkTheme) Color(0xFF000000) else Color(0xFFFFFFFF)
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
            if (darkTheme) Surface1 else Color(0xFFFFF8F0)
        else -> if (darkTheme) Surface1 else Color(0xFFFFF8F0)
    }
    val resolvedAccent = tenantAccentWithContrastBump(tenantAccent, surfaceColor = activeSurface)

    // §75.10 — Sync status-bar / nav-bar icon colour with the active theme.
    // Placed here so every screen that uses BizarreCrmTheme (or DesignSystemTheme)
    // inherits correct icon tinting automatically without per-screen boilerplate.
    SystemBarAppearance(darkTheme = darkTheme)

    CompositionLocalProvider(
        LocalExtendedColors provides extendedColors,
        LocalBrandAccent provides resolvedAccent,
    ) {
        if (BuildConfig.USE_EXPRESSIVE_THEME) {
            MaterialExpressiveTheme(
                colorScheme = colorScheme,
                typography = BizarreTypography,
                shapes = BizarreShapes,
                motionScheme = MotionScheme.expressive(),
                content = content,
            )
        } else {
            MaterialTheme(
                colorScheme = colorScheme,
                typography = BizarreTypography,
                shapes = BizarreShapes,
                content = content,
            )
        }
    }
}

// ---------------------------------------------------------------------------
// DesignSystemTheme — ActionPlan §1.4 line 189
// ---------------------------------------------------------------------------

/**
 * [DesignSystemTheme] is the forward-looking entry point for the Bizarre CRM
 * design system. Wraps [BizarreCrmTheme] 1-to-1 so all callers that use
 * [BizarreCrmTheme] continue to compile unchanged.
 *
 * M3 Expressive (material3 1.4.0 stable, 2025-09) is now live behind the
 * `BuildConfig.USE_EXPRESSIVE_THEME` flag managed in [BizarreCrmTheme]. No
 * further refactor needed at this layer.
 */
@Composable
fun DesignSystemTheme(
    darkTheme: Boolean = true,
    dynamicColor: Boolean = false,
    highContrast: Boolean = false,
    colorBlindMode: ColorBlindMode = ColorBlindMode.None,
    tenantAccent: Color? = null,
    content: @Composable () -> Unit,
) {
    BizarreCrmTheme(
        darkTheme = darkTheme,
        dynamicColor = dynamicColor,
        highContrast = highContrast,
        colorBlindMode = colorBlindMode,
        tenantAccent = tenantAccent,
        content = content,
    )
}
