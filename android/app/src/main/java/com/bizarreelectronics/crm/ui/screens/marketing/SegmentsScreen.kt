package com.bizarreelectronics.crm.ui.screens.marketing

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.data.remote.api.CustomerSegment
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState

// ─── Screen ──────────────────────────────────────────────────────────────────

/**
 * Segment list: shows saved segments with member count, auto/manual badge,
 * refresh button per row, and a FAB to create new segments.
 *
 * Plan §37.3 ActionPlan.md L2974-L2977.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SegmentsScreen(
    onBack: () -> Unit,
    viewModel: SegmentsViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()
    val actionState by viewModel.actionState.collectAsState()
    val sizeState by viewModel.sizeState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    var showCreateSheet by remember { mutableStateOf(false) }
    var selectedSegmentId by remember { mutableStateOf<Long?>(null) }

    LaunchedEffect(actionState) {
        when (val s = actionState) {
            is SegmentActionState.Success -> {
                snackbarHostState.showSnackbar(s.message)
                viewModel.resetActionState()
            }
            is SegmentActionState.Error -> {
                snackbarHostState.showSnackbar("Error: ${s.message}")
                viewModel.resetActionState()
            }
            else -> Unit
        }
    }

    // Size preview sheet: load members when segment is selected
    LaunchedEffect(selectedSegmentId) {
        val id = selectedSegmentId
        if (id != null) {
            viewModel.loadSizePreview(id)
        } else {
            viewModel.resetSizeState()
        }
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = stringResource(R.string.screen_segments),
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
        floatingActionButton = {
            FloatingActionButton(onClick = { showCreateSheet = true }) {
                Icon(
                    Icons.Default.Add,
                    contentDescription = stringResource(R.string.cd_create_segment),
                )
            }
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        when (val s = uiState) {
            is SegmentsUiState.Loading -> BrandSkeleton(modifier = Modifier.padding(padding))
            is SegmentsUiState.NotAvailable -> Box(modifier = Modifier.padding(padding)) {
                EmptyState(
                    icon = Icons.Default.Group,
                    title = stringResource(R.string.marketing_not_available),
                    subtitle = stringResource(R.string.marketing_not_available_subtitle),
                )
            }
            is SegmentsUiState.Error -> Box(modifier = Modifier.padding(padding)) {
                ErrorState(
                    message = s.message,
                    onRetry = { viewModel.load() },
                )
            }
            is SegmentsUiState.Loaded -> {
                if (s.segments.isEmpty()) {
                    Box(modifier = Modifier.padding(padding)) {
                        EmptyState(
                            icon = Icons.Default.Group,
                            title = stringResource(R.string.segments_empty_title),
                            subtitle = stringResource(R.string.segments_empty_subtitle),
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
                        items(s.segments, key = { it.id }) { seg ->
                            SegmentCard(
                                segment = seg,
                                onRefresh = { viewModel.refreshSegment(seg.id) },
                                onPreviewSize = { selectedSegmentId = seg.id },
                            )
                        }
                    }
                }
            }
        }
    }

    // ── Create segment bottom sheet ───────────────────────────────────────────
    if (showCreateSheet) {
        CreateSegmentSheet(
            onDismiss = { showCreateSheet = false },
            onCreate = { name, desc, rule ->
                viewModel.createSegment(name, desc, rule)
                showCreateSheet = false
            },
        )
    }

    // ── Size preview bottom sheet ─────────────────────────────────────────────
    if (selectedSegmentId != null) {
        SegmentSizeSheet(
            sizeState = sizeState,
            onDismiss = { selectedSegmentId = null },
        )
    }
}

// ─── SegmentCard ──────────────────────────────────────────────────────────────

@Composable
private fun SegmentCard(
    segment: CustomerSegment,
    onRefresh: () -> Unit,
    onPreviewSize: () -> Unit,
) {
    OutlinedCard(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(segment.name, style = MaterialTheme.typography.bodyMedium)
                    if (segment.isAuto == 1) {
                        AssistChip(
                            onClick = {},
                            label = { Text("Auto", style = MaterialTheme.typography.labelSmall) },
                        )
                    }
                }
                if (!segment.description.isNullOrBlank()) {
                    Text(
                        segment.description,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                FilledTonalButton(
                    onClick = onPreviewSize,
                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp),
                ) {
                    Text(
                        stringResource(R.string.segment_size_preview, segment.memberCount),
                        style = MaterialTheme.typography.labelSmall,
                    )
                }
            }
            IconButton(onClick = onRefresh) {
                Icon(
                    Icons.Default.Refresh,
                    contentDescription = stringResource(R.string.cd_refresh_segment),
                    tint = MaterialTheme.colorScheme.secondary,
                )
            }
        }
    }
}

// ─── Create segment sheet ─────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CreateSegmentSheet(
    onDismiss: () -> Unit,
    onCreate: (String, String?, String) -> Unit,
) {
    var name by remember { mutableStateOf("") }
    var description by remember { mutableStateOf("") }
    var ruleJson by remember { mutableStateOf("{}") }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .padding(horizontal = 24.dp, vertical = 8.dp)
                .navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(stringResource(R.string.segment_create_title), style = MaterialTheme.typography.titleMedium)

            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text(stringResource(R.string.segment_name_label)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )

            OutlinedTextField(
                value = description,
                onValueChange = { description = it },
                label = { Text(stringResource(R.string.segment_description_label)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )

            OutlinedTextField(
                value = ruleJson,
                onValueChange = { ruleJson = it },
                label = { Text(stringResource(R.string.segment_rule_json_label)) },
                minLines = 3,
                modifier = Modifier.fillMaxWidth(),
            )

            Text(
                stringResource(R.string.segment_rule_hint),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End,
            ) {
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) }
                Spacer(Modifier.width(8.dp))
                FilledTonalButton(
                    onClick = { onCreate(name.trim(), description, ruleJson.trim()) },
                    enabled = name.isNotBlank() && ruleJson.isNotBlank(),
                ) {
                    Text(stringResource(R.string.create))
                }
            }
            Spacer(Modifier.height(8.dp))
        }
    }
}

// ─── Size preview sheet ───────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SegmentSizeSheet(
    sizeState: SegmentSizeState,
    onDismiss: () -> Unit,
) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .padding(24.dp)
                .navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(stringResource(R.string.segment_size_sheet_title), style = MaterialTheme.typography.titleMedium)
            when (val s = sizeState) {
                is SegmentSizeState.Loading -> CircularProgressIndicator(modifier = Modifier.align(Alignment.CenterHorizontally))
                is SegmentSizeState.Loaded  -> {
                    Text(
                        stringResource(R.string.segment_size_result, s.data.total),
                        style = MaterialTheme.typography.headlineMedium,
                        color = MaterialTheme.colorScheme.primary,
                    )
                    Text(
                        stringResource(R.string.segment_size_subtitle),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                is SegmentSizeState.Error   -> Text(
                    "Error: ${s.message}",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.error,
                )
                is SegmentSizeState.Idle    -> Unit
            }
            Spacer(Modifier.height(8.dp))
            FilledTonalButton(onClick = onDismiss, modifier = Modifier.align(Alignment.End)) {
                Text(stringResource(R.string.close))
            }
            Spacer(Modifier.height(8.dp))
        }
    }
}
