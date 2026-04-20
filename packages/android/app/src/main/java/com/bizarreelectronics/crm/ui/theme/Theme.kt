package com.bizarreelectronics.crm.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp

// ---------------------------------------------------------------------------
// Primitive palette — Wave 1 brand foundation
// ---------------------------------------------------------------------------

// Brand primaries (kept as named tokens so callers that import them directly
// keep compiling; they are retuned to the Bizarre palette).
// CROSS19/BRAND: primary accent is ORANGE from the logo, not purple/magenta.
// Earlier commits shipped a purple palette — user directive 2026-04-17 is that
// orange is the canonical brand accent. Teal secondary + magenta decorative
// tertiary remain in place; only primary changes.
val Blue600 = Color(0xFFF58220)   // logo orange — primary accent
val Blue700 = Color(0xFF2B1400)   // very dark brown — onPrimary for contrast
val Blue50  = Color(0xFF4A2B0C)   // dark muted orange — primaryContainer
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
val RefundedPurple    = Color(0xFFF58220)  // token name kept for API; value follows primary (orange)
val OutOfStockOrange  = Color(0xFFE8A33D)  // retuned to WarningAmber family
val ConditionAmberBg  = Color(0xFF2B1F0A)  // dark-mode amber bg
val ConditionAmberText = Color(0xFFE8A33D)

// ---------------------------------------------------------------------------
// Warm dark surface ramp
// ---------------------------------------------------------------------------
val BgDark        = Color(0xFF121017)  // background
val Surface1      = Color(0xFF1A1722)  // surface / primary surface
val Surface2      = Color(0xFF241F2E)  // elevated surface
val OutlineColor  = Color(0xFF332C3F)  // dividers / borders
val MutedText     = Color(0xFFA79FB8)  // onSurfaceVariant muted
val PrimaryText   = Color(0xFFECE9F3)  // onBackground / onSurface

// Light-mode surface ramp (retained for when user toggles light)
val Surface50  = Color(0xFFF8F6FF)  // slightly warm white
val Surface100 = Color(0xFFEFEBFF)
val Surface200 = Color(0xFFDDD6F7)
val Surface700 = Color(0xFF4A4265)
val Surface800 = Color(0xFF1A1722)
val Surface900 = Color(0xFF121017)

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
    primary              = Color(0xFFC86500),   // orange shifted darker for light-bg AA
    onPrimary            = Color(0xFFFFFFFF),
    primaryContainer     = Color(0xFFFFDCB8),   // light peach container
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
    surface              = Color.White,
    onSurface            = Surface900,
    surfaceVariant       = Surface100,
    onSurfaceVariant     = Surface700,
    surfaceContainer     = Surface100,
    surfaceContainerHigh = Surface200,
    outline              = Surface200,
)

private val DarkColorScheme = darkColorScheme(
    primary              = Color(0xFFF58220),   // logo orange — primary accent
    onPrimary            = Color(0xFF2B1400),   // near-black brown for contrast on orange
    primaryContainer     = Color(0xFF4A2B0C),   // dark muted orange container
    onPrimaryContainer   = Color(0xFFFFD4B5),   // light peach text on container
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
// Shapes — CROSS33 brand shape tokens
// ---------------------------------------------------------------------------

/**
 * Shape tokens unify every surface + button across the app. Material3's
 * default `Shapes.medium` (12.dp rounded corners) is used by `Button`,
 * `OutlinedButton`, `Card`, `FilterChip`, etc. — which is why the previous
 * implicit mix (fully-rounded pill CTAs like "Continue to Details" vs
 * rectangular rounded buttons like "Sign In") happened: components fell
 * back to their library default instead of a theme-wide value.
 *
 * Locking `medium = RoundedCornerShape(12.dp)` here makes every themed
 * button resolve to the same 12dp radius unless a site explicitly opts
 * out by passing `shape = ...` to the component.
 *
 * Primary `Button` uses `shapes.medium` by default, so this wipes out the
 * pill/rectangle inconsistency without touching individual screens.
 *
 * `small` / `extraLarge` are left at their Material3 defaults (4dp/28dp)
 * because Wave 1 cards + chips already visually anchor to those sizes.
 */
private val BizarreShapes = Shapes(
    medium = RoundedCornerShape(12.dp),
)

// ---------------------------------------------------------------------------
// Theme entry point
// ---------------------------------------------------------------------------

@Composable
fun BizarreCrmTheme(
    // Default is true — dark-first. AppPreferences.darkMode overrides from
    // Settings ("dark" | "light" | "system"). Wave 3 wires the Settings toggle;
    // this stub reads the pref so the toggle hook is wired even though the UI
    // doesn't exist yet.
    darkTheme: Boolean = true,
    // Dynamic color disabled by default so the Bizarre scheme always renders.
    // A power-user could pass true to re-enable Material You on Android 12+.
    dynamicColor: Boolean = false,
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

    CompositionLocalProvider(LocalExtendedColors provides extendedColors) {
        MaterialTheme(
            colorScheme = colorScheme,
            typography = BizarreTypography,
            shapes = BizarreShapes,
            content = content,
        )
    }
}
