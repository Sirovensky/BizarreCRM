package com.bizarreelectronics.crm.ui.screens.dashboard.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
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
 * §3.14 L573/L574 — Brand-new tenant setup checklist card.
 *
 * Displayed at the top of the dashboard when [completedSteps] < [totalSteps].
 * Shows:
 *   - "Let's set up your shop" headline
 *   - [LinearProgressIndicator] tracking setup completion
 *   - "N of 5 steps remaining" sub-label
 *   - "Continue setup" CTA → invokes [onNavigateToSetup]
 *
 * §3.14 L581 — Completion ring: a small [CircularProgressIndicator] appears in
 * the top-right corner of the card showing setup progress percentage. Tapping
 * it also navigates to the Setup Wizard.
 *
 * The card auto-hides when [completedSteps] >= [totalSteps].
 *
 * @param completedSteps    Number of setup steps already completed.
 * @param totalSteps        Total number of setup steps (default 5).
 * @param onNavigateToSetup Called when the CTA or completion ring is tapped.
 * @param modifier          Applied to the outermost [AnimatedVisibility].
 */
@Composable
fun SetupChecklistCard(
    completedSteps: Int,
    totalSteps: Int = 5,
    onNavigateToSetup: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val isComplete = completedSteps >= totalSteps
    val progress = if (totalSteps == 0) 0f else completedSteps.toFloat() / totalSteps
    val remaining = (totalSteps - completedSteps).coerceAtLeast(0)
    val progressPercent = (progress * 100).toInt()

    AnimatedVisibility(
        visible = !isComplete,
        enter = fadeIn() + expandVertically(),
        exit = fadeOut() + shrinkVertically(),
        modifier = modifier,
    ) {
        Card(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp),
        ) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                // Header row: title + completion ring (L581)
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = "Let's set up your shop",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.onSurface,
                        )
                        Text(
                            text = "$remaining of $totalSteps steps remaining",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }

                    // §3.14 L581 — Completion ring: tappable CircularProgressIndicator.
                    Box(
                        contentAlignment = Alignment.Center,
                        modifier = Modifier
                            .size(48.dp)
                            .clickable(
                                onClickLabel = "Open Setup Wizard",
                                onClick = onNavigateToSetup,
                            )
                            .semantics {
                                role = Role.Button
                                contentDescription = "Setup progress $progressPercent percent. Tap to open Setup Wizard."
                            },
                    ) {
                        CircularProgressIndicator(
                            progress = { progress },
                            modifier = Modifier.size(40.dp),
                            strokeWidth = 4.dp,
                            color = MaterialTheme.colorScheme.primary,
                            trackColor = MaterialTheme.colorScheme.surfaceVariant,
                        )
                        Text(
                            text = "$progressPercent%",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurface,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                }

                // Progress bar
                LinearProgressIndicator(
                    progress = { progress },
                    modifier = Modifier.fillMaxWidth(),
                    color = MaterialTheme.colorScheme.primary,
                    trackColor = MaterialTheme.colorScheme.surfaceVariant,
                )

                Spacer(modifier = Modifier.height(2.dp))

                // CTA
                Button(
                    onClick = onNavigateToSetup,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Continue setup")
                }
            }
        }
    }
}
