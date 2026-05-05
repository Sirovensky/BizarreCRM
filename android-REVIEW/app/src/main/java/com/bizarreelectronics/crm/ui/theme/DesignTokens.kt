package com.bizarreelectronics.crm.ui.theme

import androidx.compose.ui.unit.dp

/**
 * Bizarre CRM design tokens — ActionPlan §30.10.
 *
 * Single source of truth for spacing, radius, elevation, and semantic color
 * aliases used across all UI layers. Screens must use these tokens instead of
 * inline `dp` literals or raw `Color(0x…)` values so that a future design
 * system update only requires touching this file.
 *
 * ## Spacing
 * All padding / gap values are multiples of a 4 dp base grid.
 *
 * | Token | dp  | Typical use                              |
 * |-------|-----|------------------------------------------|
 * | xxs   |  2  | Micro gap between icon and inline label  |
 * | xs    |  4  | Chip internal padding, dense row gap     |
 * | sm    |  8  | List item internal gap, button padding   |
 * | md    | 12  | Card inner spacing, section gap          |
 * | lg    | 16  | Screen horizontal margin                 |
 * | xl    | 20  | Card vertical padding, section padding   |
 * | xxl   | 24  | Sheet handle space, divider              |
 * | xxxl  | 32  | Empty-state inner padding                |
 * | huge  | 48  | Hero art gap, onboarding vertical pad    |
 *
 * ## Radius — mirrors §30.2 BizarreShapes
 * Use [BizarreShapes] via [MaterialTheme.shapes] for themed components (Button,
 * Card, Dialog). These constants are for callers that need a raw [Dp] value
 * (e.g. [Modifier.clip], [RoundedCornerShape] on a custom composable).
 *
 * ## Shadow elevation table
 * Material 3 uses tonal elevation (color tone shift) rather than drop shadows.
 * Numeric dp values here match the M3 "elevation overlay" levels that produce
 * visible tone shifts on the warm-dark surface ramp:
 *
 * | Level  | dp | Component                        |
 * |--------|----|----------------------------------|
 * | none   | 0  | flat cards, list rows            |
 * | low    | 1  | chip, badge                      |
 * | medium | 3  | bottom-nav, top-app-bar          |
 * | high   | 6  | FAB, selected card               |
 * | modal  | 8  | bottom sheet, dialog             |
 *
 * ## Semantic color aliases
 * Use [LocalExtendedColors] in Compose for theme-aware access. These `val`
 * references provide a stable named import for callers that build objects
 * outside of Compose (e.g. ViewModel state classes). They always resolve to
 * the dark-theme value because the app defaults to dark; callers that need
 * light-theme equivalents must read [LocalExtendedColors].
 *
 * ## Lint rule
 * A custom Lint check (`:lint-rules`) flags inline `Color(0x…)` literals and
 * raw `.dp` literals outside token files. Suppress with `@SuppressLint("InlineColor")`
 * only when you have a documented reason (e.g. dynamic hex from server).
 */
object DesignTokens {

    // -------------------------------------------------------------------------
    // Spacing
    // -------------------------------------------------------------------------

    object Spacing {
        /** 2 dp — micro gap, icon-to-inline-label */
        val xxs = 2.dp
        /** 4 dp — chip padding, dense row gap */
        val xs  = 4.dp
        /** 8 dp — list item gap, button padding */
        val sm  = 8.dp
        /** 12 dp — card inner spacing, section gap */
        val md  = 12.dp
        /** 16 dp — screen horizontal margin */
        val lg  = 16.dp
        /** 20 dp — card vertical padding */
        val xl  = 20.dp
        /** 24 dp — sheet handle space, divider */
        val xxl = 24.dp
        /** 32 dp — empty-state inner padding */
        val xxxl = 32.dp
        /** 48 dp — hero art gap, onboarding vertical pad */
        val huge = 48.dp
    }

    // -------------------------------------------------------------------------
    // Radius
    // -------------------------------------------------------------------------

    object Radius {
        /** 4 dp — text fields, input chips, badges (extraSmall) */
        val extraSmall = 4.dp
        /** 4 dp — snackbars (small) */
        val small      = 4.dp
        /** 12 dp — buttons, cards (medium) */
        val medium     = 12.dp
        /** 16 dp — bottom sheets, dialogs (large) */
        val large      = 16.dp
        /** 28 dp — FAB, full-screen cards (extraLarge) */
        val extraLarge = 28.dp
        /** Full circle (50%) — use with percent-based RoundedCornerShape(50) */
        val full       = 50 // percent — use RoundedCornerShape(full)
    }

    // -------------------------------------------------------------------------
    // Shadow / tonal elevation (dp)
    // -------------------------------------------------------------------------

    object Elevation {
        /** 0 dp — flat cards, list rows */
        val none   = 0.dp
        /** 1 dp — chip, badge */
        val low    = 1.dp
        /** 3 dp — bottom-nav, top-app-bar */
        val medium = 3.dp
        /** 6 dp — FAB, selected card */
        val high   = 6.dp
        /** 8 dp — bottom sheet, dialog */
        val modal  = 8.dp
    }

    // -------------------------------------------------------------------------
    // AMOLED palette
    // -------------------------------------------------------------------------

    /**
     * True black for the optional AMOLED "darker" variant (§30.8).
     *
     * Use ONLY when the user has explicitly opted into the AMOLED mode.
     * Regular dark mode uses [BgDark] (`0xFF1C1611`) which is a warm near-black,
     * never pure black.  AMOLED mode is a future Settings toggle — tracked in
     * TODO.md. Until the Settings toggle lands, reference this token but do NOT
     * apply it to any live surface.
     */
    val amoledBackground = androidx.compose.ui.graphics.Color(0xFF000000)

    // -------------------------------------------------------------------------
    // Semantic color stable references (dark-theme values — see kdoc above)
    // -------------------------------------------------------------------------

    /** Brand accent cream — same as [BrandAccent] / `DarkColorScheme.primary`. */
    val brandAccent    = BrandAccent          // 0xFFFDEED0

    /** Semantic danger — hue-shifted brand error red. */
    val brandDanger    = ErrorRed             // 0xFFE2526C

    /** Semantic warning — warm amber. */
    val brandWarning   = WarningAmber         // 0xFFE8A33D

    /** Semantic success — cool green. */
    val brandSuccess   = SuccessGreen         // 0xFF34C47E

    /** Semantic info — teal. */
    val brandInfo      = InfoBlue             // 0xFF4DB8C9
}
