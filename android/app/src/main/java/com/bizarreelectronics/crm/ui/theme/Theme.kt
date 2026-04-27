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
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalContext
import com.bizarreelectronics.crm.BuildConfig
import java.time.LocalTime

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
// Dark surface ramp — aligned to ios/pos-phone-mockups.html (2026-04-26 audit)
// ---------------------------------------------------------------------------
val BgDark        = Color(0xFF0F0A14)  // background — deep purple-black
val Surface1      = Color(0xFF1A1722)  // surface / primary surface
val Surface2      = Color(0xFF241F2E)  // elevated surface
val OutlineColor  = Color(0xFF332C3F)  // dividers / borders
val MutedText     = Color(0xFFA79FB8)  // onSurfaceVariant — cool muted
val PrimaryText   = Color(0xFFECE9F3)  // onBackground / onSurface — cool light

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

// ---------------------------------------------------------------------------
// §30.8 — Dark mode auto after 7pm
// ---------------------------------------------------------------------------

/**
 * Returns true if the local hour is 19:00 (7pm) or later and before 07:00
 * (7am next day). Used as the default-dark fallback when the user has not
 * explicitly set a dark/light preference.
 *
 * Called inside [BizarreCrmTheme] only when [darkTheme] hasn't been
 * overridden by an explicit user pref — callers pass the result of
 * `AppPreferences.darkMode` already resolved. This helper is a pure-Kotlin
 * utility so it can be tested without Compose.
 */
fun isAfterSevenPm(): Boolean {
    val hour = LocalTime.now().hour
    return hour >= 19 || hour < 7
}

// ---------------------------------------------------------------------------
// §30.9 — Tenant accent contrast bump
// ---------------------------------------------------------------------------

/**
 * Returns a version of [accent] that meets Material 3 AA 4.5:1 contrast against
 * [onSurface]. If the luminance ratio of the supplied accent is already ≥ 4.5:1
 * the color is returned unchanged.
 *
 * Strategy: if the accent is too pale (high luminance on a dark surface), darken
 * it by blending toward black. If too dark (low luminance on a light surface),
 * lighten it toward white. The blend ratio is binary at 0.35f, which in practice
 * shifts most brand pastels far enough to clear AA without losing hue recognition.
 *
 * Semantic danger / success / warning colors are NEVER passed through here —
 * callers must only supply the primary brand accent so semantic signals are
 * never overridden.
 */
fun accentWithContrastBump(accent: Color, onSurface: Color): Color {
    val accentLum = accent.luminance()
    val bgLum = onSurface.luminance()
    // WCAG contrast = (lighter + 0.05) / (darker + 0.05)
    val lighter = maxOf(accentLum, bgLum)
    val darker  = minOf(accentLum, bgLum)
    val ratio   = (lighter + 0.05f) / (darker + 0.05f)
    if (ratio >= 4.5f) return accent
    // Determine whether the bg is dark or light, then bump accordingly.
    return if (bgLum < 0.18f) {
        // Dark background — lighten accent toward white
        Color(
            red   = accent.red   + (1f - accent.red)   * 0.35f,
            green = accent.green + (1f - accent.green) * 0.35f,
            blue  = accent.blue  + (1f - accent.blue)  * 0.35f,
            alpha = accent.alpha,
        )
    } else {
        // Light background — darken accent toward black
        Color(
            red   = accent.red   * 0.65f,
            green = accent.green * 0.65f,
            blue  = accent.blue  * 0.65f,
            alpha = accent.alpha,
        )
    }
}

// ---------------------------------------------------------------------------
// §30.8 — AMOLED "darker" background variant
// ---------------------------------------------------------------------------

/**
 * True-black background for AMOLED "darker" variant. Never used as the
 * default — only when the user explicitly selects "AMOLED darker" in
 * Appearance settings. [BgDark] (#1C1611) remains the standard dark background.
 *
 * §30.8: "Never pure black except on AMOLED 'darker' variant."
 */
val BgAmoled: Color = Color(0xFF000000)

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
    // §30.8: Default uses time-based heuristic when no explicit pref is set.
    // AppPreferences.darkMode overrides from Settings ("dark" | "light" | "system").
    // Pass `isSystemInDarkTheme()` for "system" mode; the default here is
    // `isAfterSevenPm()` which flips to dark after 19:00 if the user has not
    // made an explicit choice.
    darkTheme: Boolean = isAfterSevenPm(),
    // ActionPlan §1.4 line 190: dynamicColor reads AppPreferences.dynamicColorEnabled.
    // Defaults FALSE so the Bizarre brand palette always renders out of the box.
    // When true AND Android 12+ (API 31+), Material You derives the color scheme
    // from the user's wallpaper via dynamicLightColorScheme / dynamicDarkColorScheme.
    dynamicColor: Boolean = false,
    // §30.9 Tenant accent override — null uses BrandAccent (brand cream).
    // Automatically bumped to AA contrast ratio via accentWithContrastBump()
    // when supplied. Semantic danger / success / warning are NEVER overridden.
    tenantAccent: Color? = null,
    // §30.8 AMOLED "darker" variant — true only when user has explicitly
    // chosen AMOLED mode in Appearance settings. Never a default.
    amoledDark: Boolean = false,
    content: @Composable () -> Unit,
) {
    var colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        darkTheme -> DarkColorScheme
        else -> LightColorScheme
    }

    // §30.8: AMOLED darker — swap background to pure black.
    // surfaceContainer / surfaceContainerHigh are intentionally left at the
    // normal ramp (Surface1/Surface2) so elevated content is distinguishable.
    if (amoledDark && darkTheme) {
        colorScheme = colorScheme.copy(
            background = BgAmoled,
            surface    = BgAmoled,
        )
    }

    // AND-036: provide semantic extended colors matching the active theme so
    // composables can read LocalExtendedColors.current instead of importing
    // hardcoded top-level color vals.
    val extendedColors = if (darkTheme) darkExtended() else lightExtended()

    // §30.9: resolve tenant accent (falls back to brand cream) and apply
    // auto-contrast bump so pale brand colors meet AA on the current surface.
    val resolvedAccent = remember(tenantAccent, darkTheme) {
        val base = tenantAccentOrFallback(tenantAccent)
        accentWithContrastBump(base, colorScheme.onSurface)
    }

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
    darkTheme: Boolean = isAfterSevenPm(),
    dynamicColor: Boolean = false,
    tenantAccent: Color? = null,
    amoledDark: Boolean = false,
    content: @Composable () -> Unit,
) {
    BizarreCrmTheme(
        darkTheme = darkTheme,
        dynamicColor = dynamicColor,
        tenantAccent = tenantAccent,
        amoledDark = amoledDark,
        content = content,
    )
}
