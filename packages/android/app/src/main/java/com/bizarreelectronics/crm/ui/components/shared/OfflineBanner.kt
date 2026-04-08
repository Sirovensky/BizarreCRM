package com.bizarreelectronics.crm.ui.components.shared

import androidx.compose.animation.*
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.theme.*

@Composable
fun OfflineBanner(isOffline: Boolean, pendingSyncCount: Int = 0) {
    AnimatedVisibility(
        visible = isOffline,
        enter = expandVertically(),
        exit = shrinkVertically(),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(WarningBg)
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(Icons.Default.CloudOff, "Offline", tint = WarningAmber, modifier = Modifier.size(16.dp))
            Text(
                "Working offline",
                style = MaterialTheme.typography.labelMedium,
                color = WarningText,
            )
            if (pendingSyncCount > 0) {
                Text(
                    "• $pendingSyncCount changes pending",
                    style = MaterialTheme.typography.labelSmall,
                    color = WarningText,
                )
            }
        }
    }
}

@Composable
fun SyncIndicator(isSyncing: Boolean) {
    AnimatedVisibility(visible = isSyncing) {
        Icon(
            Icons.Default.Sync,
            contentDescription = "Syncing",
            modifier = Modifier.size(20.dp),
            tint = MaterialTheme.colorScheme.primary,
        )
    }
}
