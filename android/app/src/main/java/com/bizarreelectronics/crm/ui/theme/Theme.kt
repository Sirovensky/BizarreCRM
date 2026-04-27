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

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
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
    // Tenant accent override — null uses BrandAccent (brand cream).
    tenantAccent: Color? = null,
    content: @Composable () -> Unit,
) {
    val colorScheme = when {
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
    val extendedColors = if (darkTheme) darkExtended() else lightExtended()

    // §30.9: resolve tenant accent with auto-contrast bump.
    // Falls back to brand cream when null; bumps toward AA 3.0 when the
    // tenant-supplied color is too pale against the active surface.
    val activeSurface = if (dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        // Dynamic color — use a neutral mid-dark surface as the bump reference.
        if (darkTheme) Surface1 else Color(0xFFFFF8F0)
    } else {
        if (darkTheme) Surface1 else Color(0xFFFFF8F0)
    }
    val resolvedAccent = tenantAccentWithContrastBump(tenantAccent, surfaceColor = activeSurface)

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
    tenantAccent: Color? = null,
    content: @Composable () -> Unit,
) {
    BizarreCrmTheme(
        darkTheme = darkTheme,
        dynamicColor = dynamicColor,
        tenantAccent = tenantAccent,
        content = content,
    )
}
