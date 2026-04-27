package com.bizarreelectronics.crm.ui.screens.marketing

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Merge
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.data.remote.api.CustomerSegment
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ConfirmDialog
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.components.shared.LoadingIndicator

// ─── Screen ──────────────────────────────────────────────────────────────────

/**
 * Multi-step campaign builder: Audience → Message → Review.
 *
 * Merge-tag reference chips shown in the message step.
 * TCPA note (opt-in recipients only) shown in the Review step.
 *
 * Deferred (server schema):
 *   - A/B test variant (50/50 split): no `variant_b_body` column in schema.
 *   - Scheduled / recurring: no `scheduled_at`/`recurring_cron` columns.
 *   - Per-recipient preview with fully merged values: handled server-side by
 *     POST /campaigns/:id/preview (shown in Review step after save-to-draft).
 *
 * Plan §37.2 ActionPlan.md L2967-L2972.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CampaignBuilderScreen(
    onBack: () -> Unit,
    onSaved: (Long) -> Unit,
    viewModel: CampaignBuilderViewModel = hiltViewModel(),
) {
    val step by viewModel.step.collectAsState()
    val builderUiState by viewModel.builderUiState.collectAsState()
    val segmentLoadState by viewModel.segmentLoadState.collectAsState()
    val previewState by viewModel.previewState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    var showSendConfirm by remember { mutableStateOf(false) }

    LaunchedEffect(builderUiState) {
        when (val s = builderUiState) {
            is BuilderUiState.SaveSuccess -> {
                onSaved(s.campaign.id)
                viewModel.resetBuilderState()
            }
            is BuilderUiState.Error -> {
                snackbarHostState.showSnackbar("Error: ${s.message}")
                viewModel.resetBuilderState()
            }
            else -> Unit
        }
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = stringResource(R.string.screen_campaign_builder),
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
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState()),
        ) {
            // ── Step indicator ────────────────────────────────────────────────
            StepIndicator(step = step)

            Spacer(modifier = Modifier.height(8.dp))

            when (step) {
                BuilderStep.AUDIENCE -> AudienceStep(viewModel, segmentLoadState)
                BuilderStep.MESSAGE  -> MessageStep(viewModel)
                BuilderStep.REVIEW   -> ReviewStep(viewModel, previewState)
            }

            Spacer(modifier = Modifier.height(16.dp))

            // ── Navigation row ────────────────────────────────────────────────
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                if (step != BuilderStep.AUDIENCE) {
                    OutlinedButton(onClick = { viewModel.goPreviousStep() }) {
                        Text(stringResource(R.string.back))
                    }
                } else {
                    Spacer(modifier = Modifier.width(1.dp))
                }

                when (step) {
                    BuilderStep.AUDIENCE, BuilderStep.MESSAGE -> {
                        FilledTonalButton(
                            onClick = { viewModel.goNextStep() },
                            enabled = isStepValid(step, viewModel),
                        ) {
                            Text(stringResource(R.string.next))
                        }
                    }
                    BuilderStep.REVIEW -> {
                        FilledTonalButton(
                            onClick = { showSendConfirm = true },
                            enabled = builderUiState != BuilderUiState.Saving,
                        ) {
                            if (builderUiState == BuilderUiState.Saving) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(16.dp),
                                    strokeWidth = 2.dp,
                                )
                            } else {
                                Text(stringResource(R.string.campaign_save_draft))
                            }
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(32.dp))
        }
    }

    // ── "Save campaign" ConfirmDialog ─────────────────────────────────────────
    if (showSendConfirm) {
        ConfirmDialog(
            title = stringResource(R.string.campaign_builder_confirm_title),
            message = stringResource(R.string.campaign_builder_confirm_msg),
            confirmLabel = stringResource(R.string.campaign_save_draft),
            onConfirm = {
                showSendConfirm = false
                viewModel.saveDraft()
            },
            onDismiss = { showSendConfirm = false },
        )
    }
}

// ─── Step indicator ───────────────────────────────────────────────────────────

@Composable
private fun StepIndicator(step: BuilderStep) {
    val steps = listOf(
        BuilderStep.AUDIENCE to "Audience",
        BuilderStep.MESSAGE  to "Message",
        BuilderStep.REVIEW   to "Review",
    )
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        steps.forEach { (s, label) ->
            val active = s == step
            val done = s.ordinal < step.ordinal
            FilterChip(
                selected = active || done,
                onClick = {},
                label = {
                    Text(
                        label,
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = if (active) FontWeight.Bold else FontWeight.Normal,
                    )
                },
                modifier = Modifier.weight(1f),
            )
        }
    }
}

// ─── Step: Audience ───────────────────────────────────────────────────────────

@Composable
private fun AudienceStep(
    viewModel: CampaignBuilderViewModel,
    segmentLoadState: SegmentLoadState,
) {
    val campaignName by viewModel.campaignName.collectAsState()
    val campaignType by viewModel.campaignType.collectAsState()
    val selectedSegmentId by viewModel.selectedSegmentId.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            stringResource(R.string.campaign_step_audience),
            style = MaterialTheme.typography.titleMedium,
        )

        OutlinedTextField(
            value = campaignName,
            onValueChange = { viewModel.campaignName.value = it },
            label = { Text(stringResource(R.string.campaign_name_label)) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )

        // Campaign type picker
        Text(
            stringResource(R.string.campaign_type_label),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        val types = listOf(
            "custom" to "Custom",
            "birthday" to "Birthday",
            "winback" to "Win-back",
            "review_request" to "Review Request",
            "churn_warning" to "Churn Warning",
            "service_subscription" to "Service Subscription",
        )
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            types.chunked(2).forEach { pair ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    pair.forEach { (value, label) ->
                        FilterChip(
                            selected = campaignType == value,
                            onClick = { viewModel.campaignType.value = value },
                            label = { Text(label, style = MaterialTheme.typography.labelSmall) },
                            modifier = Modifier.weight(1f),
                        )
                    }
                    if (pair.size == 1) Spacer(modifier = Modifier.weight(1f))
                }
            }
        }

        // Segment picker
        Text(
            stringResource(R.string.campaign_segment_label),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        when (segmentLoadState) {
            is SegmentLoadState.Loading -> LoadingIndicator()
            is SegmentLoadState.Error   -> ErrorState(
                message = segmentLoadState.message,
                onRetry = { viewModel.loadSegments() },
            )
            is SegmentLoadState.Loaded  -> {
                SegmentPicker(
                    segments = segmentLoadState.segments,
                    selectedId = selectedSegmentId,
                    onSelect = { viewModel.selectedSegmentId.value = it },
                )
            }
        }
    }
}

@Composable
private fun SegmentPicker(
    segments: List<CustomerSegment>,
    selectedId: Long?,
    onSelect: (Long?) -> Unit,
) {
    OutlinedCard(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            // "All customers" option
            FilterChip(
                selected = selectedId == null,
                onClick = { onSelect(null) },
                label = { Text("All customers", style = MaterialTheme.typography.labelMedium) },
                modifier = Modifier.fillMaxWidth(),
            )
            segments.forEach { seg ->
                FilterChip(
                    selected = selectedId == seg.id,
                    onClick = { onSelect(seg.id) },
                    label = {
                        Text(
                            "${seg.name} (${seg.memberCount})",
                            style = MaterialTheme.typography.labelMedium,
                        )
                    },
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}

// ─── Step: Message ────────────────────────────────────────────────────────────

@Composable
private fun MessageStep(viewModel: CampaignBuilderViewModel) {
    val channel by viewModel.channel.collectAsState()
    val templateBody by viewModel.templateBody.collectAsState()
    val templateSubject by viewModel.templateSubject.collectAsState()

    // Merge-tag reference chips
    val mergeTags = listOf(
        "{{customer.first_name}}",
        "{{ticket.status}}",
        "{{shop.name}}",
        "{{coupon.code}}",
    )

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            stringResource(R.string.campaign_step_message),
            style = MaterialTheme.typography.titleMedium,
        )

        // Channel selector
        Text(
            stringResource(R.string.campaign_channel_label),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("sms" to "SMS", "email" to "Email", "both" to "Both").forEach { (value, label) ->
                FilterChip(
                    selected = channel == value,
                    onClick = { viewModel.channel.value = value },
                    label = { Text(label, style = MaterialTheme.typography.labelMedium) },
                    modifier = Modifier.weight(1f),
                )
            }
        }

        if (channel == "email" || channel == "both") {
            OutlinedTextField(
                value = templateSubject,
                onValueChange = { viewModel.templateSubject.value = it },
                label = { Text(stringResource(R.string.campaign_subject_label)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
        }

        OutlinedTextField(
            value = templateBody,
            onValueChange = { viewModel.templateBody.value = it },
            label = { Text(stringResource(R.string.campaign_body_label)) },
            minLines = 4,
            maxLines = 10,
            modifier = Modifier.fillMaxWidth(),
        )

        // Merge-tag chips reference row
        Text(
            stringResource(R.string.campaign_merge_tags_label),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Row(
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            modifier = Modifier.fillMaxWidth(),
        ) {
            mergeTags.forEach { tag ->
                AssistChip(
                    onClick = {
                        viewModel.templateBody.value = viewModel.templateBody.value + tag
                    },
                    label = { Text(tag, style = MaterialTheme.typography.labelSmall) },
                    leadingIcon = {
                        Icon(
                            Icons.Default.Merge,
                            contentDescription = stringResource(R.string.cd_merge_tag),
                            modifier = Modifier.size(14.dp),
                        )
                    },
                )
            }
        }

        // TCPA compliance notice
        OutlinedCard(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    stringResource(R.string.tcpa_notice_title),
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    stringResource(R.string.tcpa_notice_body),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

// ─── Step: Review ─────────────────────────────────────────────────────────────

@Composable
private fun ReviewStep(
    viewModel: CampaignBuilderViewModel,
    previewState: PreviewState,
) {
    val campaignName by viewModel.campaignName.collectAsState()
    val campaignType by viewModel.campaignType.collectAsState()
    val channel by viewModel.channel.collectAsState()
    val templateBody by viewModel.templateBody.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            stringResource(R.string.campaign_step_review),
            style = MaterialTheme.typography.titleMedium,
        )

        // Summary card
        OutlinedCard(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                LabelValue(label = stringResource(R.string.campaign_name_label), value = campaignName)
                LabelValue(label = stringResource(R.string.campaign_type_label), value = campaignType.replace('_', ' '))
                LabelValue(label = stringResource(R.string.campaign_channel_label), value = channel.uppercase())
                LabelValue(label = stringResource(R.string.campaign_body_label), value = templateBody)
            }
        }

        // Audience preview (populated after save-as-draft on first reach of Review step)
        when (val ps = previewState) {
            is PreviewState.Loading -> LoadingIndicator()
            is PreviewState.Loaded  -> {
                Text(
                    stringResource(R.string.campaign_preview_audience, ps.preview.totalRecipients),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.secondary,
                )
                if (ps.preview.preview.isNotEmpty()) {
                    Text(
                        stringResource(R.string.campaign_preview_sample),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    ps.preview.preview.forEach { sample ->
                        OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                            Column(modifier = Modifier.padding(12.dp)) {
                                Text(
                                    sample.firstName ?: "Customer",
                                    style = MaterialTheme.typography.labelSmall,
                                    fontWeight = FontWeight.Bold,
                                )
                                Text(
                                    sample.renderedBody,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                }
            }
            is PreviewState.Error   -> Text(
                "Preview unavailable: ${ps.message}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            is PreviewState.Idle    -> Unit
        }
    }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

@Composable
private fun LabelValue(label: String, value: String) {
    Column {
        Text(
            label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(value, style = MaterialTheme.typography.bodyMedium)
    }
}

private fun isStepValid(step: BuilderStep, viewModel: CampaignBuilderViewModel): Boolean {
    return when (step) {
        BuilderStep.AUDIENCE -> viewModel.campaignName.value.isNotBlank()
        BuilderStep.MESSAGE  -> viewModel.templateBody.value.isNotBlank()
        BuilderStep.REVIEW   -> true
    }
}
