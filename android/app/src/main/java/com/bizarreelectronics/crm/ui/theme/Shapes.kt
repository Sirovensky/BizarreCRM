package com.bizarreelectronics.crm.ui.theme

import androidx.compose.foundation.shape.CutCornerShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Shapes
import androidx.compose.ui.unit.dp

/**
 * Bizarre CRM shape tokens — ActionPlan §1.4 line 191.
 *
 * Material3 [Shapes] covers five named sizes; we fill all of them so every
 * themed component (Button, Card, Dialog, FAB, Chip, BottomSheet, etc.) resolves
 * to a consistent corner radius without explicit per-site overrides.
 *
 * Token mapping:
 *   extraSmall  =  4dp  — text fields, input chips
 *   small       =  4dp  — snackbars, badges
 *   medium      = 12dp  — buttons, cards (matches previous default, see Theme.kt history)
 *   large       = 16dp  — bottom sheets, dialogs
 *   extraLarge  = 28dp  — FAB, full-screen cards
 *
 * [ConcaveFabShape] is a CutCornerShape(16.dp) used for emphasis FABs — the
 * diagonal cut adds visual distinction from regular rounded FABs.
 *
 * [BizarreShapes] is the canonical export. Theme.kt wires it into
 * MaterialTheme.shapes so callers using `MaterialTheme.shapes.medium` etc.
 * get the full branded token set automatically.
 */
val BizarreShapes = Shapes(
    extraSmall = RoundedCornerShape(4.dp),
    small      = RoundedCornerShape(4.dp),
    medium     = RoundedCornerShape(12.dp),
    large      = RoundedCornerShape(16.dp),
    extraLarge = RoundedCornerShape(28.dp),
)

/**
 * Emphasis FAB shape — diagonal cut corner for visual differentiation.
 * Use on the primary action FAB where extra attention-grabbing is desired.
 *
 * Example:
 * ```kotlin
 * FloatingActionButton(shape = ConcaveFabShape) { ... }
 * ```
 */
val ConcaveFabShape = CutCornerShape(16.dp)
