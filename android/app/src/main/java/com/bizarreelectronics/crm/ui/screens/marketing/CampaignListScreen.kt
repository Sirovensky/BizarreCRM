package com.bizarreelectronics.crm.ui.screens.marketing

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Campaign
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.*
import androidx.compose.runtime.*
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
 * Campaign list screen — status tabs (Draft / Active / Paused / Archived) with
 * per-campaign metric chips (sends / replies / converted).
 *
 * ConfirmDialog guards "Send now" action per task constraints.
 *
 * Plan §37.1 ActionPlan.md L2963-L2965.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CampaignListScreen(
    onBack: () -> Unit,
    onCreateCampaign: () -> Unit,
    onCampaignClick: (Long) -> Unit,
    viewModel: CampaignListViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()
    val actionState by viewModel.actionState.collectAsState()
    val statusFilter by viewModel.statusFilter.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    var campaignToSend by remember { mutableStateOf<Campaign?>(null) }

    // Surface action results via snackbar
    LaunchedEffect(actionState) {
        when (val s = actionState) {
            is CampaignActionState.SendSuccess -> {
                snackbarHostState.showSnackbar(s.result)
                viewModel.resetActionState()
            }
            is CampaignActionState.Error -> {
                snackbarHostState.showSnackbar("Error: ${s.message}")
                viewModel.resetActionState()
            }
            else -> Unit
        }
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = stringResource(R.string.screen_campaigns),
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.cd_back),
                        )
                    }
                },
                actions = {
                    IconButton(onClick = onCreateCampaign) {
                        Icon(
                            Icons.Default.Add,
                            contentDescription = stringResource(R.string.cd_create_campaign),
                        )
                    }
                },
            )
        },
        floatingActionButton = {
            FloatingActionButton(onClick = onCreateCampaign) {
                Icon(
                    Icons.Default.Add,
                    contentDescription = stringResource(R.string.cd_create_campaign),
                )
            }
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Column(modifier = Modifier.padding(padding)) {
            // ── Status filter chips ───────────────────────────────────────────
            val statuses = listOf(null, "draft", "active", "paused", "archived")
            val labels = listOf("All", "Draft", "Active", "Paused", "Archived")
            LazyRow(
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(statuses.size) { i ->
                    FilterChip(
                        selected = statusFilter == statuses[i],
                        onClick = { viewModel.setStatusFilter(statuses[i]) },
                        label = { Text(labels[i], style = MaterialTheme.typography.labelMedium) },
                    )
                }
            }

            when (val s = uiState) {
                is CampaignListUiState.Loading -> BrandSkeleton()
                is CampaignListUiState.NotAvailable -> EmptyState(
                    icon = Icons.Default.Campaign,
                    title = stringResource(R.string.marketing_not_available),
                    subtitle = stringResource(R.string.marketing_not_available_subtitle),
                )
                is CampaignListUiState.Error -> ErrorState(
                    message = s.message,
                    onRetry = { viewModel.load() },
                )
                is CampaignListUiState.Loaded -> {
                    if (s.campaigns.isEmpty()) {
                        EmptyState(
                            icon = Icons.Default.Campaign,
                            title = stringResource(R.string.campaigns_empty_title),
                            subtitle = stringResource(R.string.campaigns_empty_subtitle),
                        )
                    } else {
                        LazyColumn(contentPadding = PaddingValues(bottom = 80.dp)) {
                            items(s.campaigns, key = { it.id }) { campaign ->
                                CampaignRow(
                                    campaign = campaign,
                                    onSendNow = { campaignToSend = campaign },
                                    onCampaignClick = { onCampaignClick(campaign.id) },
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    // ── "Send campaign" ConfirmDialog ─────────────────────────────────────────
    campaignToSend?.let { c ->
        ConfirmDialog(
            title = stringResource(R.string.campaign_send_confirm_title),
            message = stringResource(R.string.campaign_send_confirm_msg, c.name),
            confirmLabel = stringResource(R.string.campaign_send_confirm_btn),
            onConfirm = {
                viewModel.runCampaignNow(c)
                campaignToSend = null
            },
            onDismiss = { campaignToSend = null },
        )
    }
}

// ─── CampaignRow ─────────────────────────────────────────────────────────────

@Composable
private fun CampaignRow(
    campaign: Campaign,
    onSendNow: () -> Unit,
    onCampaignClick: () -> Unit,
) {
    ListItem(
        headlineContent = {
            Text(campaign.name, style = MaterialTheme.typography.bodyMedium)
        },
        supportingContent = {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    "Channel: ${campaign.channel.uppercase()}  ·  Type: ${campaign.type.replace('_', ' ')}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                // Metric chips: sends / replies / converted
                LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    item {
                        AssistChip(
                            onClick = {},
                            label = {
                                Text(
                                    "Sent ${campaign.sentCount}",
                                    style = MaterialTheme.typography.labelSmall,
                                )
                            },
                        )
                    }
                    item {
                        AssistChip(
                            onClick = {},
                            label = {
                                Text(
                                    "Replied ${campaign.repliedCount}",
                                    style = MaterialTheme.typography.labelSmall,
                                )
                            },
                        )
                    }
                    item {
                        AssistChip(
                            onClick = {},
                            label = {
                                Text(
                                    "Converted ${campaign.convertedCount}",
                                    style = MaterialTheme.typography.labelSmall,
                                )
                            },
                        )
                    }
                }
            }
        },
        leadingContent = {
            Icon(
                Icons.Default.Campaign,
                contentDescription = stringResource(R.string.cd_campaign_icon),
                tint = MaterialTheme.colorScheme.primary,
            )
        },
        trailingContent = {
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                BrandStatusBadge(label = campaign.status, status = campaign.status)
                if (campaign.status != "archived") {
                    IconButton(onClick = onSendNow) {
                        Icon(
                            Icons.Default.PlayArrow,
                            contentDescription = stringResource(R.string.cd_send_campaign),
                            tint = MaterialTheme.colorScheme.secondary,
                        )
                    }
                }
            }
        },
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onCampaignClick),
    )
    HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f))
}
