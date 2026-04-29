package com.bizarreelectronics.crm.ui.screens.settings

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Analytics
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Policy
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel

/**
 * L2526 — Data Privacy settings sub-screen.
 *
 * Surfaces four GDPR-related actions for the authenticated user:
 *   1. **Export my data** — submits an async export request to the server.
 *   2. **Delete my account** — soft-deletes the account after confirmation.
 *   3. **Privacy policy link** — opens the hosted privacy policy in a browser.
 *   4. **Terms of Service link** — opens the hosted ToS in a browser.
 *
 * Also displays the user's consent-captured-on timestamp from the server, if available.
 *
 * All destructive actions are gated behind confirmation dialogs.  404 responses
 * are surfaced as "This feature is not available on your server" snackbar messages.
 *
 * @param onNavigateBack   Callback to pop the back stack.
 * @param onAccountDeleted Callback invoked when the account has been deleted and
 *   local auth state has been wiped — typically navigates to the login screen.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DataPrivacyScreen(
    onNavigateBack: () -> Unit,
    onAccountDeleted: () -> Unit,
    viewModel: DataPrivacyViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val consentStatus by viewModel.consentStatus.collectAsState()
    val telemetryEnabled by viewModel.telemetryEnabled.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    var showDeleteDialog by remember { mutableStateOf(false) }
    val context = LocalContext.current

    // Side effects from state transitions
    LaunchedEffect(state) {
        when (val s = state) {
            is DataPrivacyState.ExportRequested -> {
                val msg = if (s.requestId != null) {
                    "Export requested (ID: ${s.requestId}). You will receive an email when ready."
                } else {
                    "Export request submitted. You will receive an email when ready."
                }
                snackbarHostState.showSnackbar(msg)
                viewModel.resetState()
            }
            is DataPrivacyState.DeletedAndLoggedOut -> onAccountDeleted()
            is DataPrivacyState.FeatureNotAvailable -> {
                snackbarHostState.showSnackbar("This feature is not available on your server.")
                viewModel.resetState()
            }
            is DataPrivacyState.Error -> {
                snackbarHostState.showSnackbar("Error: ${s.message}")
                viewModel.resetState()
            }
            else -> Unit
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Data & Privacy") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .padding(paddingValues)
                .verticalScroll(rememberScrollState()),
        ) {
            // ─── Consent timestamp ────────────────────────────────────────────
            consentStatus?.let { consent ->
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text(
                            text = "Consent Record",
                            style = MaterialTheme.typography.titleSmall,
                        )
                        Spacer(modifier = Modifier.height(4.dp))
                        val label = when {
                            consent.policyVersion != null && consent.consentedAt != null ->
                                "Accepted policy v${consent.policyVersion} on ${consent.consentedAt}"
                            consent.consentedAt != null ->
                                "Accepted privacy policy on ${consent.consentedAt}"
                            else -> "No consent record found"
                        }
                        Text(
                            text = label,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))

            // ─── §74.3 Telemetry opt-out ──────────────────────────────────────
            // All analytics events go to the tenant's own server only.
            // No GAID / ADID / Firebase Analytics / Google Analytics / Mixpanel.
            // When disabled, the local crash log (CrashReporter) is unaffected.
            ListItem(
                headlineContent = { Text("Diagnostics & analytics") },
                supportingContent = {
                    Text(
                        "Send anonymous usage events to this shop's server only. " +
                            "No data leaves your server. " +
                            "Crash logs are always kept locally for support.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                },
                leadingContent = {
                    Icon(Icons.Default.Analytics, contentDescription = null)
                },
                trailingContent = {
                    Switch(
                        checked = telemetryEnabled,
                        onCheckedChange = { viewModel.setTelemetryEnabled(it) },
                    )
                },
            )

            HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))

            // ─── Export data ──────────────────────────────────────────────────
            ListItem(
                headlineContent = { Text("Export my data") },
                supportingContent = {
                    Text("Request a copy of all your personal data stored on this server.")
                },
                leadingContent = {
                    Icon(Icons.Default.Download, contentDescription = null)
                },
            )
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.End,
            ) {
                if (state is DataPrivacyState.Loading) {
                    CircularProgressIndicator()
                } else {
                    OutlinedButton(onClick = { viewModel.requestExport() }) {
                        Text("Request Export")
                    }
                }
            }

            HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))

            // ─── Delete account ───────────────────────────────────────────────
            ListItem(
                headlineContent = { Text("Delete my account") },
                supportingContent = {
                    Text(
                        "Permanently deletes your account and associated data. " +
                            "This action cannot be undone.",
                    )
                },
                leadingContent = {
                    Icon(
                        Icons.Default.Delete,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.error,
                    )
                },
            )
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.End,
            ) {
                Button(
                    onClick = { showDeleteDialog = true },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.error,
                    ),
                    enabled = state !is DataPrivacyState.Loading,
                ) {
                    Text("Delete Account")
                }
            }

            HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))

            // ─── Policy links ─────────────────────────────────────────────────
            ListItem(
                headlineContent = { Text("Privacy Policy") },
                supportingContent = { Text("Read how we handle your personal data.") },
                leadingContent = { Icon(Icons.Default.Policy, contentDescription = null) },
                modifier = Modifier.clickable {
                    context.startActivity(
                        Intent(Intent.ACTION_VIEW, Uri.parse("https://bizarreelectronics.com/privacy")),
                    )
                },
            )
            ListItem(
                headlineContent = { Text("Terms of Service") },
                supportingContent = { Text("Read our terms and conditions.") },
                leadingContent = { Icon(Icons.Default.Policy, contentDescription = null) },
                modifier = Modifier.clickable {
                    context.startActivity(
                        Intent(Intent.ACTION_VIEW, Uri.parse("https://bizarreelectronics.com/terms")),
                    )
                },
            )
        }
    }

    // ─── Delete confirmation dialog ───────────────────────────────────────────
    if (showDeleteDialog) {
        AlertDialog(
            onDismissRequest = { showDeleteDialog = false },
            title = { Text("Delete Account") },
            text = {
                Text(
                    "This will permanently delete your account and all associated data. " +
                        "You will be signed out immediately. This action cannot be undone.\n\n" +
                        "Are you sure you want to proceed?",
                )
            },
            confirmButton = {
                Button(
                    onClick = {
                        showDeleteDialog = false
                        viewModel.deleteAccount()
                    },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.error,
                    ),
                ) {
                    Text("Delete My Account")
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteDialog = false }) {
                    Text("Cancel")
                }
            },
        )
    }
}
