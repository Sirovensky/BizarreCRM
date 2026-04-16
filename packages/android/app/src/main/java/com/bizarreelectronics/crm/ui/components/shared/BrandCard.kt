package com.bizarreelectronics.crm.ui.components.shared

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * Brand-aligned card component.
 *
 * Dark theme: surface1 bg (`colorScheme.surface`) + 1px outline border + 14dp radius,
 *             NO elevation shadow (flat on OLED).
 * Light theme: white bg + 1px outline border + 14dp radius.
 *
 * Drop-in replacement for per-screen `Card { ... }` overrides.
 *
 * Wave 3: migrate card call sites that currently override containerColor or
 * elevation — exceptions are the *sanctioned highlight cards* that use
 * primaryContainer (checkout order summary, unread notification rows).
 *
 * @param modifier    Applied to the Card.
 * @param onClick     If non-null, the card is clickable.
 * @param content     Card content (ColumnScope receiver).
 */
@Composable
fun BrandCard(
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val cardColors = CardDefaults.cardColors(
        containerColor = MaterialTheme.colorScheme.surface, // surface1 in dark
    )
    val cardElevation = CardDefaults.cardElevation(
        defaultElevation = 0.dp,
        pressedElevation = 0.dp,
        focusedElevation = 0.dp,
        hoveredElevation = 0.dp,
    )
    val shape = androidx.compose.foundation.shape.RoundedCornerShape(14.dp)
    val border = BorderStroke(
        width = 1.dp,
        color = MaterialTheme.colorScheme.outline,
    )

    if (onClick != null) {
        Card(
            onClick = onClick,
            modifier = modifier,
            shape = shape,
            colors = cardColors,
            elevation = cardElevation,
            border = border,
            content = content,
        )
    } else {
        Card(
            modifier = modifier,
            shape = shape,
            colors = cardColors,
            elevation = cardElevation,
            border = border,
            content = content,
        )
    }
}
