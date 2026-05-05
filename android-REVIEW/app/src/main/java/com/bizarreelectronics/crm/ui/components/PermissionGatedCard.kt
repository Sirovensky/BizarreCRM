package com.bizarreelectronics.crm.ui.components

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

/**
 * §3.14 L572 — Permission-gated tile wrapper.
 *
 * When [hasPermission] is false, renders a semi-transparent grey overlay on
 * top of [content] with a Lock icon and an explanatory message. The content
 * is rendered at 20% opacity (visually greyed-out) so the user can see what
 * the tile contains but understands it is inaccessible.
 *
 * When [hasPermission] is true, renders [content] directly with no overlay.
 *
 * Usage:
 * ```kotlin
 * PermissionGatedCard(
 *     requiredPermission = "reports",
 *     hasPermission = currentUser.canViewReports,
 * ) {
 *     RevenueCard(...)
 * }
 * ```
 *
 * @param requiredPermission  Human-readable name of the permission needed (e.g. "Reports").
 *                            Used to build the overlay message.
 * @param hasPermission       True if the current user has access.
 * @param modifier            Applied to the root [Box].
 * @param content             The tile content to render (possibly dimmed).
 */
@Composable
fun PermissionGatedCard(
    requiredPermission: String,
    hasPermission: Boolean,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    Box(modifier = modifier) {
        // Always render content — gated view dims it rather than hiding,
        // so the user knows what they are missing.
        Box(
            modifier = if (!hasPermission) Modifier.alpha(0.20f) else Modifier,
        ) {
            content()
        }

        if (!hasPermission) {
            // Overlay — covers the entire tile
            Surface(
                modifier = Modifier
                    .matchParentSize()
                    .semantics {
                        contentDescription = "$requiredPermission is locked. Ask your admin to enable $requiredPermission for your role."
                    },
                color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.85f),
                shape = MaterialTheme.shapes.medium,
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(12.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    androidx.compose.foundation.layout.Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(6.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Default.Lock,
                            // decorative — parent Surface semantics carries the full announcement
                            contentDescription = null,
                            modifier = Modifier.size(20.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            text = "Ask your admin to enable $requiredPermission for your role.",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center,
                        )
                    }
                }
            }
        }
    }
}
