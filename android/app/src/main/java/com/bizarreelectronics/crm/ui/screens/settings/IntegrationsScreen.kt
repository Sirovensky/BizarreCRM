package com.bizarreelectronics.crm.ui.screens.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.Message
import androidx.compose.material.icons.filled.Print
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * §19.10 — Integrations settings hub.
 *
 * Lists connected integrations and navigates to their individual sub-screens.
 * Admin-only; enforced at the nav call site in AppNavGraph.
 *
 * Webhooks and Zapier rows are shown as "coming soon" until server endpoints
 * are implemented.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun IntegrationsScreen(
    onBack: () -> Unit,
    /** Navigate to Hardware Settings (covers BlockChyp terminal pairing). */
    onHardware: (() -> Unit)? = null,
    /** Navigate to SMS Settings screen. */
    onSms: (() -> Unit)? = null,
) {
    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text("Integrations") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                Column {
                    Text(
                        "Connected integrations",
                        style = MaterialTheme.typography.titleSmall,
                        modifier = Modifier.padding(start = 16.dp, top = 16.dp, end = 16.dp),
                    )
                    if (onHardware != null) {
                        ListItem(
                            leadingContent = {
                                Icon(
                                    Icons.Default.CreditCard,
                                    contentDescription = "BlockChyp terminal",
                                )
                            },
                            headlineContent = { Text("BlockChyp") },
                            supportingContent = { Text("Payment terminal pairing and configuration") },
                            modifier = Modifier.settingsClickable(onHardware),
                        )
                    }
                    if (onSms != null) {
                        ListItem(
                            leadingContent = {
                                Icon(
                                    Icons.Default.Message,
                                    contentDescription = "SMS provider",
                                )
                            },
                            headlineContent = { Text("SMS provider") },
                            supportingContent = { Text("Twilio, Telnyx, or other configured SMS provider") },
                            modifier = Modifier.settingsClickable(onSms),
                        )
                    }
                }
            }

            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                Column {
                    Text(
                        "Coming soon",
                        style = MaterialTheme.typography.titleSmall,
                        modifier = Modifier.padding(start = 16.dp, top = 16.dp, end = 16.dp),
                    )
                    ListItem(
                        leadingContent = {
                            Icon(
                                Icons.Default.Print,
                                contentDescription = "Webhooks",
                                tint = MaterialTheme.colorScheme.outline,
                            )
                        },
                        headlineContent = {
                            Text(
                                "Webhooks",
                                color = MaterialTheme.colorScheme.outline,
                            )
                        },
                        supportingContent = {
                            Text(
                                "Send events to external URLs — not yet available",
                                color = MaterialTheme.colorScheme.outline,
                            )
                        },
                    )
                    ListItem(
                        leadingContent = {
                            Icon(
                                Icons.Default.Print,
                                contentDescription = "Zapier",
                                tint = MaterialTheme.colorScheme.outline,
                            )
                        },
                        headlineContent = {
                            Text("Zapier", color = MaterialTheme.colorScheme.outline)
                        },
                        supportingContent = {
                            Text(
                                "Automate workflows — not yet available",
                                color = MaterialTheme.colorScheme.outline,
                            )
                        },
                    )
                    ListItem(
                        leadingContent = {
                            Icon(
                                Icons.Default.CreditCard,
                                contentDescription = "Google Wallet",
                                tint = MaterialTheme.colorScheme.outline,
                            )
                        },
                        headlineContent = {
                            Text("Google Wallet", color = MaterialTheme.colorScheme.outline)
                        },
                        supportingContent = {
                            Text(
                                "Digital receipt passes — not yet available",
                                color = MaterialTheme.colorScheme.outline,
                            )
                        },
                    )
                }
            }
        }
    }
}

private fun Modifier.settingsClickable(onClick: () -> Unit): Modifier =
    this.clickable { onClick() }
