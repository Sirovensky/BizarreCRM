package com.bizarreelectronics.crm.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AttachMoney
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ConfirmationNumber
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SmallFloatingActionButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * Front-and-center FAB for the dashboard. Collapsed it is a single "+" button.
 * Expanded it reveals three stacked mini-FABs for the most common first
 * actions a technician takes when opening the app:
 *   1. New ticket
 *   2. New customer
 *   3. Log sale (POS)
 *
 * A fourth entry point (Scan barcode / IMEI) is wired in when the camera
 * scanner is available — this ties item 9 (barcode quick-add) into the same
 * expandable FAB rather than cluttering the dashboard with another button.
 *
 * The expanded state is local to this composable because it has no meaning
 * outside of "the FAB is open right now". If we later need to close it from
 * an outer composable (e.g. to hide on scroll), we can lift the state into
 * the caller.
 */
@Composable
fun DashboardFab(
    onNewTicket: () -> Unit,
    onNewCustomer: () -> Unit,
    onLogSale: () -> Unit,
    onScanBarcode: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    var expanded by remember { mutableStateOf(false) }

    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.End,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        AnimatedVisibility(
            visible = expanded,
            enter = fadeIn(),
            exit = fadeOut(),
        ) {
            Column(
                horizontalAlignment = Alignment.End,
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                MiniFab(
                    label = "New ticket",
                    icon = Icons.Filled.ConfirmationNumber,
                    onClick = {
                        expanded = false
                        onNewTicket()
                    },
                )
                MiniFab(
                    label = "New customer",
                    icon = Icons.Filled.PersonAdd,
                    onClick = {
                        expanded = false
                        onNewCustomer()
                    },
                )
                MiniFab(
                    label = "Log sale",
                    icon = Icons.Filled.AttachMoney,
                    onClick = {
                        expanded = false
                        onLogSale()
                    },
                )
                if (onScanBarcode != null) {
                    MiniFab(
                        label = "Scan barcode",
                        icon = Icons.Filled.QrCodeScanner,
                        onClick = {
                            expanded = false
                            onScanBarcode()
                        },
                    )
                }
            }
        }

        FloatingActionButton(
            onClick = { expanded = !expanded },
            containerColor = MaterialTheme.colorScheme.primary,
            contentColor = MaterialTheme.colorScheme.onPrimary,
        ) {
            Icon(
                imageVector = if (expanded) Icons.Filled.Close else Icons.Filled.Add,
                contentDescription = if (expanded) "Close menu" else "Open quick-action menu",
            )
        }
    }
}

/**
 * Labelled mini-FAB row. Uses [ExtendedFloatingActionButton] so the label
 * is directly attached to the action rather than floating beside it, which
 * survives RTL layouts without extra bookkeeping.
 */
@Composable
private fun MiniFab(
    label: String,
    icon: ImageVector,
    onClick: () -> Unit,
) {
    ExtendedFloatingActionButton(
        onClick = onClick,
        containerColor = MaterialTheme.colorScheme.secondaryContainer,
        contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
        icon = { Icon(icon, contentDescription = null) },
        text = { Text(label) },
    )
}
