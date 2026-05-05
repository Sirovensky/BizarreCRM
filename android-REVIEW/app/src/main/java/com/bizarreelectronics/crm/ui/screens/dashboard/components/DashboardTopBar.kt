package com.bizarreelectronics.crm.ui.screens.dashboard.components

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Sms
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * §3.8 L543 — Tablet/ChromeOS top-app-bar action row.
 *
 * Renders when [windowMode] >= [WindowMode.Tablet]. On phone the standard FAB
 * is shown instead; this composable must NOT be included in the topBar on phone.
 *
 * Actions: New Ticket, New Customer, Scan, New SMS, Settings.
 */
@Composable
fun DashboardTabletActions(
    onCreateTicket: () -> Unit,
    onCreateCustomer: () -> Unit,
    onScanBarcode: (() -> Unit)?,
    onNewSms: (() -> Unit)?,
    onNavigateToSettings: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = onCreateTicket) {
            Icon(
                Icons.Default.Add,
                contentDescription = "New ticket",
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        IconButton(onClick = onCreateCustomer) {
            Icon(
                Icons.Default.PersonAdd,
                contentDescription = "New customer",
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (onScanBarcode != null) {
            IconButton(onClick = onScanBarcode) {
                Icon(
                    Icons.Default.QrCodeScanner,
                    contentDescription = "Scan barcode",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        if (onNewSms != null) {
            IconButton(onClick = onNewSms) {
                Icon(
                    Icons.Default.Sms,
                    contentDescription = "New SMS",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        if (onNavigateToSettings != null) {
            Spacer(modifier = Modifier.width(4.dp))
            IconButton(onClick = onNavigateToSettings) {
                Icon(
                    Icons.Default.Settings,
                    contentDescription = "Settings",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}
