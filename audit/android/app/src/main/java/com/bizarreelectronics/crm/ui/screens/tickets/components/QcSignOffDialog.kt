package com.bizarreelectronics.crm.ui.screens.tickets.components

import android.graphics.Bitmap
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.components.SignatureCanvas
import com.bizarreelectronics.crm.ui.components.rememberSignatureState

/**
 * QcSignOffDialog — §4.7 L741 (plan:L741)
 *
 * [ModalBottomSheet] allowing an authorised technician / manager to sign off QC:
 * 1. Draws a signature on [SignatureCanvas].
 * 2. Optionally adds a comment.
 * 3. Taps "Work complete" → [onConfirm] receives the [Bitmap] + comment.
 *
 * Role-gating (admin / manager / tech) must be enforced by the caller before
 * presenting this sheet. The sheet itself does not perform role checks.
 *
 * Server endpoint: `POST /tickets/:id/qc-sign` (404-tolerant — on 404 the
 * caller should fall back to attaching the signature PNG as a note with an
 * "is_qc_sign_off" flag). See [TicketDetailViewModel.submitQcSignOff].
 *
 * @param reduceMotion When true, the sheet skip-enters without animation (M3
 *                     [ModalBottomSheet] does not yet support custom enter
 *                     transitions, so this is a forward-compat annotation).
 * @param onConfirm    Emitted with the signature [Bitmap] + optional comment.
 * @param onDismiss    Sheet dismissed without submitting.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QcSignOffDialog(
    @Suppress("UNUSED_PARAMETER") reduceMotion: Boolean = false,
    onConfirm: (signature: Bitmap, comments: String) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val signatureState = rememberSignatureState()
    var comments by rememberSaveable { mutableStateOf("") }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(
                "QC Sign-Off",
                style = MaterialTheme.typography.titleLarge,
            )

            Text(
                "Draw your signature below to certify this repair is complete.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            // Signature pad
            SignatureCanvas(
                state = signatureState,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(180.dp),
                reduceMotion = reduceMotion,
            )

            if (signatureState.isEmpty) {
                Text(
                    "Signature is required",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }

            // Optional comment
            OutlinedTextField(
                value = comments,
                onValueChange = { comments = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Comments (optional)") },
                placeholder = { Text("Any QC notes…") },
                minLines = 2,
                maxLines = 4,
            )

            Spacer(modifier = Modifier.height(4.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                // Clear button
                TextButton(
                    onClick = { signatureState.clear() },
                    modifier = Modifier.weight(1f),
                ) {
                    Text("Clear")
                }

                // Cancel
                TextButton(
                    onClick = onDismiss,
                    modifier = Modifier.weight(1f),
                ) {
                    Text("Cancel")
                }

                // Confirm — gated on non-empty signature
                TextButton(
                    onClick = {
                        if (!signatureState.isEmpty) {
                            val bitmap = signatureState.capture()
                            onConfirm(bitmap, comments.trim())
                        }
                    },
                    enabled = !signatureState.isEmpty,
                    modifier = Modifier.weight(1.5f),
                    colors = ButtonDefaults.textButtonColors(
                        contentColor = MaterialTheme.colorScheme.primary,
                    ),
                ) {
                    Text("Work complete")
                }
            }
        }
    }
}
