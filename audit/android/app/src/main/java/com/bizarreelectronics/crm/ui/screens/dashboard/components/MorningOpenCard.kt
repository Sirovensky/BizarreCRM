package com.bizarreelectronics.crm.ui.screens.dashboard.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/**
 * §36 L585 — Dashboard banner that triggers the morning-open checklist.
 *
 * Shown when:
 *  - The logged-in user has a staff role, AND
 *  - [AppPreferences.lastMorningChecklistDate] != today, AND
 *  - The banner has not been dismissed for today.
 *
 * Tap on the body → navigate to [Screen.MorningChecklist].
 * Tap on "×"     → dismiss for today (writes [AppPreferences.setMorningChecklistDismissed]).
 *
 * This card is deliberately non-blocking: staff can dismiss without completing
 * the checklist.
 *
 * @param completedStepCount Number of steps already checked off today (shown in subtitle).
 * @param totalStepCount     Total number of steps in today's checklist.
 * @param onTap              Called when the user taps the card body to open the checklist.
 * @param onDismiss          Called when the user taps "×" to hide the banner for today.
 * @param modifier           Outer layout modifier.
 */
@Composable
fun MorningOpenCard(
    completedStepCount: Int,
    totalStepCount: Int,
    onTap: () -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val subtitle = when {
        completedStepCount == 0 -> "$totalStepCount steps to complete before opening"
        completedStepCount < totalStepCount ->
            "$completedStepCount / $totalStepCount steps done — tap to continue"
        else -> "All steps done — have a great day!"
    }

    Card(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .semantics {
                contentDescription = "Morning checklist: $subtitle. Tap to open."
            },
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.secondaryContainer,
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(onClick = onTap)
                .padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            // Checklist icon
            Icon(
                imageVector = Icons.Default.Checklist,
                contentDescription = null,
                modifier = Modifier.size(24.dp),
                tint = MaterialTheme.colorScheme.onSecondaryContainer,
            )

            // Title + subtitle
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "Morning open checklist",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSecondaryContainer,
                )
                Text(
                    text = subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSecondaryContainer.copy(alpha = 0.82f),
                )
            }

            // Chevron affordance
            Icon(
                imageVector = Icons.Default.ChevronRight,
                contentDescription = "Open checklist",
                modifier = Modifier
                    .size(20.dp)
                    .semantics { role = Role.Button },
                tint = MaterialTheme.colorScheme.onSecondaryContainer,
            )

            Spacer(modifier = Modifier.width(0.dp))

            // Dismiss button
            IconButton(
                onClick = onDismiss,
                modifier = Modifier.size(32.dp),
            ) {
                Icon(
                    imageVector = Icons.Default.Close,
                    contentDescription = "Dismiss morning checklist",
                    modifier = Modifier.size(16.dp),
                    tint = MaterialTheme.colorScheme.onSecondaryContainer,
                )
            }
        }
    }
}
