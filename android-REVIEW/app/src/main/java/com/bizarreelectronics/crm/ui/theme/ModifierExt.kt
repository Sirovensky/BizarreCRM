package com.bizarreelectronics.crm.ui.theme

import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.PointerIcon
import androidx.compose.ui.input.pointer.pointerHoverIcon

/**
 * Modifier extensions that centralise cursor / pointer-hover icons so
 * every interactive composable in the app picks up the correct OS cursor
 * on ChromeOS, Samsung DeX, and Android desktop-mode without 20+ scattered
 * call-sites.
 *
 * ChromeOS / Samsung DeX hover-cursor policy (§22.3 non-negotiable):
 *   - Editable text fields  → [PointerIcon.Text]   (I-beam / text caret)
 *   - Buttons / links       → [PointerIcon.Hand]   (pointer / hand)
 *
 * On phone (non-desktop) these modifiers are no-ops — [pointerHoverIcon]
 * only has visible effect when a mouse/trackpad is connected, so applying
 * them unconditionally on all form-factor targets is safe and correct.
 *
 * Usage:
 * ```
 * OutlinedTextField(modifier = Modifier.textFieldHover())
 * TextButton(modifier = Modifier.clickableHover()) { ... }
 * IconButton(modifier = Modifier.clickableHover()) { ... }
 * ```
 *
 * Implementation note: [overrideDescendants] is left at its default value
 * of `false` so child composables (e.g. an [IconButton] inside a field's
 * trailing-icon slot) may override the cursor independently if needed.
 */

/**
 * Applies an I-beam / text-cursor hover icon — correct for any editable
 * text input field ([OutlinedTextField], [TextField], [BasicTextField]).
 */
fun Modifier.textFieldHover(): Modifier = this.pointerHoverIcon(PointerIcon.Text)

/**
 * Applies a hand / pointer-cursor hover icon — correct for any tappable
 * element that is not a text input: [Button], [TextButton], [OutlinedButton],
 * [IconButton], [FilterChip], [AssistChip], clickable rows, etc.
 */
fun Modifier.clickableHover(): Modifier = this.pointerHoverIcon(PointerIcon.Hand)
