package com.bizarreelectronics.crm.ui.components.shared

import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/**
 * Unified tile atom for the POS flow. Used by:
 *  - POS Home path picker (Retail sale / Create repair / Store credit) — `tall = true` (120dp)
 *  - Check-in TYPE picker (Phone / Tablet / Laptop / TV / Console / Desktop) — default 96dp
 *  - Check-in MAKE picker (Apple / Samsung / Google / ...) — default 96dp
 *  - Check-in MODEL picker (iPhone 15 Pro / ...) — default 96dp
 *  - Symptoms picker (Cracked screen / Battery drain / ...) — default 96dp
 *
 * Visual contract (matches mockup `ios/pos-phone-mockups.html` issues grid):
 *   - Surface bg, RoundedCornerShape(10dp)
 *   - 1dp outline border idle / 1.5dp primary (cream) when selected
 *   - 12dp inner padding, center-aligned column
 *   - Icon 28dp tint primary if selected else onSurfaceVariant
 *   - Title labelMedium bold, color primary if selected else onSurface
 *   - Optional subtitle labelSmall onSurfaceVariant
 *
 * @param label Title text shown bold below the icon.
 * @param subtitle Optional small text below the title (e.g. "41 models").
 * @param icon Optional icon. null = text-only tile.
 * @param selected Cream primary border + tinted icon/title when true.
 * @param onClick Tap handler.
 * @param tall When true, tile renders at 120dp instead of 96dp (POS Home).
 */
@Composable
fun FlowTile(
    label: String,
    subtitle: String? = null,
    icon: ImageVector? = null,
    selected: Boolean = false,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    tall: Boolean = false,
) {
    val borderColor = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline
    val borderWidth = if (selected) 1.5.dp else 1.dp
    val labelColor = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface
    val iconTint = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant
    Surface(
        modifier = modifier
            .height(if (tall) 120.dp else 96.dp)
            .border(borderWidth, borderColor, RoundedCornerShape(10.dp))
            .clickable(onClickLabel = "Select $label") { onClick() },
        shape = RoundedCornerShape(10.dp),
        color = MaterialTheme.colorScheme.surface,
    ) {
        Column(
            modifier = Modifier.padding(12.dp).fillMaxSize(),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            if (icon != null) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = iconTint,
                    modifier = Modifier.size(28.dp),
                )
                Spacer(Modifier.height(6.dp))
            }
            Text(
                text = label,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Bold,
                color = labelColor,
            )
            if (subtitle != null) {
                Spacer(Modifier.height(2.dp))
                Text(
                    text = subtitle,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}
