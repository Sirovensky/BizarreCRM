package com.bizarreelectronics.crm.ui.screens.setup.steps

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * §2.10 Step 11 — Summary review.
 *
 * Displays a read-only summary of the key values collected across steps 1–10.
 * No user input; no data posted for this step. Next advances to step 12 (Finish).
 *
 * Server contract: no data posted; step_index=11 is sent with an empty map.
 *
 * [stepData] — the full stepData map from SetupWizardUiState used to display
 * summaries for each step.
 */
@Composable
fun SummaryStep(
    stepData: Map<Int, Map<String, Any>>,
    modifier: Modifier = Modifier,
) {
    val businessInfo = stepData[1] ?: emptyMap()
    val ownerInfo    = stepData[2] ?: emptyMap()
    val taxInfo      = stepData[3] ?: emptyMap()
    val paymentInfo  = stepData[4] ?: emptyMap()
    val smsInfo      = stepData[5] ?: emptyMap()
    val staffInfo    = stepData[7] ?: emptyMap()

    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("Summary Review", style = MaterialTheme.typography.titleLarge)
        Text(
            "Review your setup before finishing. You can go back to edit any step.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        SummaryCard("Business Info") {
            SummaryRow("Shop name", businessInfo["shop_name"]?.toString() ?: "(not set)")
            SummaryRow("Phone",     businessInfo["phone"]?.toString() ?: "(not set)")
            SummaryRow("Timezone",  businessInfo["timezone"]?.toString() ?: "(not set)")
            SummaryRow("Shop type", businessInfo["shop_type"]?.toString() ?: "(not set)")
        }
        SummaryCard("Owner Account") {
            SummaryRow("Username", ownerInfo["username"]?.toString() ?: "(not set)")
            SummaryRow("Email",    ownerInfo["email"]?.toString() ?: "(not set)")
            SummaryRow("Password", if (!ownerInfo["password"]?.toString().isNullOrBlank()) "••••••••" else "(not set)")
        }
        SummaryCard("Tax Classes") {
            val taxMsg = when {
                taxInfo["skipped"] == "true" -> "Skipped"
                taxInfo["tax_classes"] != null -> "Using defaults"
                else -> "(not set)"
            }
            SummaryRow("Status", taxMsg)
        }
        SummaryCard("Payment Methods") {
            val payMsg = when {
                paymentInfo["skipped"] == "true" -> "Skipped"
                else -> paymentInfo["payment_methods"]?.toString()?.replace(",", ", ") ?: "(not set)"
            }
            SummaryRow("Methods", payMsg)
        }
        SummaryCard("SMS / Email") {
            val smsMsg = if (smsInfo["skipped"] == "true") "Skipped" else "Twilio configured"
            SummaryRow("Status", smsMsg)
        }
        SummaryCard("Staff Invite") {
            val staffMsg = when {
                staffInfo["skipped"] == "true" -> "Skipped"
                else -> staffInfo["invite_email"]?.toString() ?: "Skipped"
            }
            SummaryRow("Invite", staffMsg)
        }
    }
}

@Composable
private fun SummaryCard(title: String, content: @Composable ColumnScope.() -> Unit) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = MaterialTheme.typography.titleSmall)
            HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
            content()
        }
    }
}

@Composable
private fun SummaryRow(label: String, value: String) {
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.bodySmall)
    }
}
