package com.bizarreelectronics.crm.ui.screens.tickets.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AssignmentInd
import androidx.compose.material.icons.filled.HourglassTop
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.screens.tickets.TicketSavedView

/**
 * Bottom sheet (L645) allowing the user to select a saved-view preset.
 *
 * Presets:
 *   - My queue:             assigned to current user + open
 *   - Awaiting customer:    status name matches "awaiting" / "waiting for customer"
 *   - SLA breaching today:  stub — shows urgency High+ non-closed tickets
 *
 * The selected view persists to [AppPreferences.ticketListSavedView] via the ViewModel.
 * Tapping "None" clears the saved view filter.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TicketSavedViewSheet(
    currentSavedView: TicketSavedView,
    onSavedViewSelected: (TicketSavedView) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(modifier = Modifier.padding(bottom = 24.dp)) {
            Text(
                text = "Saved views",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(horizontal = 24.dp, vertical = 12.dp),
            )
            HorizontalDivider()
            Spacer(modifier = Modifier.height(8.dp))

            SavedViewRow(
                view = TicketSavedView.None,
                currentSavedView = currentSavedView,
                icon = null,
                subtitle = "Show all tickets (no preset filter)",
                onSelected = onSavedViewSelected,
            )
            SavedViewRow(
                view = TicketSavedView.MyQueue,
                currentSavedView = currentSavedView,
                icon = Icons.Default.AssignmentInd,
                subtitle = "Assigned to me · Open tickets",
                onSelected = onSavedViewSelected,
            )
            SavedViewRow(
                view = TicketSavedView.AwaitingCustomer,
                currentSavedView = currentSavedView,
                icon = Icons.Default.HourglassTop,
                subtitle = "Status contains 'awaiting customer'",
                onSelected = onSavedViewSelected,
            )
            SavedViewRow(
                view = TicketSavedView.SlaBreachingToday,
                currentSavedView = currentSavedView,
                icon = Icons.Default.Timer,
                subtitle = "High urgency non-closed tickets (SLA stub)",
                onSelected = onSavedViewSelected,
            )
        }
    }
}

@Composable
private fun SavedViewRow(
    view: TicketSavedView,
    currentSavedView: TicketSavedView,
    icon: androidx.compose.ui.graphics.vector.ImageVector?,
    subtitle: String,
    onSelected: (TicketSavedView) -> Unit,
) {
    val isSelected = view == currentSavedView
    TextButton(
        onClick = { onSelected(view) },
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (icon != null) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = if (isSelected) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                )
                Spacer(modifier = Modifier.padding(end = 12.dp))
            } else {
                Spacer(modifier = Modifier.padding(end = 36.dp))
            }
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = view.label,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
                    color = if (isSelected) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurface
                    },
                )
                Text(
                    text = subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}
