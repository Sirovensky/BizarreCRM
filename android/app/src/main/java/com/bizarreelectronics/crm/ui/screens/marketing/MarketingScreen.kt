package com.bizarreelectronics.crm.ui.screens.marketing

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.remote.api.CampaignDto
import com.bizarreelectronics.crm.data.remote.api.CampaignRunResult
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ConfirmDialog
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.viewmodels.marketing.CAMPAIGN_STATUS_TABS
import com.bizarreelectronics.crm.viewmodels.marketing.MarketingViewModel

// Brand cream — matches theme primary token.
private val BrandCream = Color(0xFFFDEED0)

/**
 * §37 Marketing & Growth — top-level screen.
 *
 * Hosts two sub-sections: Campaigns (§37.1-37.2) and Segments (§37.3).
 * A FAB opens the campaign-create bottom sheet.
 *
 * Features wired to live server data:
 *   - Campaign list with status-tab filter
 *   - Create campaign (name / type / channel / body / segment)
 *   - Preview recipient count → ConfirmDialog → dispatch (§37.2 send flow)
 *   - Open/click/sent metrics card (§37.1)
 *   - Segment list + create segment (§37.3)
 *
 * Features deferred (server endpoints not yet shipped):
 *   - A/B test variant toggle (§37.2 — no server support)
 *   - Merge-tag per-recipient preview (§37.2 — UI-only future work)
 *   - Automations (§37.4 — no /campaigns/automations endpoint)
 *   - Review solicitation NPS flow (§37.5 — UI for /review-request/trigger future)
 *   - Referral program (§37.6 — no referral endpoints)
 *   - Coupons (§37.7 — no coupon endpoints)
 *   - QR campaigns + print (§37.8 — no QR endpoint)
 *
 * Plan §37 ActionPlan.md lines 3255-3360.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MarketingScreen(
    onBack: () -> Unit = {},
    viewModel: MarketingViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    // Toast
    val snackbarHostState = remember { SnackbarHostState() }
    LaunchedEffect(state.toastMessage) {
        state.toastMessage?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearToast()
        }
    }

    // Campaign-create sheet
    var showCreateSheet by remember { mutableStateOf(false) }

    // Segment-create dialog
    var showSegmentDialog by remember { mutableStateOf(false) }

    // Confirm-send dialog
    val pendingId = state.pendingSendCampaignId
    val pendingCount = state.pendingSendPreviewCount

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Marketing",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { viewModel.refresh() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
                    }
                }
            )
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = { showCreateSheet = true },
                containerColor = BrandCream,
                contentColor = Color.Black,
            ) {
                Icon(Icons.Default.Add, contentDescription = "Create campaign")
            }
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { innerPadding ->

        if (state.isLoading) {
            Box(
                Modifier
                    .fillMaxSize()
                    .padding(innerPadding),
                contentAlignment = Alignment.Center,
            ) { CircularProgressIndicator() }
            return@Scaffold
        }

        if (state.error != null && state.campaigns.isEmpty()) {
            Box(modifier = Modifier.padding(innerPadding)) {
                ErrorState(message = state.error!!, onRetry = { viewModel.refresh() })
            }
            return@Scaffold
        }

        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            verticalArrangement = Arrangement.spacedBy(0.dp),
        ) {

            // ── Metrics overview card (§37.1) ─────────────────────────────────
            item {
                MarketingMetricsCard(campaigns = state.campaigns)
            }

            // ── Section header: Campaigns ─────────────────────────────────────
            item {
                Text(
                    text = "Campaigns",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier
                        .padding(horizontal = 16.dp, vertical = 12.dp)
                        .semantics { heading() },
                )
            }

            // ── Status tabs ───────────────────────────────────────────────────
            item {
                LazyRow(
                    contentPadding = PaddingValues(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(CAMPAIGN_STATUS_TABS) { tab ->
                        FilterChip(
                            selected = state.selectedStatusTab == tab,
                            onClick = { viewModel.selectStatusTab(tab) },
                            label = { Text(tab) },
                            colors = FilterChipDefaults.filterChipColors(
                                selectedContainerColor = BrandCream,
                                selectedLabelColor = Color.Black,
                            ),
                        )
                    }
                }
                Spacer(Modifier.height(8.dp))
            }

            // ── Campaign rows ─────────────────────────────────────────────────
            val filtered = if (state.selectedStatusTab == "All") {
                state.campaigns
            } else {
                state.campaigns.filter {
                    it.status.equals(state.selectedStatusTab, ignoreCase = true)
                }
            }

            if (filtered.isEmpty()) {
                item {
                    EmptyState(
                        title = "No campaigns",
                        subtitle = if (state.selectedStatusTab == "All")
                            "Tap + to create your first campaign."
                        else
                            "No ${state.selectedStatusTab.lowercase()} campaigns.",
                    )
                }
            } else {
                items(filtered, key = { it.id }) { campaign ->
                    CampaignRow(
                        campaign = campaign,
                        onSendClick = { viewModel.requestSend(campaign.id) },
                        onStatsClick = { viewModel.loadCampaignStats(campaign.id) },
                        onArchiveClick = { viewModel.archiveCampaign(campaign.id) },
                    )
                }
            }

            // ── Section header: Segments (§37.3) ──────────────────────────────
            item {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(start = 16.dp, end = 8.dp, top = 16.dp, bottom = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = "Segments",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier
                            .weight(1f)
                            .semantics { heading() },
                    )
                    TextButton(onClick = { showSegmentDialog = true }) {
                        Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(4.dp))
                        Text("New")
                    }
                }
            }

            if (state.segments.isEmpty()) {
                item {
                    EmptyState(
                        title = "No segments",
                        subtitle = "Segments let you target specific customer groups.",
                    )
                }
            } else {
                items(state.segments, key = { "seg-${it.id}" }) { segment ->
                    SegmentRow(segment = segment)
                }
            }

            item { Spacer(Modifier.height(80.dp)) }
        }
    }

    // ── Send confirm dialog ───────────────────────────────────────────────────
    if (pendingId != null) {
        val countText = pendingCount?.toString() ?: "an unknown number of"
        ConfirmDialog(
            title = "Send campaign?",
            message = "This will immediately send to $countText eligible recipient(s). " +
                    "Only opted-in contacts receive messages (TCPA compliant).",
            confirmLabel = "Send now",
            onConfirm = { viewModel.confirmSend() },
            onDismiss = { viewModel.cancelSend() },
        )
    }

    // ── Create campaign sheet ─────────────────────────────────────────────────
    if (showCreateSheet) {
        CreateCampaignSheet(
            segments = state.segments,
            onDismiss = { showCreateSheet = false },
            onCreate = { request ->
                viewModel.createCampaign(request) { showCreateSheet = false }
            },
        )
    }

    // ── Create segment dialog ─────────────────────────────────────────────────
    if (showSegmentDialog) {
        CreateSegmentDialog(
            onDismiss = { showSegmentDialog = false },
            onConfirm = { name, desc ->
                viewModel.createSegment(name, desc) { showSegmentDialog = false }
            },
        )
    }

    // ── Stats sheet ───────────────────────────────────────────────────────────
    val openStats = state.openCampaignStats
    if (openStats != null) {
        CampaignStatsSheet(
            stats = openStats,
            onDismiss = { viewModel.clearCampaignStats() },
        )
    }

    // ── Dispatch result snackbar (already shown via toastMessage; also surface as card) ──
    val dispatchResult = state.lastDispatchResult
    if (dispatchResult != null) {
        DispatchResultDialog(
            result = dispatchResult,
            onDismiss = { viewModel.clearDispatchResult() },
        )
    }
}

// ─── Metrics overview card ────────────────────────────────────────────────────

@Composable
private fun MarketingMetricsCard(campaigns: List<CampaignDto>) {
    val totalSent = campaigns.sumOf { it.sentCount }
    val totalReplied = campaigns.sumOf { it.repliedCount }
    val totalConverted = campaigns.sumOf { it.convertedCount }

    BrandCard(modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = "Overview",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(8.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly,
            ) {
                MetricChip(label = "Sent", value = totalSent.toString())
                MetricChip(label = "Replied", value = totalReplied.toString())
                MetricChip(label = "Converted", value = totalConverted.toString())
                MetricChip(label = "Campaigns", value = campaigns.size.toString())
            }
        }
    }
}

@Composable
private fun MetricChip(label: String, value: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            text = value,
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
            color = Color(0xFFFDEED0),
        )
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
