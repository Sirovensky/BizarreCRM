package com.bizarreelectronics.crm.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.bizarreelectronics.crm.R

// ---------------------------------------------------------------------------
// Font families — Wave 1 brand foundation
//
// Inter          → body/UI font (400/500/600/700)
// Barlow Condensed SemiBold → display (headlineLarge / headlineMedium ONLY)
// JetBrains Mono → mono (ticket IDs, SKUs, TOTP codes, backup codes)
//
// Fonts are bundled in app/src/main/res/font/ (downloaded from Google Fonts
// via curl during Wave 1). Source: fonts.gstatic.com / Inter v20,
// BarlowCondensed v13, JetBrainsMono v24.
// ---------------------------------------------------------------------------

val InterFamily = FontFamily(
    Font(R.font.inter_regular,  FontWeight.Normal),
    Font(R.font.inter_medium,   FontWeight.Medium),
    Font(R.font.inter_semibold, FontWeight.SemiBold),
    Font(R.font.inter_bold,     FontWeight.Bold),
)

val BarlowCondensedFamily = FontFamily(
    Font(R.font.barlow_condensed_semibold, FontWeight.SemiBold),
)

val JetBrainsMonoFamily = FontFamily(
    Font(R.font.jetbrains_mono_regular, FontWeight.Normal),
    Font(R.font.jetbrains_mono_medium,  FontWeight.Medium),
)

/**
 * BrandMono — centralized mono text style for ticket IDs, SKUs, TOTP codes,
 * backup codes, barcode values, and any other fixed-width data display.
 *
 * Usage: `MaterialTheme.typography.labelLarge.copy(fontFamily = BrandMono)`
 * or reference BrandMono directly for standalone Text composables.
 *
 * Migration targets (Wave 3+):
 *   - LoginScreen.kt:468-471   (backup codes — currently FontFamily.Monospace)
 * *   - LoginScreen.kt:1010-1015 (TOTP input)
 *   - SmsThreadScreen.kt:238-244 (character counter)
 */
val BrandMono: TextStyle = TextStyle(
    fontFamily = JetBrainsMonoFamily,
    fontWeight = FontWeight.Normal,
    fontSize = 13.sp,
    lineHeight = 18.sp,
    letterSpacing = 0.5.sp,
)

// ---------------------------------------------------------------------------
// Typography scale
//
// headlineLarge / headlineMedium → BarlowCondensedFamily (display/section headers)
// ALL other slots                → InterFamily (body/UI)
//
// Do NOT apply ALL-CAPS globally. Reserve sentence-case everywhere except
// sanctioned ALL-CAPS locations (see androidUITODO.md §2 MoreScreen).
// ---------------------------------------------------------------------------

val BizarreTypography = Typography(
    headlineLarge = TextStyle(
        fontFamily = BarlowCondensedFamily,
        fontWeight = FontWeight.SemiBold,
        fontSize = 28.sp,
        lineHeight = 36.sp,
    ),
    headlineMedium = TextStyle(
        fontFamily = BarlowCondensedFamily,
        fontWeight = FontWeight.SemiBold,
        fontSize = 24.sp,
        lineHeight = 32.sp,
    ),
    headlineSmall = TextStyle(
        fontFamily = BarlowCondensedFamily,
        fontWeight = FontWeight.SemiBold,
        fontSize = 24.sp,
        lineHeight = 32.sp,
        letterSpacing = 0.sp,
    ),
    titleLarge = TextStyle(
        fontFamily = InterFamily,
        fontWeight = FontWeight.SemiBold,
        fontSize = 20.sp,
        lineHeight = 28.sp,
    ),
    titleMedium = TextStyle(
        fontFamily = InterFamily,
        fontWeight = FontWeight.Medium,
        fontSize = 16.sp,
        lineHeight = 24.sp,
    ),
    titleSmall = TextStyle(
        fontFamily = InterFamily,
        fontWeight = FontWeight.Medium,
        fontSize = 14.sp,
        lineHeight = 20.sp,
    ),
    bodyLarge = TextStyle(
        fontFamily = InterFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 16.sp,
        lineHeight = 24.sp,
    ),
    bodyMedium = TextStyle(
        fontFamily = InterFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 14.sp,
        lineHeight = 20.sp,
    ),
    bodySmall = TextStyle(
        fontFamily = InterFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 12.sp,
        lineHeight = 16.sp,
    ),
    labelLarge = TextStyle(
        fontFamily = InterFamily,
        fontWeight = FontWeight.Medium,
        fontSize = 14.sp,
        lineHeight = 20.sp,
    ),
    labelMedium = TextStyle(
        fontFamily = InterFamily,
        fontWeight = FontWeight.Medium,
        fontSize = 12.sp,
        lineHeight = 16.sp,
        letterSpacing = 0.5.sp,
    ),
    labelSmall = TextStyle(
        fontFamily = InterFamily,
        fontWeight = FontWeight.Medium,
        fontSize = 12.sp,
        lineHeight = 16.sp,
    ),
)
