package com.bizarreelectronics.crm.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

// Brand colors
val Blue600 = Color(0xFF2563EB)
val Blue700 = Color(0xFF1D4ED8)
val Blue50 = Color(0xFFEFF6FF)
val Green600 = Color(0xFF16A34A)
val Red600 = Color(0xFFDC2626)
val Amber500 = Color(0xFFF59E0B)
// Semantic colors (use these instead of hardcoding hex values)
val SuccessGreen = Color(0xFF16A34A)
val ErrorRed = Color(0xFFDC2626)
val WarningAmber = Color(0xFFF59E0B)
val InfoBlue = Color(0xFF2563EB)
val WarningBg = Color(0xFFFEF3C7)
val WarningText = Color(0xFF92400E)
val SuccessBg = Color(0xFFF0FDF4)
val ErrorBg = Color(0xFFFEE2E2)
val StarYellow = Color(0xFFFBBF24)
val RefundedPurple = Color(0xFF8B5CF6)
val OutOfStockOrange = Color(0xFFE65100)
val ConditionAmberBg = Color(0xFFFFF3E0)
val ConditionAmberText = Color(0xFFE65100)

/**
 * Returns Color.Black or Color.White based on perceived brightness of the background color.
 * Uses the W3C luminance formula: (R*299 + G*587 + B*114) / 1000.
 */
fun contrastTextColor(bgColor: Color): Color {
    val brightness = (bgColor.red * 299f + bgColor.green * 587f + bgColor.blue * 114f) / 1000f
    return if (brightness > 0.5f) Color.Black else Color.White
}

val Surface50 = Color(0xFFF8FAFC)
val Surface100 = Color(0xFFF1F5F9)
val Surface200 = Color(0xFFE2E8F0)
val Surface700 = Color(0xFF334155)
val Surface800 = Color(0xFF1E293B)
val Surface900 = Color(0xFF0F172A)

private val LightColorScheme = lightColorScheme(
    primary = Blue600,
    onPrimary = Color.White,
    primaryContainer = Blue50,
    onPrimaryContainer = Blue700,
    secondary = Green600,
    onSecondary = Color.White,
    error = Red600,
    onError = Color.White,
    background = Surface50,
    onBackground = Surface900,
    surface = Color.White,
    onSurface = Surface900,
    surfaceVariant = Surface100,
    onSurfaceVariant = Surface700,
    outline = Surface200,
)

private val DarkColorScheme = darkColorScheme(
    primary = Color(0xFF60A5FA), // Blue 400
    onPrimary = Color(0xFF1E3A5F),
    primaryContainer = Color(0xFF1E3A5F),
    onPrimaryContainer = Color(0xFF93C5FD),
    secondary = Color(0xFF4ADE80),
    onSecondary = Color(0xFF14532D),
    error = Color(0xFFF87171),
    onError = Color(0xFF7F1D1D),
    background = Surface900,
    onBackground = Color(0xFFE2E8F0),
    surface = Surface800,
    onSurface = Color(0xFFE2E8F0),
    surfaceVariant = Surface700,
    onSurfaceVariant = Color(0xFFCBD5E1),
    outline = Color(0xFF475569),
)

@Composable
fun BizarreCrmTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = true,
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

    MaterialTheme(
        colorScheme = colorScheme,
        typography = BizarreTypography,
        content = content,
    )
}
