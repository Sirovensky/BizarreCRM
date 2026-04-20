package com.bizarreelectronics.crm.ui.components.shared

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.RowScope
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * Brand button system — thin wrappers that default-wire the correct color,
 * shape, and typography tokens from Theme.kt. Screens call these instead
 * of raw Material buttons with per-site color overrides so primary-vs-
 * secondary action hierarchy is consistent everywhere.
 *
 * CROSS48: the historical "filled vs outlined" mismatch across screens
 * (Call = orange filled, SMS = outlined; ticket wizard "Continue" filled;
 * service pills outlined; etc.) is now resolved at the wrapper layer.
 *
 * ## Button hierarchy
 * | Composable              | Use case                                               |
 * |-------------------------|--------------------------------------------------------|
 * | [BrandPrimaryButton]    | Primary CTA — orange filled (`primary` container)      |
 * | [BrandSecondaryButton]  | Secondary action — orange outlined, no fill            |
 * | [BrandTertiaryButton]   | Tertiary/text action — orange text, no border/fill     |
 * | [BrandTextButton]       | (Legacy alias for [BrandTertiaryButton])               |
 * | [BrandDestructiveButton]| Destructive only — error-red fill (sign out, clear)    |
 *
 * ## Adoption (CROSS48)
 * Incremental. The two most painful mismatches are adopted now
 * (CustomerDetailScreen Call/SMS + LoginScreen Sign In). Future sweeps
 * can migrate the remaining raw `Button { }` / `OutlinedButton { }` /
 * `TextButton { }` call sites — the default `colorScheme.primary` already
 * resolves correctly via Theme.kt, but explicit wrappers make intent legible.
 */

/**
 * Primary CTA. Orange `primary` container, `onPrimary` text, 12dp theme shape
 * (BizarreShapes.medium via Theme.kt). Use for the single dominant action
 * on a screen or section (Sign In, Save, Create, Call).
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
        shape = MaterialTheme.shapes.medium,
        colors = ButtonDefaults.buttonColors(
            containerColor = MaterialTheme.colorScheme.primary,
            contentColor = MaterialTheme.colorScheme.onPrimary,
        ),
        content = content,
    )
}

/**
 * Secondary action. Orange 1dp outline, orange text, no fill, 12dp theme
 * shape. Use for peer actions to a primary CTA (SMS next to Call, Cancel
 * next to Save).
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
        shape = MaterialTheme.shapes.medium,
        colors = ButtonDefaults.outlinedButtonColors(
            contentColor = MaterialTheme.colorScheme.primary,
        ),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.primary),
        content = content,
    )
}

/**
 * Tertiary / text action. Orange text, no border or fill. Use for link-
 * style and lowest-hierarchy actions (Forgot password, View all, etc.).
 */
@Composable
fun BrandTertiaryButton(
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
            contentColor = MaterialTheme.colorScheme.primary,
        ),
        content = content,
    )
}

/**
 * Legacy text-button alias — the original [BrandTextButton] pointed at
 * the teal secondary palette. CROSS48 deprecates that in favour of the
 * primary-tinted [BrandTertiaryButton]. Kept as an alias so existing
 * call sites (EmptyState actions, dialog dismiss, etc.) keep compiling;
 * new code should call [BrandTertiaryButton] directly.
 */
@Composable
fun BrandTextButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    content: @Composable RowScope.() -> Unit,
) {
    BrandTertiaryButton(
        onClick = onClick,
        modifier = modifier,
        enabled = enabled,
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
