package com.bizarreelectronics.crm.ui.screens.dashboard.components

import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Sms
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

/**
 * §3.12 L561 — SMS unread badge.
 *
 * Wraps an SMS icon in a [BadgedBox]. The badge is shown only when
 * [unreadCount] > 0. If [unreadCount] is null (endpoint returned 404 or
 * is not yet loaded) the icon renders without a badge.
 *
 * Intended for use in the FAB SpeedDial action row (phone) or in the
 * tab-bar / nav-rail SMS item (tablet).
 */
@Composable
fun UnreadSmsPill(
    unreadCount: Int?,
    onNavigateToSms: () -> Unit,
    modifier: Modifier = Modifier,
) {
    BadgedBox(
        modifier = modifier,
        badge = {
            if (unreadCount != null && unreadCount > 0) {
                Badge {
                    Text(if (unreadCount > 99) "99+" else unreadCount.toString())
                }
            }
        },
    ) {
        IconButton(onClick = onNavigateToSms) {
            Icon(
                Icons.Default.Sms,
                contentDescription = if (unreadCount != null && unreadCount > 0) {
                    "SMS ($unreadCount unread)"
                } else {
                    "SMS"
                },
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
