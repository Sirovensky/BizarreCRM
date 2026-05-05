package com.bizarreelectronics.crm.ui.screens.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshots.SnapshotStateMap
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel

/**
 * Plan §20.5 L2118 — Conflict resolution screen.
 *
 * Displays a [LazyColumn] of pending sync conflicts. Each conflict card shows
 * the conflicting fields side-by-side with "Keep Mine / Keep Theirs / Merge"
 * chip selectors. Submitting posts `POST /sync/conflicts/resolve` via
 * [ConflictResolutionViewModel.submit].
 *
 * The screen respects the phone + tablet density guideline: chips and buttons
 * are touch-friendly (48dp min height) while the field labels remain concise.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConflictResolutionScreen(
    onBack: () -> Unit,
    viewModel: ConflictResolutionViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()
    val message by viewModel.message.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(message) {
        if (message != null) {
            snackbarHostState.showSnackbar(message!!)
            viewModel.clearMessage()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Sync Conflicts") },
                navigationIcon = {
                    OutlinedButton(
                        onClick = onBack,
                        modifier = Modifier.padding(start = 8.dp),
                    ) {
                        Text("Back")
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
        ) {
            when (val state = uiState) {
                is ConflictResolutionUiState.Empty -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(
                            text = "No pending conflicts",
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }

                is ConflictResolutionUiState.Content -> {
                    ConflictList(
                        conflicts = state.conflicts,
                        onSubmit = { conflictId, entityType, entityId, choices, myValues ->
                            viewModel.submit(conflictId, entityType, entityId, choices, myValues)
                        },
                    )
                }

                is ConflictResolutionUiState.Submitting -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                }

                is ConflictResolutionUiState.Error -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(
                                text = state.message,
                                color = MaterialTheme.colorScheme.error,
                                style = MaterialTheme.typography.bodyMedium,
                            )
                            Spacer(Modifier.height(12.dp))
                            Button(onClick = { viewModel.refresh() }) {
                                Text("Retry")
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ConflictList(
    conflicts: List<ConflictUi>,
    onSubmit: (Long, String, Long, Map<String, FieldChoice>, Map<String, String>) -> Unit,
) {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item { Spacer(Modifier.height(8.dp)) }
        items(conflicts, key = { it.conflictId }) { conflict ->
            ConflictCard(conflict = conflict, onSubmit = onSubmit)
        }
        item { Spacer(Modifier.height(16.dp)) }
    }
}

@Composable
private fun ConflictCard(
    conflict: ConflictUi,
    onSubmit: (Long, String, Long, Map<String, FieldChoice>, Map<String, String>) -> Unit,
) {
    // Per-field choice state — defaults to THEIRS (server wins).
    val choices: SnapshotStateMap<String, FieldChoice> = remember(conflict.conflictId) {
        mutableStateMapOf<String, FieldChoice>().also { map ->
            conflict.fields.forEach { f -> map[f.fieldName] = FieldChoice.THEIRS }
        }
    }

    Card(
        modifier = Modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = "${conflict.entityType.replaceFirstChar { it.uppercaseChar() }} #${conflict.entityId}",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(Modifier.height(8.dp))

            conflict.fields.forEachIndexed { index, field ->
                if (index > 0) HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
                FieldConflictRow(
                    field = field,
                    choice = choices[field.fieldName] ?: FieldChoice.THEIRS,
                    onChoiceChange = { choices[field.fieldName] = it },
                )
            }

            Spacer(Modifier.height(16.dp))

            Button(
                onClick = {
                    // For MINE choices, pass the client value as myValues.
                    val myValues = conflict.fields
                        .filter { choices[it.fieldName] == FieldChoice.MINE }
                        .associate { it.fieldName to it.clientValue }
                    onSubmit(
                        conflict.conflictId,
                        conflict.entityType,
                        conflict.entityId,
                        choices.toMap(),
                        myValues,
                    )
                },
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.primary,
                ),
            ) {
                Text("Apply resolution")
            }
        }
    }
}

@Composable
private fun FieldConflictRow(
    field: FieldConflictUi,
    choice: FieldChoice,
    onChoiceChange: (FieldChoice) -> Unit,
) {
    Column {
        Text(
            text = field.fieldName,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(4.dp))
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    "Mine",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    field.clientValue,
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    "Theirs",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    field.serverValue,
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(
                selected = choice == FieldChoice.MINE,
                onClick = { onChoiceChange(FieldChoice.MINE) },
                label = { Text("Keep mine") },
            )
            FilterChip(
                selected = choice == FieldChoice.THEIRS,
                onClick = { onChoiceChange(FieldChoice.THEIRS) },
                label = { Text("Keep theirs") },
            )
            FilterChip(
                selected = choice == FieldChoice.MERGE,
                onClick = { onChoiceChange(FieldChoice.MERGE) },
                label = { Text("Merge") },
            )
        }
    }
}
