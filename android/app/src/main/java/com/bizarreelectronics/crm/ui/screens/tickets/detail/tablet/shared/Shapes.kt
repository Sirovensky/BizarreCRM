package com.bizarreelectronics.crm.ui.screens.tickets.detail.tablet.shared

import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.MaterialShapes
import androidx.compose.material3.toShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Shape

/**
 * M3-Expressive cookie-shape avatar helper.
 *
 * Returns `MaterialShapes.Cookie9Sided.toShape()` — a softly scalloped
 * 9-sided rounded square. Already proven at `PosEntryScreen.kt:749`
 * for the POS entry hero icon; the customer-card avatar reuses the
 * same idiom so the brand shape token reads consistently across
 * surfaces.
 *
 * Composable wrapper so the experimental opt-in lives once at the
 * helper instead of every call site. Memoised with [remember] because
 * `toShape()` allocates a `Path` internally.
 */
@Composable
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
internal fun cookieAvatarShape(): Shape {
    val shape = MaterialShapes.Cookie9Sided.toShape()
    return remember(shape) { shape }
}
