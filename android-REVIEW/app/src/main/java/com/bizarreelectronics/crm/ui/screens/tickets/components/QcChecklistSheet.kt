package com.bizarreelectronics.crm.ui.screens.tickets.components

import android.graphics.Bitmap
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddAPhoto
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.components.SignatureCanvas
import com.bizarreelectronics.crm.ui.components.rememberSignatureState

// ─── Model ───────────────────────────────────────────────────────────────────

/** A single checklist item returned by GET /qc-checklists?service_id=. */
data class QcChecklistItem(
    val id: Long,
    val label: String,
    val required: Boolean = true,
)

/** Result value for a single checklist item. */
enum class QcItemResult { Pass, Fail, NA }

/** State holder for the checklist sheet. */
data class QcItemState(
    val item: QcChecklistItem,
    val result: QcItemResult? = null,
    val photoUri: Uri? = null,
    val failReason: String = "",
)

/** Submitted sign-off payload. */
data class QcSignOffPayload(
    val itemResults: List<QcItemState>,
    val signature: Bitmap,
    val timestamp: Long,
    val secondTechSignature: Bitmap? = null,
)

// ─── Sheet ───────────────────────────────────────────────────────────────────

/**
 * §4.18 L838-L846 — QC checklist ModalBottomSheet.
 *
 * Blocks mark-as-Ready until every required item has a result.
 * Any "Fail" result returns the ticket to "In Repair" and requires a reason.
 *
 * ### Flow
 * 1. Renders each [QcChecklistItem] with Pass / Fail / N/A radio buttons.
 * 2. Fail → mandatory [failReason] field opens inline.
 * 3. Optional photo per item via gallery picker.
 * 4. Bottom: [SignatureCanvas] for primary tech sign-off + timestamp.
 * 5. When [requireSecondSignoff] is true, a second tech signature canvas is shown
 *    (tenant flag `require_second_signoff` for high-value repairs).
 * 6. "Complete QC" → [onComplete] with full [QcSignOffPayload].
 *
 * ### Server endpoints (404-tolerant)
 * - GET /qc-checklists?service_id= → list of [QcChecklistItem]
 * - POST /tickets/:id/qc-checklist → submit results (called by caller's VM)
 *
 * ### Audit
 * The server appends a timeline event to the ticket on successful submission.
 * Customer-visible: QC result is included on the invoice/receipt via the printed
 * template.
 *
 * @param items                 Checklist items from the server.
 * @param requireSecondSignoff  Tenant flag; when true a second tech signature is required.
 * @param reduceMotion          When true, the sheet enters without animation.
 * @param onComplete            Callback with the full sign-off payload.
 * @param onDismiss             Sheet dismissed without submitting.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QcChecklistSheet(
    items: List<QcChecklistItem>,
    requireSecondSignoff: Boolean = false,
    reduceMotion: Boolean = false,
    onComplete: (QcSignOffPayload) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    // Item states — immutable list updated via copy
    var itemStates by rememberSaveable {
        mutableStateOf(items.map { QcItemState(item = it) })
    }

    val primarySig = rememberSignatureState()
    val secondSig  = rememberSignatureState()

    // Validation: all required items must have a result
    val allRequired = itemStates.filter { it.item.required }.all { it.result != null }
    // All fails must have a reason
    val failsHaveReasons = itemStates
        .filter { it.result == QcItemResult.Fail }
        .all { it.failReason.isNotBlank() }
    val hasFail = itemStates.any { it.result == QcItemResult.Fail }
    val canSubmit = allRequired && failsHaveReasons && !primarySig.isEmpty &&
        (!requireSecondSignoff || !secondSig.isEmpty)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .padding(bottom = 32.dp),
        ) {
            Text(
                "QC Checklist",
                style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.padding(bottom = 4.dp),
            )

            if (hasFail) {
                Text(
                    "One or more items failed — ticket will return to In Repair.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(bottom = 8.dp),
                )
            }

            // Checklist items
            LazyColumn(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(320.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                items(itemStates, key = { it.item.id }) { state ->
                    QcItemRow(
                        state = state,
                        onResultChange = { newResult ->
                            itemStates = itemStates.map { s ->
                                if (s.item.id == state.item.id) s.copy(result = newResult) else s
                            }
                        },
                        onReasonChange = { reason ->
                            itemStates = itemStates.map { s ->
                                if (s.item.id == state.item.id) s.copy(failReason = reason) else s
                            }
                        },
                        onPhotoSelected = { uri ->
                            itemStates = itemStates.map { s ->
                                if (s.item.id == state.item.id) s.copy(photoUri = uri) else s
                            }
                        },
                    )
                    HorizontalDivider()
                }
            }

            Spacer(Modifier.height(16.dp))

            // Primary tech signature
            Text(
                "Technician Sign-Off",
                style = MaterialTheme.typography.titleSmall,
                modifier = Modifier.padding(bottom = 6.dp),
            )
            SignatureCanvas(
                state = primarySig,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(140.dp),
                reduceMotion = reduceMotion,
            )
            if (primarySig.isEmpty) {
                Text(
                    "Signature required",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }

            // Second tech signature — only when tenant flag is set
            if (requireSecondSignoff) {
                Spacer(Modifier.height(12.dp))
                Text(
                    "Second Technician Verification",
                    style = MaterialTheme.typography.titleSmall,
                    modifier = Modifier.padding(bottom = 6.dp),
                )
                SignatureCanvas(
                    state = secondSig,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(140.dp),
                    reduceMotion = reduceMotion,
                )
                if (secondSig.isEmpty) {
                    Text(
                        "Second signature required",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            }

            Spacer(Modifier.height(16.dp))

            // Actions
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                TextButton(onClick = onDismiss, modifier = Modifier.weight(1f)) {
                    Text("Cancel")
                }
                Button(
                    onClick = {
                        val payload = QcSignOffPayload(
                            itemResults = itemStates,
                            signature = primarySig.capture(),
                            timestamp = System.currentTimeMillis(),
                            secondTechSignature = if (requireSecondSignoff) secondSig.capture() else null,
                        )
                        onComplete(payload)
                    },
                    enabled = canSubmit,
                    modifier = Modifier.weight(2f),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = if (hasFail)
                            MaterialTheme.colorScheme.error
                        else
                            MaterialTheme.colorScheme.primary,
                    ),
                ) {
                    Text(if (hasFail) "Mark Failed — Return to Repair" else "Complete QC")
                }
            }
        }
    }
}

// ─── Item row ─────────────────────────────────────────────────────────────────

@Composable
private fun QcItemRow(
    state: QcItemState,
    onResultChange: (QcItemResult) -> Unit,
    onReasonChange: (String) -> Unit,
    onPhotoSelected: (Uri?) -> Unit,
) {
    val photoPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.GetContent()
    ) { uri: Uri? -> onPhotoSelected(uri) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 6.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(
                text = state.item.label,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.weight(1f),
            )

            // Pass / Fail / NA radio buttons
            QcItemResult.values().forEach { result ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    RadioButton(
                        selected = state.result == result,
                        onClick = { onResultChange(result) },
                    )
                    Text(
                        text = result.name,
                        style = MaterialTheme.typography.labelSmall,
                    )
                }
            }

            // Photo picker
            IconButton(onClick = { photoPicker.launch("image/*") }) {
                Icon(
                    Icons.Default.AddAPhoto,
                    contentDescription = "Attach photo",
                    tint = if (state.photoUri != null)
                        MaterialTheme.colorScheme.primary
                    else
                        MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        // Fail reason input
        if (state.result == QcItemResult.Fail) {
            OutlinedTextField(
                value = state.failReason,
                onValueChange = onReasonChange,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 4.dp),
                label = { Text("Reason for failure (required)") },
                singleLine = true,
                isError = state.failReason.isBlank(),
            )
        }
    }
}
