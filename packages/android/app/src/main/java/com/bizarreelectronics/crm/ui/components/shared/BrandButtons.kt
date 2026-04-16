package com.bizarreelectronics.crm.ui.components.shared

import androidx.compose.foundation.layout.RowScope
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

/**
 * Brand button system — thin wrappers that default-wire the correct color
 * and typography tokens from Theme.kt. Wave 3 agents call these instead
 * of raw Material buttons with per-site color overrides.
 *
 * ## Button hierarchy
 * | Composable              | Use case                                               |
 * |-------------------------|--------------------------------------------------------|
 * | [BrandPrimaryButton]    | Primary CTA — purple filled (`primary` container)      |
 * | [BrandSecondaryButton]  | Secondary action — purple outlined, no fill            |
 * | [BrandTextButton]       | Ghost / tertiary action — teal text, no border/fill    |
 * | [BrandDestructiveButton]| Destructive only — error-red fill (sign out, clear)    |
 *
 * ## Migration note for Wave 3
 * Most `ButtonDefaults.buttonColors(containerColor = ...)` overrides across
 * ~20 screens should be replaced by the appropriate wrapper here. If a call
 * site already uses the default `Button { }` with no color override and
 * Theme.kt is correct, no migration is needed — the theme already wires
 * purple primary. Audit with:
 * ```
 * grep -r "buttonColors\|containerColor" --include="*.kt" packages/android
 * ```
 *
 * ## Destructive sites (Wave 3)
 * - SettingsScreen.kt:291 (Sign Out)
 * - ClockInOutScreen.kt:255 ("C" clear-pin)
 */

/**
 * Primary CTA button. Purple fill from `colorScheme.primary` (default from
 * theme — no override needed after Theme.kt lands). Included as an explicit
 * wrapper so call sites read intent clearly.
 */
@Composable
fun BrandPrimaryButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    content: @Composable RowScope.() -> Unit,
) {
    Button(
        onClick = onClick,
        modifier = modifier,
        enabled = enabled,
        // colors default to theme primary — no override needed
        content = content,
    )
}

/**
 * Secondary / outlined button. Purple outline + purple text, no fill.
 */
@Composable
fun BrandSecondaryButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    content: @Composable RowScope.() -> Unit,
) {
    OutlinedButton(
        onClick = onClick,
        modifier = modifier,
        enabled = enabled,
        // OutlinedButton default tints outline + text with primary (purple) via theme
        content = content,
    )
}

/**
 * Ghost / text button. Teal text, no border or fill.
 * Use for tertiary, info, and link-style actions.
 */
@Composable
fun BrandTextButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    content: @Composable RowScope.() -> Unit,
) {
    TextButton(
        onClick = onClick,
        modifier = modifier,
        enabled = enabled,
        colors = ButtonDefaults.textButtonColors(
            contentColor = MaterialTheme.colorScheme.secondary, // teal
        ),
        content = content,
    )
}

/**
 * Destructive button. Error-red fill. Use ONLY for genuinely destructive
 * actions (delete, clear, sign out). Do not use for normal navigation or
 * cancel actions — use [BrandTextButton] for those.
 */
@Composable
fun BrandDestructiveButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    content: @Composable RowScope.() -> Unit,
) {
    Button(
        onClick = onClick,
        modifier = modifier,
        enabled = enabled,
        colors = ButtonDefaults.buttonColors(
            containerColor = MaterialTheme.colorScheme.error,
            contentColor = MaterialTheme.colorScheme.onError,
        ),
        content = content,
    )
}
