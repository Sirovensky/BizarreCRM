package com.bizarreelectronics.crm.ui.screens.checkin

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Card
import androidx.compose.material3.Checkbox
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.components.SignaturePad
import com.bizarreelectronics.crm.ui.components.SignatureStroke
import com.bizarreelectronics.crm.ui.components.isSignatureValid
import com.bizarreelectronics.crm.ui.components.renderSignatureBitmap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import android.util.Base64

// TODO(Phase 4): Replace this stub with real SignatureRouter.capture() once
// BlockChyp SDK + SignatureRouter.kt are wired (see plan Phase 4).
// The stub returns a fake base64 PNG so Step 6 compiles and functions on-phone
// before terminal routing is available.
private suspend fun captureSignatureViaRouter(strokes: List<SignatureStroke>): String {
    return withContext(Dispatchers.Default) {
        val bmp = renderSignatureBitmap(strokes, 800, 400)
        val out = ByteArrayOutputStream()
        bmp.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, out)
        val bytes = out.toByteArray()
        "data:image/png;base64," + Base64.encodeToString(bytes, Base64.NO_WRAP)
    }
}

@Composable
fun CheckInStep6Sign(
    agreedToTerms: Boolean,
    consentBackup: Boolean,
    authorizedDeposit: Boolean,
    optInSms: Boolean,
    depositCents: Long,
    signatureBase64: String?,
    onAgreedChange: (Boolean) -> Unit,
    onConsentChange: (Boolean) -> Unit,
    onAuthorizeChange: (Boolean) -> Unit,
    onOptInChange: (Boolean) -> Unit,
    onSigned: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    var termsExpanded by remember { mutableStateOf(false) }
    var strokes by remember { mutableStateOf<List<SignatureStroke>>(emptyList()) }
    val scope = rememberCoroutineScope()

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item(key = "terms_block") {
            TermsBlock(
                expanded = termsExpanded,
                onToggle = { termsExpanded = !termsExpanded },
            )
        }

        item(key = "checkboxes") {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                AcknowledgementRow(
                    label = "I agree to the estimate and service terms",
                    checked = agreedToTerms,
                    onCheckedChange = onAgreedChange,
                    required = true,
                )
                AcknowledgementRow(
                    label = "I confirm I have backed up my own data",
                    checked = consentBackup,
                    onCheckedChange = onConsentChange,
                    required = true,
                )
                if (depositCents > 0L) {
                    AcknowledgementRow(
                        label = "I authorize the deposit charge",
                        checked = authorizedDeposit,
                        onCheckedChange = onAuthorizeChange,
                        required = true,
                    )
                }
                AcknowledgementRow(
                    label = "Send me repair-status SMS updates (optional)",
                    checked = optInSms,
                    onCheckedChange = onOptInChange,
                    required = false,
                )
            }
        }

        item(key = "signature_section") {
            HorizontalDivider()
            Column(
                modifier = Modifier.padding(top = 8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text("Customer signature", style = MaterialTheme.typography.titleSmall)
                if (signatureBase64 != null) {
                    Text(
                        "Signature captured ✓",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.primary,
                    )
                    TextButton(
                        onClick = {
                            strokes = emptyList()
                            onSigned("")
                        },
                        modifier = Modifier.semantics { contentDescription = "Clear signature and re-sign" },
                    ) {
                        Text("Re-sign")
                    }
                } else {
                    SignaturePad(
                        strokes = strokes,
                        onStrokesChanged = { updated ->
                            strokes = updated
                            if (isSignatureValid(updated)) {
                                scope.launch {
                                    val base64 = captureSignatureViaRouter(updated)
                                    onSigned(base64)
                                }
                            }
                        },
                        modifier = Modifier.fillMaxWidth(),
                        placeholder = "Customer signs here",
                    )
                }
            }
        }
    }
}

@Composable
private fun TermsBlock(expanded: Boolean, onToggle: () -> Unit) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Service terms", style = MaterialTheme.typography.titleSmall)
                TextButton(
                    onClick = onToggle,
                    modifier = Modifier.semantics {
                        contentDescription = if (expanded) "Collapse service terms" else "Expand service terms"
                    },
                ) {
                    Text(if (expanded) "Collapse" else "Read full terms")
                }
            }
            AnimatedVisibility(visible = expanded) {
                Text(
                    TERMS_SUMMARY,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (!expanded) {
                Text(
                    "Bizarre Electronics will perform the agreed repair. We are not responsible for data loss. All parts carry a 90-day warranty unless otherwise stated…",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                )
            }
        }
    }
}

@Composable
private fun AcknowledgementRow(
    label: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    required: Boolean,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .semantics {
                contentDescription = "$label${if (required) " (required)" else " (optional)"}. ${if (checked) "Checked" else "Unchecked"}"
                role = Role.Checkbox
            },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Checkbox(
            checked = checked,
            onCheckedChange = onCheckedChange,
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(label, style = MaterialTheme.typography.bodyMedium)
            if (required) {
                Text(
                    "Required",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }
        }
    }
}

private const val TERMS_SUMMARY = """
BIZARRE ELECTRONICS SERVICE TERMS

1. Estimates: All quoted prices are estimates. Final cost may differ if additional issues are discovered during repair.
2. Liability: Bizarre Electronics is not responsible for data loss. Customers are advised to back up all data before service.
3. Parts warranty: All parts carry a 90-day warranty against defects, excluding physical damage or liquid damage occurring after repair.
4. Unclaimed devices: Devices not claimed within 30 days of completion notice may be subject to storage fees.
5. Authorization: By signing, the customer authorizes Bizarre Electronics to perform the described repair at the quoted price range.
6. Privacy: Device passcodes are encrypted and auto-deleted upon ticket close. They are used solely for testing purposes.
"""
