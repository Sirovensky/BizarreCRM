package com.bizarreelectronics.crm.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
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
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

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
 * [P1] Scrim support: callers may hoist the expanded state via [expandedState]
 * so a full-screen scrim can be rendered in the Scaffold content area. When
 * the scrim is tapped, the caller sets [expandedState].value = false, which
 * collapses the FAB. If [expandedState] is omitted the FAB manages its own state.
 */
@Composable
fun DashboardFab(
    onNewTicket: () -> Unit,
    onNewCustomer: () -> Unit,
    onLogSale: () -> Unit,
    onScanBarcode: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
    expandedState: MutableState<Boolean> = remember { mutableStateOf(false) },
) {
    val expanded = expandedState.value

    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.End,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // 160ms cubic ease-in-out per motion spec (§4 Motion spec polish)
        val fabEasing = CubicBezierEasing(0.4f, 0.0f, 0.2f, 1.0f)
        AnimatedVisibility(
            visible = expanded,
            enter = fadeIn(animationSpec = tween(durationMillis = 160, easing = fabEasing)),
            exit = fadeOut(animationSpec = tween(durationMillis = 160, easing = fabEasing)),
        ) {
            Column(
                horizontalAlignment = Alignment.End,
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                MiniFab(
                    label = "New Ticket",
                    icon = Icons.Filled.ConfirmationNumber,
                    onClick = {
                        expandedState.value = false
                        onNewTicket()
                    },
                )
                MiniFab(
                    label = "New customer",
                    icon = Icons.Filled.PersonAdd,
                    onClick = {
                        expandedState.value = false
                        onNewCustomer()
                    },
                )
                MiniFab(
                    label = "Log sale",
                    icon = Icons.Filled.AttachMoney,
                    onClick = {
                        expandedState.value = false
                        onLogSale()
                    },
                )
                if (onScanBarcode != null) {
                    MiniFab(
                        label = "Scan barcode",
                        icon = Icons.Filled.QrCodeScanner,
                        onClick = {
                            expandedState.value = false
                            onScanBarcode()
                        },
                    )
                }
            }
        }

        FloatingActionButton(
            onClick = { expandedState.value = !expandedState.value },
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
 *
 * [P1] Label text uses labelLarge with SemiBold weight — visually distinct
 * from body text, matching the display-condensed-semibold intent from the spec.
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
        text = {
            // [P1] SemiBold labelLarge so the FAB action labels read as
            // distinct named actions rather than body copy.
            Text(
                label,
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold,
            )
        },
    )
}
