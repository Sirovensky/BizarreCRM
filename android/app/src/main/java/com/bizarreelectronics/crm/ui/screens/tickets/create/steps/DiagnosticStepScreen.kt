package com.bizarreelectronics.crm.ui.screens.tickets.create.steps

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.bizarreelectronics.crm.data.remote.dto.ConditionCheckItem

/**
 * Step 4 — Diagnostic / intake checklist.
 *
 * Provides:
 * - PhotoPicker integration: photos are stored as local URIs until uploaded
 *   by [MultipartUploadWorker] after ticket creation.
 * - Pre-conditions checklist: tenant-configurable items from the server
 *   (`GET /settings/condition-checks/:category`), with a sensible default set.
 * - Drag-reorder on tablet, long-press-reorder on phone (exposed via
 *   [onReorder] callback; the calling screen decides the gesture handler).
 *
 * Validation: always valid — all fields are optional.
 */
@Composable
fun DiagnosticStepScreen(
    conditionChecks: List<ConditionCheckItem>,
    selectedConditions: Set<String>,
    intakePhotoUris: List<String>,
    notes: String,
    onToggleCondition: (String) -> Unit,
    onNotesChange: (String) -> Unit,
    onPickPhotos: () -> Unit,
    onRemovePhoto: (String) -> Unit,
    onReorder: (List<String>) -> Unit,
    modifier: Modifier = Modifier,
) {
    val effectiveChecks = conditionChecks.ifEmpty { DEFAULT_CONDITION_CHECKS }

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // ── Intake photos ──────────────────────────────────────────────
        item(key = "photos_header") {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Intake photos", style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
                IconButton(onClick = onPickPhotos) {
                    Icon(Icons.Default.Add, contentDescription = "Add photos")
                }
            }
        }

        if (intakePhotoUris.isNotEmpty()) {
            item(key = "photos_grid") {
                LazyVerticalGrid(
                    columns = GridCells.Adaptive(minSize = 96.dp),
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(max = 300.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(intakePhotoUris, key = { it }) { uri ->
                        IntakePhotoTile(uri = uri, onRemove = { onRemovePhoto(uri) })
                    }
                }
            }
        }

        // ── Pre-conditions checklist ───────────────────────────────────
        item(key = "conditions_header") {
            Text("Pre-conditions", style = MaterialTheme.typography.titleSmall)
        }

        items(effectiveChecks, key = { "cond_${it.id}" }) { check ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Checkbox(
                    checked = check.label in selectedConditions,
                    onCheckedChange = { onToggleCondition(check.label) },
                )
                Spacer(Modifier.width(8.dp))
                Text(check.label, style = MaterialTheme.typography.bodyMedium)
            }
        }

        // ── Intake notes ──────────────────────────────────────────────
        item(key = "notes") {
            OutlinedTextField(
                value = notes,
                onValueChange = onNotesChange,
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 80.dp),
                label = { Text("Diagnostic notes") },
                maxLines = 6,
            )
        }
    }
}

// ── Private sub-composables ─────────────────────────────────────────────────

@Composable
private fun IntakePhotoTile(uri: String, onRemove: () -> Unit) {
    Box(modifier = Modifier.size(96.dp)) {
        AsyncImage(
            model = uri,
            contentDescription = "Intake photo",
            modifier = Modifier.fillMaxSize(),
            contentScale = ContentScale.Crop,
        )
        IconButton(
            onClick = onRemove,
            modifier = Modifier
                .align(Alignment.TopEnd)
                .size(28.dp),
        ) {
            Icon(
                Icons.Default.Delete,
                contentDescription = "Remove photo",
                tint = MaterialTheme.colorScheme.error,
                modifier = Modifier.size(18.dp),
            )
        }
    }
}

// ── Defaults ─────────────────────────────────────────────────────────────────

/**
 * Default pre-condition items used when the server returns an empty list.
 * These cover the most common intake checks for a general repair shop.
 */
private val DEFAULT_CONDITION_CHECKS: List<ConditionCheckItem> = listOf(
    ConditionCheckItem(id = -1, label = "Powers on", sortOrder = 0),
    ConditionCheckItem(id = -2, label = "Screen intact", sortOrder = 1),
    ConditionCheckItem(id = -3, label = "No cracks / chips", sortOrder = 2),
    ConditionCheckItem(id = -4, label = "Battery present", sortOrder = 3),
    ConditionCheckItem(id = -5, label = "All ports present", sortOrder = 4),
    ConditionCheckItem(id = -6, label = "No water damage visible", sortOrder = 5),
    ConditionCheckItem(id = -7, label = "Customer data backed up", sortOrder = 6),
)
