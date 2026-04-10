package com.bizarreelectronics.crm.ui.components.shared

import androidx.compose.animation.*
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

private val OfflineBannerYellow = Color(0xFFFFD600)
private val OfflineBannerText = Color(0xFF1A1A1A)

@Composable
fun OfflineBanner(
    isOffline: Boolean,
    pendingSyncCount: Int = 0,
    isSyncing: Boolean = false,
) {
    AnimatedVisibility(
        visible = isOffline,
        enter = expandVertically(),
        exit = shrinkVertically(),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(OfflineBannerYellow)
                .padding(horizontal = 16.dp, vertical = 10.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(
                    Icons.Default.WifiOff,
                    contentDescription = "Offline",
                    tint = OfflineBannerText,
                    modifier = Modifier.size(20.dp),
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    "OFFLINE MODE",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold,
                    color = OfflineBannerText,
                    textAlign = TextAlign.Center,
                )
            }
            if (pendingSyncCount > 0 || isSyncing) {
                Spacer(Modifier.height(2.dp))
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center,
                ) {
                    if (isSyncing) {
                        Icon(
                            Icons.Default.Sync,
                            contentDescription = "Syncing",
                            tint = OfflineBannerText.copy(alpha = 0.7f),
                            modifier = Modifier.size(14.dp),
                        )
                        Spacer(Modifier.width(4.dp))
                        Text(
                            "Syncing...",
                            style = MaterialTheme.typography.labelSmall,
                            color = OfflineBannerText.copy(alpha = 0.7f),
                        )
                    } else {
                        Text(
                            "$pendingSyncCount change${if (pendingSyncCount != 1) "s" else ""} pending sync",
                            style = MaterialTheme.typography.labelSmall,
                            color = OfflineBannerText.copy(alpha = 0.7f),
                        )
                    }
                }
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
