package com.bizarreelectronics.crm.ui.screens.marketing

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.data.remote.api.Campaign
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandStatusBadge
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ConfirmDialog
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState

// ─── Screen ──────────────────────────────────────────────────────────────────

/**
 * Automations screen: event- and cron-driven campaigns (birthday, win-back,
 * review-request, churn-warning). Toggle active/paused, run-now.
 *
 * Plan §37.4 ActionPlan.md L2979-L2981.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AutomationsScreen(
    onBack: () -> Unit,
    viewModel: AutomationsViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()
    val actionState by viewModel.actionState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    var campaignToRunNow by remember { mutableStateOf<Campaign?>(null) }

    LaunchedEffect(actionState) {
        when (val s = actionState) {
            is AutomationActionState.DispatchSuccess -> {
                snackbarHostState.showSnackbar(
                    "Sent ${s.result.sent} / ${s.result.attempted} messages"
                )
                viewModel.resetActionState()
            }
            is AutomationActionState.StatusUpdateSuccess -> {
                snackbarHostState.showSnackbar("${s.campaignName} → ${s.newStatus}")
                viewModel.resetActionState()
            }
            is AutomationActionState.Error -> {
                snackbarHostState.showSnackbar("Error: ${s.message}")
                viewModel.resetActionState()
            }
            else -> Unit
        }
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = stringResource(R.string.screen_automations),
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.cd_back),
                        )
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        when (val s = uiState) {
            is AutomationsUiState.Loading -> BrandSkeleton(modifier = Modifier.padding(padding))
            is AutomationsUiState.NotAvailable -> Box(modifier = Modifier.padding(padding)) {
                EmptyState(
                    icon = Icons.Default.AutoAwesome,
                    title = stringResource(R.string.marketing_not_available),
                    subtitle = stringResource(R.string.marketing_not_available_subtitle),
                )
            }
            is AutomationsUiState.Error -> Box(modifier = Modifier.padding(padding)) {
                ErrorState(
                    message = s.message,
                    onRetry = { viewModel.load() },
                )
            }
            is AutomationsUiState.Loaded -> {
                if (s.automations.isEmpty()) {
                    Box(modifier = Modifier.padding(padding)) {
                    EmptyState(
                        icon = Icons.Default.AutoAwesome,
                        title = stringResource(R.string.automations_empty_title),
                        subtitle = stringResource(R.string.automations_empty_subtitle),
                    )
                    }
                } else {
                    LazyColumn(
                        contentPadding = PaddingValues(
                            start = 16.dp,
                            end = 16.dp,
                            top = padding.calculateTopPadding() + 8.dp,
                            bottom = 80.dp,
                        ),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        items(s.automations, key = { it.id }) { campaign ->
                            AutomationCard(
                                campaign = campaign,
                                onToggleActive = { active -> viewModel.setStatus(campaign, active) },
                                onRunNow = { campaignToRunNow = campaign },
                            )
                        }
                    }
                }
            }
        }
    }

    // ConfirmDialog for run-now
    campaignToRunNow?.let { c ->
        ConfirmDialog(
            title = stringResource(R.string.campaign_send_confirm_title),
            message = stringResource(R.string.campaign_send_confirm_msg, c.name),
            confirmLabel = stringResource(R.string.campaign_send_confirm_btn),
            onConfirm = {
                viewModel.runNow(c)
                campaignToRunNow = null
            },
            onDismiss = { campaignToRunNow = null },
        )
    }
}

// ─── AutomationCard ───────────────────────────────────────────────────────────

@Composable
private fun AutomationCard(
    campaign: Campaign,
    onToggleActive: (Boolean) -> Unit,
    onRunNow: () -> Unit,
) {
    val isActive = campaign.status == "active"
    val isArchived = campaign.status == "archived"

    OutlinedCard(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                Icons.Default.AutoAwesome,
                contentDescription = stringResource(R.string.cd_automation_icon),
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier
                    .size(24.dp)
                    .padding(end = 0.dp),
            )
            Spacer(Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(campaign.name, style = MaterialTheme.typography.bodyMedium)
                Text(
                    campaign.type.replace('_', ' ').replaceFirstChar { it.uppercase() },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Row(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    BrandStatusBadge(label = campaign.status, status = campaign.status)
                    Text(
                        "Sent ${campaign.sentCount}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            if (!isArchived) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    // Active toggle
                    Switch(
                        checked = isActive,
                        onCheckedChange = onToggleActive,
                    )
                    // Run now
                    IconButton(onClick = onRunNow, modifier = Modifier.size(32.dp)) {
                        Icon(
                            Icons.Default.PlayArrow,
                            contentDescription = stringResource(R.string.cd_send_campaign),
                            tint = MaterialTheme.colorScheme.secondary,
                            modifier = Modifier.size(20.dp),
                        )
                    }
                }
            }
        }
    }
}
