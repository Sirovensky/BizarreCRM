package com.bizarreelectronics.crm.ui.screens.setup.steps

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Science
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

/**
 * §2.10 Step 12 — Finish & launch.
 *
 * Final step. The "Finish" button on the bottom nav bar triggers
 * [SetupWizardViewModel.completeSetup] → POST /setup/complete → navigate to dashboard.
 *
 * §3.14 L582 — Sample data toggle: a clearly-labelled [OutlinedCard] lets the
 * user load 5 demo customers + 10 demo tickets + 3 demo invoices so they can
 * explore the app before entering real data. A "Clear sample data" button removes
 * the demo rows. Both buttons call [onLoadSampleData] / [onClearSampleData] which
 * hit POST/DELETE /onboarding/sample-data (404-tolerant).
 *
 * @param isLoading          True while [completeSetup] is in flight.
 * @param sampleDataLoaded   True when demo data is currently loaded.
 * @param isSampleDataBusy   True while the load/clear API call is in flight.
 * @param onLoadSampleData   Called to insert demo data.
 * @param onClearSampleData  Called to remove demo data.
 * @param modifier           Outer layout modifier.
 */
@Composable
fun FinishStep(
    isLoading: Boolean = false,
    sampleDataLoaded: Boolean = false,
    isSampleDataBusy: Boolean = false,
    onLoadSampleData: () -> Unit = {},
    onClearSampleData: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 24.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (isLoading) {
            CircularProgressIndicator()
            Spacer(Modifier.height(4.dp))
            Text(
                "Setting up your shop…",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        } else {
            Icon(
                imageVector = Icons.Default.CheckCircle,
                contentDescription = null,
                modifier = Modifier.size(72.dp),
                tint = MaterialTheme.colorScheme.primary,
            )
            Text(
                text = "You're all set!",
                style = MaterialTheme.typography.headlineMedium,
                textAlign = TextAlign.Center,
            )
            Text(
                text = "Tap \"Finish\" to launch your CRM dashboard. " +
                       "You can adjust any settings at any time from the Settings screen.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )

            // §3.14 L582 — Sample data toggle card
            SampleDataToggleCard(
                sampleDataLoaded = sampleDataLoaded,
                isBusy = isSampleDataBusy,
                onLoad = onLoadSampleData,
                onClear = onClearSampleData,
            )
        }
    }
}

/**
 * §3.14 L582 — Sample data toggle card shown on the Setup Wizard Finish step.
 *
 * Clearly labelled as "DEMO DATA" so new users never mistake sample rows for
 * real customer/ticket data. One-tap to load; one-tap to clear.
 */
@Composable
private fun SampleDataToggleCard(
    sampleDataLoaded: Boolean,
    isBusy: Boolean,
    onLoad: () -> Unit,
    onClear: () -> Unit,
    modifier: Modifier = Modifier,
) {
    OutlinedCard(
        modifier = modifier
            .fillMaxWidth()
            .semantics {
                contentDescription = if (sampleDataLoaded)
                    "Sample data loaded. Tap Clear to remove demo data."
                else
                    "Sample data not loaded. Tap Load to add demo data and explore the app."
            },
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(
                    imageVector = Icons.Default.Science,
                    contentDescription = null,
                    modifier = Modifier.size(20.dp),
                    tint = MaterialTheme.colorScheme.secondary,
                )
                Text(
                    text = "Sample data",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                Spacer(Modifier.weight(1f))
                // Badge: DEMO DATA label
                Surface(
                    color = MaterialTheme.colorScheme.secondaryContainer,
                    shape = MaterialTheme.shapes.small,
                ) {
                    Text(
                        text = "DEMO",
                        style = MaterialTheme.typography.labelSmall,
                        modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                        color = MaterialTheme.colorScheme.onSecondaryContainer,
                    )
                }
            }

            Text(
                text = if (sampleDataLoaded)
                    "Demo tickets, customers, and invoices are loaded. " +
                    "All demo data is clearly labelled and can be removed any time."
                else
                    "Load 5 demo customers, 10 demo tickets, and 3 demo invoices to " +
                    "explore the app before entering real data.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            if (isBusy) {
                LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
            } else if (sampleDataLoaded) {
                FilledTonalButton(
                    onClick = onClear,
                    modifier = Modifier
                        .fillMaxWidth()
                        .semantics { role = Role.Button },
                ) {
                    Text("Clear sample data")
                }
            } else {
                FilledTonalButton(
                    onClick = onLoad,
                    modifier = Modifier
                        .fillMaxWidth()
                        .semantics { role = Role.Button },
                ) {
                    Text("Load sample data")
                }
            }
        }
    }
}
