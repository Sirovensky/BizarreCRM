package com.bizarreelectronics.crm.ui.screens.tickets.detail.tablet.shared

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.unit.dp

/**
 * M3 Expressive shape for the tablet ticket-detail Status pill.
 *
 * Asymmetric corner radii — `topLeft` + `bottomRight` round at 22.dp,
 * `topRight` + `bottomLeft` round at 8.dp. Reads as the brand-shape
 * token rather than a generic capsule. Used by `TabletTopAppBar` and
 * could be animated on press for the M3-Expressive shape-morph
 * effect; the static form is the v1 baseline.
 */
internal val AsymmetricStatusShape = RoundedCornerShape(
    topStart = 22.dp,
    topEnd = 8.dp,
    bottomEnd = 22.dp,
    bottomStart = 8.dp,
)
