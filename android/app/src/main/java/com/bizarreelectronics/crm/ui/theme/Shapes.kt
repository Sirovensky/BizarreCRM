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
 * Expressive FAB shape — diagonal cut corner (Material 3 Expressive style).
 *
 * §30.2: FAB and emphasis buttons use a cut-corner or fully-rounded shape to
 * visually differentiate the primary action from body content. [ConcaveFabShape]
 * is the brand-opinionated choice — the 16 dp cut reads as assertive and
 * unusual, reinforcing Bizarre Electronics' brand character.
 *
 * Use this on [FloatingActionButton] and primary emphasis CTAs:
 * ```kotlin
 * FloatingActionButton(shape = ConcaveFabShape) { ... }
 * BrandPrimaryButton(shape = ConcaveFabShape) { ... }  // high-emphasis CTA
 * ```
 *
 * See also [FullRoundShape] for the softer 50% alternative.
 */
val ConcaveFabShape = CutCornerShape(16.dp)

/**
 * Full-round FAB shape — 50% corner radius (pill / circle for square FABs).
 *
 * §30.2 alternative: use when the brand expression calls for a softer, more
 * approachable feel (e.g. the on-boarding floating button). For the primary
 * ticket-list FAB, prefer [ConcaveFabShape].
 *
 * Example:
 * ```kotlin
 * FloatingActionButton(shape = FullRoundShape) { ... }
 * ```
 */
val FullRoundShape = RoundedCornerShape(50)
