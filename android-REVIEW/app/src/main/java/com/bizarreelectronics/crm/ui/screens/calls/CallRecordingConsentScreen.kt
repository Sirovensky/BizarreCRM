package com.bizarreelectronics.crm.ui.screens.calls

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.data.remote.api.RecordingConfigData
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.ErrorState

/**
 * §42.3 — Call recording compliance screen.
 *
 * Surfaces:
 *  1. Whether the tenant has recording enabled.
 *  2. Whether the jurisdiction requires two-party consent.
 *  3. RECORD_AUDIO permission rationale + runtime grant.
 *  4. Per-session consent toggle (stored to server via POST /voice/recording-consent).
 *
 * This screen is navigated to from CallDetailScreen (for individual calls)
 * or from Voice Settings (for the tenant-wide policy view).
 *
 * Route: calls/recording-consent?callId=<id>
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CallRecordingConsentScreen(
    callId: Long,
    onBack: () -> Unit,
    viewModel: RecordingConsentViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    val snackbarHostState = remember { SnackbarHostState() }

    // RECORD_AUDIO permission
    val hasAudioPermission = remember {
        mutableStateOf(
            context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED,
        )
    }
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted -> hasAudioPermission.value = granted }

    LaunchedEffect(callId) { viewModel.loadRecordingConfig(callId) }

    LaunchedEffect(state.actionMessage) {
        state.actionMessage?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearActionMessage()
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            BrandTopAppBar(
                title = stringResource(R.string.screen_call_recording),
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.Default.ArrowBack,
                            contentDescription = stringResource(R.string.cd_navigate_back),
                        )
                    }
                },
            )
        },
    ) { padding ->
        when {
            state.isLoading -> BrandSkeleton(
                rows = 4,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
            )

            state.error != null -> Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                contentAlignment = Alignment.Center,
            ) {
                ErrorState(
                    message = state.error ?: "Failed to load recording config",
                    onRetry = { viewModel.loadRecordingConfig(callId) },
                )
            }

            else -> RecordingConsentContent(
                config = state.config,
                hasAudioPermission = hasAudioPermission.value,
                consentGiven = state.consentGiven,
                isSaving = state.isSaving,
                modifier = Modifier.padding(padding),
                onRequestAudioPermission = {
                    permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                },
                onConsentToggled = { consented ->
                    viewModel.saveConsent(callId = callId, consented = consented)
                },
            )
        }
    }
}

@Composable
private fun RecordingConsentContent(
    config: RecordingConfigData?,
    hasAudioPermission: Boolean,
    consentGiven: Boolean?,
    isSaving: Boolean,
    modifier: Modifier = Modifier,
    onRequestAudioPermission: () -> Unit,
    onConsentToggled: (Boolean) -> Unit,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Spacer(modifier = Modifier.height(8.dp))

        // Recording status card
        BrandCard(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        if (config?.enabled == true) Icons.Default.FiberManualRecord
                        else Icons.Default.RadioButtonUnchecked,
                        contentDescription = null,
                        tint = if (config?.enabled == true)
                            MaterialTheme.colorScheme.error
                        else
                            MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(20.dp),
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        if (config?.enabled == true)
                            stringResource(R.string.recording_enabled)
                        else
                            stringResource(R.string.recording_disabled),
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                    )
                }

                if (config?.enabled == true) {
                    HorizontalDivider()
                    // Two-party consent notice
                    if (config.two_party_required) {
                        Row(
                            verticalAlignment = Alignment.Top,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Icon(
                                Icons.Default.Gavel,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.tertiary,
                                modifier = Modifier.size(18.dp),
                            )
                            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Text(
                                    stringResource(R.string.recording_two_party_required_title),
                                    style = MaterialTheme.typography.bodyMedium,
                                    fontWeight = FontWeight.Medium,
                                )
                                Text(
                                    stringResource(R.string.recording_two_party_required_body),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }

                    if (config.announcement_url != null) {
                        Text(
                            stringResource(R.string.recording_announcement_configured),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }

        // RECORD_AUDIO permission card
        BrandCard(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    stringResource(R.string.recording_permission_title),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    stringResource(R.string.recording_permission_rationale),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (hasAudioPermission) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Icon(
                            Icons.Default.CheckCircle,
                            contentDescription = stringResource(R.string.recording_permission_granted_cd),
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(18.dp),
                        )
                        Text(
                            stringResource(R.string.recording_permission_granted),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                } else {
                    FilledTonalButton(
                        onClick = onRequestAudioPermission,
                        modifier = Modifier
                            .fillMaxWidth()
                            .semantics {
                                contentDescription = "Grant microphone permission for call recording"
                            },
                    ) {
                        Icon(
                            Icons.Default.Mic,
                            contentDescription = null,
                            modifier = Modifier.size(18.dp),
                        )
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(stringResource(R.string.recording_grant_permission))
                    }
                }
            }
        }

        // Per-session consent toggle (only shown when recording is enabled)
        if (config?.enabled == true) {
            BrandCard(modifier = Modifier.fillMaxWidth()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Column(
                        modifier = Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Text(
                            stringResource(R.string.recording_consent_toggle_title),
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.Medium,
                        )
                        Text(
                            stringResource(R.string.recording_consent_toggle_subtitle),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    if (isSaving) {
                        CircularProgressIndicator(modifier = Modifier.size(24.dp))
                    } else {
                        Switch(
                            checked = consentGiven == true,
                            onCheckedChange = onConsentToggled,
                            modifier = Modifier.semantics {
                                contentDescription = "Consent to record this call"
                            },
                        )
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(24.dp))
    }
}
