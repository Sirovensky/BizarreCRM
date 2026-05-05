package com.bizarreelectronics.crm.ui.screens.tickets.components

import android.graphics.Bitmap
import android.util.Base64
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SheetState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.dto.SignatureAuditDto
import com.bizarreelectronics.crm.data.remote.dto.SubmitSignatureRequest
import com.bizarreelectronics.crm.data.remote.dto.WaiverTemplateDto
import com.bizarreelectronics.crm.ui.components.SignatureCanvas
import com.bizarreelectronics.crm.ui.components.rememberSignatureState
import com.bizarreelectronics.crm.util.DeviceFingerprint
import com.bizarreelectronics.crm.util.MarkdownLiteParser
import java.io.ByteArrayOutputStream
import java.time.Instant

/**
 * WaiverSheet — §4.14 L780-L786 (plan:L780-L786)
 *
 * Full-height [ModalBottomSheet] that renders a single waiver template and
 * captures the customer's signature.
 *
 * ## Submit gate
 *
 * The "Sign" button stays disabled until all three conditions hold:
 *  1. The "I've read and agree" checkbox is checked.
 *  2. The [SignatureCanvas] has at least one stroke (not empty).
 *  3. The printed name field is non-blank.
 *
 * ## Audit
 *
 * On submit, a [SignatureAuditDto] is assembled from:
 *  - current [Instant.now] as ISO-8601 timestamp;
 *  - [DeviceFingerprint.get] for device fingerprint (wraps [DeviceBinding.fingerprint]);
 *  - [actorUserId] passed in by the caller from the active session.
 *
 * The signature bitmap is converted to base64 PNG and included in the
 * [SubmitSignatureRequest]. It is ALSO returned via [onSubmit] so the caller
 * can enqueue a multipart upload via [MultipartUploadWorker] for servers that
 * prefer the binary form. **Never log the base64 bytes.**
 *
 * @param template      Waiver template to display (title + markdown body + type).
 * @param actorUserId   ID of the logged-in CRM user collecting the signature.
 * @param sheetState    Optional externally-controlled sheet state.
 * @param onSubmit      Called with the completed [SubmitSignatureRequest] and the
 *                      raw [Bitmap] for multipart upload. Caller dismisses the sheet.
 * @param onDismiss     Called when the user cancels / the sheet is dismissed.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WaiverSheet(
    template: WaiverTemplateDto,
    actorUserId: Long,
    sheetState: SheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    onSubmit: (request: SubmitSignatureRequest, bitmap: Bitmap) -> Unit,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current

    var signerName by rememberSaveable { mutableStateOf("") }
    var agreed by rememberSaveable { mutableStateOf(false) }
    val signatureState = rememberSignatureState()

    // Submit is gated: checkbox + non-empty signature + non-blank name
    val canSubmit = agreed && !signatureState.isEmpty && signerName.isNotBlank()

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 16.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // Header: template title
            Text(
                text = template.title,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(top = 8.dp),
            )

            // Scrollable markdown body rendered by MarkdownLiteParser
            val bodyAnnotated = remember(template.body) {
                MarkdownLiteParser.parse(template.body)
            }
            Text(
                text = bodyAnnotated,
                style = MaterialTheme.typography.bodyMedium,
            )

            Spacer(Modifier.height(4.dp))

            // Signature canvas
            Text(
                text = "Signature",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            SignatureCanvas(
                state = signatureState,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(160.dp),
            )
            TextButton(
                onClick = { signatureState.clear() },
                enabled = !signatureState.isEmpty,
            ) {
                Text("Clear signature")
            }

            // Printed name
            OutlinedTextField(
                value = signerName,
                onValueChange = { signerName = it },
                label = { Text("Printed name") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
            )

            // Agreement checkbox
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Checkbox(
                    checked = agreed,
                    onCheckedChange = { agreed = it },
                )
                Text(
                    text = "I've read and agree to the above terms.",
                    style = MaterialTheme.typography.bodyMedium,
                )
            }

            // Submit button
            Button(
                onClick = {
                    val bitmap = signatureState.capture()
                    // Encode PNG to base64 — never log these bytes
                    val base64 = ByteArrayOutputStream().use { baos ->
                        bitmap.compress(Bitmap.CompressFormat.PNG, 100, baos)
                        Base64.encodeToString(baos.toByteArray(), Base64.NO_WRAP)
                    }
                    val fp = DeviceFingerprint.get(context)
                    val audit = SignatureAuditDto(
                        timestamp = Instant.now().toString(),
                        deviceFingerprint = fp.fingerprint,
                        actorUserId = actorUserId,
                    )
                    val request = SubmitSignatureRequest(
                        templateId = template.id,
                        version = template.version,
                        signerName = signerName.trim(),
                        signatureBase64 = base64,
                        audit = audit,
                    )
                    onSubmit(request, bitmap)
                },
                enabled = canSubmit,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Sign")
            }

            Spacer(Modifier.height(24.dp))
        }
    }
}
