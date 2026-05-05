package com.bizarreelectronics.crm.ui.components.shared

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/**
 * Single visual atom for the "attached customer" pill that follows the
 * cashier across every POS flow screen. Replaces the dual dark/teal
 * variants previously rendered by PosEntryScreen.CustomerHeaderBanner +
 * CheckInEntryScreen.AttachedCustomerPill so the user sees one consistent
 * shape regardless of which screen they're on.
 *
 * Visual contract:
 *   - Surface bg (`MaterialTheme.colorScheme.surface`)
 *   - 12dp rounded corners
 *   - 1dp outline border (idle); never the teal/cyan variant
 *   - 40dp circle avatar with cream `primary` background + onPrimary initials
 *   - Title bodyMedium bold, optional subtitle labelSmall onSurfaceVariant
 *   - Optional trailing close (X) IconButton — null hides it
 *
 * @param name Full name to display.
 * @param subtitle Optional second line (e.g. phone, ticket count).
 * @param onDetach Optional close handler. null = hide trailing icon.
 */
@Composable
fun CustomerHeaderPill(
    name: String,
    subtitle: String? = null,
    onDetach: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surface,
        border = androidx.compose.foundation.BorderStroke(
            width = 1.dp,
            color = MaterialTheme.colorScheme.outline,
        ),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .size(40.dp)
                        .background(MaterialTheme.colorScheme.primary, CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = name.take(2).trim().uppercase().ifBlank { "?" },
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onPrimary,
                    )
                }
                Spacer(Modifier.width(12.dp))
                Column {
                    Text(
                        text = name,
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    if (subtitle != null) {
                        Text(
                            text = subtitle,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
            if (onDetach != null) {
                IconButton(onClick = onDetach) {
                    Icon(
                        Icons.Default.Close,
                        contentDescription = "Detach customer",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}
