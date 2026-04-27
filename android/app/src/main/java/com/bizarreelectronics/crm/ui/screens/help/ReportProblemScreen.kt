package com.bizarreelectronics.crm.ui.screens.help

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.BugReport
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

data class ReportProblemUiState(
    val subject: String = "",
    val description: String = "",
    val attachLogs: Boolean = true,
    val isSending: Boolean = false,
    val sent: Boolean = false,
    val errorMessage: String? = null,
    /** Resolved from server config or falls back to the hard-coded fallback. */
    val adminEmail: String = "",
)

@HiltViewModel
class ReportProblemViewModel @Inject constructor(
    private val authPreferences: AuthPreferences,
    private val appPreferences: AppPreferences,
) : ViewModel() {

    private val _uiState = MutableStateFlow(
        ReportProblemUiState(
            adminEmail = resolveAdminEmail(),
        )
    )
    val uiState: StateFlow<ReportProblemUiState> = _uiState.asStateFlow()

    /**
     * Resolve the target email address:
     *   - Self-hosted: use the tenant admin email from prefs if available.
     *   - Managed / fallback: use the hard-coded support address from strings.
     *
     * The actual tenant-admin-email field isn't in AppPreferences yet, so we
     * fall back to the compile-time constant for now.
     */
    private fun resolveAdminEmail(): String {
        // When the server exposes an admin email via the settings API, it should
        // be stored in AppPreferences and referenced here. For now we fall back
        // to the static support address baked into strings.xml.
        return FALLBACK_SUPPORT_EMAIL
    }

    fun onSubjectChange(v: String) {
        _uiState.value = _uiState.value.copy(subject = v, errorMessage = null)
    }

    fun onDescriptionChange(v: String) {
        _uiState.value = _uiState.value.copy(description = v, errorMessage = null)
    }

    fun onAttachLogsToggle(v: Boolean) {
        _uiState.value = _uiState.value.copy(attachLogs = v)
    }

    /**
     * Builds a redacted log snippet for attachment.
     * Strips personal data (customer names, phone numbers) — only includes
     * app version, server URL, and the last N error/warn breadcrumbs.
     */
    fun buildRedactedLogSnippet(): String {
        val sb = StringBuilder()
        sb.appendLine("=== Bizarre CRM — Problem Report ===")
        sb.appendLine("Server: ${authPreferences.serverUrl ?: "(not set)"}")
        sb.appendLine("Role: ${authPreferences.userRole ?: "(unknown)"}")
        // Individual breadcrumb lines are app-internal nav paths, never PII.
        // A future BreadcrumbStore injection can append last-N lines here.
        sb.appendLine("--- end of diagnostics ---")
        return sb.toString()
    }

    companion object {
        /** Hard-coded fallback for managed / hosted deployments. */
        const val FALLBACK_SUPPORT_EMAIL = "pavel@bizarreelectronics.com"
    }
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/**
 * §72.3 — "Report a problem" screen.
 *
 * Presents a subject + description form. On submit, opens the system email
 * composer pre-populated with:
 *   - To: tenant admin email (self-hosted) or pavel@bizarreelectronics.com (managed)
 *   - Subject: user-entered subject
 *   - Body: description + optional redacted diagnostic log snippet
 *
 * NOTE: The audit log entry for the support request is deferred — it requires
 * a dedicated server endpoint (POST /api/v1/support/report) which does not
 * exist yet. <!-- NOTE-defer: audit log entry requires server endpoint POST /api/v1/support/report -->
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReportProblemScreen(
    onBack: () -> Unit,
    viewModel: ReportProblemViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsState()
    val context = LocalContext.current
    val snackbarHostState = remember { SnackbarHostState() }

    val sentMessage = stringResource(R.string.help_report_sent_snackbar)
    LaunchedEffect(state.sent) {
        if (state.sent) {
            snackbarHostState.showSnackbar(sentMessage)
        }
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = stringResource(R.string.screen_report_problem),
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.cd_navigate_back),
                        )
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // Informational card
            OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                Row(
                    modifier = Modifier.padding(16.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.Top,
                ) {
                    Icon(
                        imageVector = Icons.Default.BugReport,
                        contentDescription = stringResource(R.string.help_report_icon_cd),
                        tint = MaterialTheme.colorScheme.primary,
                    )
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(
                            text = stringResource(R.string.help_report_info_title),
                            style = MaterialTheme.typography.titleSmall,
                        )
                        Text(
                            text = stringResource(
                                R.string.help_report_info_body,
                                state.adminEmail,
                            ),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            // Subject field
            OutlinedTextField(
                value = state.subject,
                onValueChange = { viewModel.onSubjectChange(it) },
                label = { Text(stringResource(R.string.help_report_subject_label)) },
                placeholder = { Text(stringResource(R.string.help_report_subject_hint)) },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                isError = state.errorMessage != null && state.subject.isBlank(),
            )

            // Description field
            OutlinedTextField(
                value = state.description,
                onValueChange = { viewModel.onDescriptionChange(it) },
                label = { Text(stringResource(R.string.help_report_description_label)) },
                placeholder = { Text(stringResource(R.string.help_report_description_hint)) },
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 120.dp),
                maxLines = 10,
                isError = state.errorMessage != null && state.description.isBlank(),
            )

            // Attach logs toggle
            ListItem(
                headlineContent = { Text(stringResource(R.string.help_report_attach_logs_title)) },
                supportingContent = { Text(stringResource(R.string.help_report_attach_logs_subtitle)) },
                trailingContent = {
                    Switch(
                        checked = state.attachLogs,
                        onCheckedChange = { viewModel.onAttachLogsToggle(it) },
                    )
                },
            )

            if (state.errorMessage != null) {
                Text(
                    text = state.errorMessage!!,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall,
                )
            }

            // Submit button
            FilledTonalButton(
                onClick = {
                    if (state.subject.isBlank() || state.description.isBlank()) {
                        // Let field isError handle the visual — just return
                        return@FilledTonalButton
                    }
                    val body = buildString {
                        append(state.description)
                        if (state.attachLogs) {
                            appendLine()
                            appendLine()
                            append(viewModel.buildRedactedLogSnippet())
                        }
                    }
                    val intent = Intent(Intent.ACTION_SENDTO).apply {
                        data = Uri.parse("mailto:")
                        putExtra(Intent.EXTRA_EMAIL, arrayOf(state.adminEmail))
                        putExtra(Intent.EXTRA_SUBJECT, state.subject)
                        putExtra(Intent.EXTRA_TEXT, body)
                    }
                    if (intent.resolveActivity(context.packageManager) != null) {
                        context.startActivity(intent)
                    }
                },
                modifier = Modifier.align(Alignment.End),
                enabled = !state.isSending,
            ) {
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.Send,
                    contentDescription = null,
                    modifier = Modifier.size(ButtonDefaults.IconSize),
                )
                Spacer(modifier = Modifier.size(ButtonDefaults.IconSpacing))
                Text(stringResource(R.string.help_report_send_action))
            }
        }
    }
}
