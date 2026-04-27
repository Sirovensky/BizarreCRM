package com.bizarreelectronics.crm.ui.theme

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Bizarre CRM design tokens — ActionPlan §30.10.
 *
 * Single source of truth for spacing, radius, shadow elevation, and semantic
 * color aliases. Call sites should import from here rather than using inline
 * `dp` literals or `Color(0x…)` constants.
 *
 * ## Lint enforcement
 * A future detekt / lint rule will flag inline `Color(0x…)` and inline dp
 * literals outside this file and the five theme kt files.  The rule is
 * tracked as a separate TODO — wiring it requires a custom lint module.
 */

// ---------------------------------------------------------------------------
// Spacing — named steps following a 4dp grid
// ---------------------------------------------------------------------------

/**
 * Spacing tokens. All UI padding / margin / gap values should reference one of
 * these rather than a bare `N.dp` literal.
 *
 * Scale: xxs=2, xs=4, sm=8, md=12, lg=16, xl=20, xxl=24, xxxl=32, huge=48
 */
object Spacing {
    /** 2dp — icon-to-label micro gaps, badge internal padding. */
    val xxs: Dp = 2.dp
    /** 4dp — tight internal padding, chip horizontal padding. */
    val xs: Dp = 4.dp
    /** 8dp — standard intra-component spacing. */
    val sm: Dp = 8.dp
    /** 12dp — card internal padding (compact), list item vertical padding. */
    val md: Dp = 12.dp
    /** 16dp — default content padding, screen edge margin. */
    val lg: Dp = 16.dp
    /** 20dp — dialog internal padding, section gap. */
    val xl: Dp = 20.dp
    /** 24dp — section-to-section gap, bottom sheet content padding. */
    val xxl: Dp = 24.dp
    /** 32dp — large section separation. */
    val xxxl: Dp = 32.dp
    /** 48dp — hero / full-bleed component padding. */
    val huge: Dp = 48.dp
}

// ---------------------------------------------------------------------------
// Radius — matches §30.2 BizarreShapes tokens
// ---------------------------------------------------------------------------

/**
 * Corner radius tokens. These mirror [BizarreShapes] but as raw [Dp] values
 * for use in non-M3 contexts (Canvas drawing, custom shapes, shimmer clips).
 */
object Radius {
    /** 4dp — text fields, input chips. */
    val xs: Dp = 4.dp
    /** 8dp — snackbars, badges. */
    val sm: Dp = 8.dp
    /** 16dp — buttons, cards (BizarreShapes.medium). */
    val md: Dp = 16.dp
    /** 24dp — bottom sheets, dialogs (BizarreShapes.large). */
    val lg: Dp = 24.dp
    /** 32dp — FAB, full-screen cards (BizarreShapes.extraLarge). */
    val xl: Dp = 32.dp
}

// ---------------------------------------------------------------------------
// Shadow / tonal elevation table — §30.10
//
// Material 3 uses tonal (color) elevation rather than drop-shadows.  The table
// below maps M3 elevation levels to dp values for the rare cases where a real
// shadow is required (e.g. FAB drop-shadow, floating filter chips).
//
// Rule: no drop-shadows except on FABs (elevation level 3 = 6dp).
// ---------------------------------------------------------------------------

/**
 * Elevation tokens for surfaces and elevated components.
 *
 * Tonal elevation is the default (handled by [MaterialTheme.colorScheme]
 * surfaceTint). Use these [Dp] values only where a physical elevation /
 * shadow is explicitly required (FABs, contextual menus).
 */
object Elevation {
    /** 0dp — flat surface, no shadow. */
    val none: Dp = 0.dp
    /** 1dp — resting card. */
    val level1: Dp = 1.dp
    /** 3dp — raised card, hovered state. */
    val level2: Dp = 3.dp
    /** 6dp — FAB resting elevation (Material 3 spec). */
    val level3: Dp = 6.dp
    /** 8dp — dropdown menu, snackbar. */
    val level4: Dp = 8.dp
    /** 12dp — dialog. */
    val level5: Dp = 12.dp
}

// ---------------------------------------------------------------------------
// Semantic color aliases — §30.10
//
// These aliases consolidate the top-level vals in Theme.kt so new callers have
// a discoverable, typed entry point. The underlying Color values are the same —
// see Theme.kt for the canonical definitions and rationale.
// ---------------------------------------------------------------------------

/**
 * Brand-semantic color tokens. Read via `DesignTokens.brand*` at call sites.
 *
 * For composables that need theme-aware light/dark variants, use
 * [LocalExtendedColors] instead — these are the dark-mode constants.
 */
object BrandColors {
    /** Primary brand accent — cream `#FDEED0`. */
    val brandAccent: Color   = BrandAccent         // #FDEED0

    /** Error / danger — hue-shifted brand red `#E2526C`. */
    val brandDanger: Color   = ErrorRed            // #E2526C

    /** Warning — retuned amber `#E8A33D`. */
    val brandWarning: Color  = WarningAmber        // #E8A33D

    /** Success — retuned green `#34C47E`. */
    val brandSuccess: Color  = SuccessGreen        // #34C47E

    /** Info — teal `#4DB8C9`. */
    val brandInfo: Color     = InfoBlue            // #4DB8C9
}
