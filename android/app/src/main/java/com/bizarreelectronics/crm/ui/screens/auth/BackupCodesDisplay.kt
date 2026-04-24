package com.bizarreelectronics.crm.ui.screens.auth

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.theme.BrandMono
import com.bizarreelectronics.crm.util.ClipboardUtil

/**
 * §2.4 L301 — Backup codes display shown immediately after a successful 2FA enrollment.
 *
 * Renders the list of one-time recovery codes in a [FlowRow] of monospaced chips.
 * The user must tick the "I have saved these codes" checkbox before the primary CTA
 * becomes enabled — this is a deliberate friction gate, not an oversight.
 *
 * Features:
 *   - FlowRow grid of codes in JetBrains Mono for readability
 *   - "Copy all" button → [ClipboardUtil.copySensitive] with 30s auto-clear
 *   - Warning banner: losing both authenticator and codes causes lockout
 *   - "I have saved these codes" checkbox → gates the primary dismiss CTA
 *   - Primary CTA: "Done — go to dashboard" → calls [onDismiss]
 *
 * @param codes      the list of backup codes returned by the server (typically 10)
 * @param onDismiss  called when the user confirms they have saved the codes;
 *                   the caller is responsible for navigating to the dashboard
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun BackupCodesDisplay(
    codes: List<String>,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    var savedConfirmed by remember { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = { /* Non-dismissible — user must confirm */ },
        containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
        title = {
            Text(
                "Save Your Backup Codes",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold,
            )
        },
        text = {
            Column(modifier = Modifier.verticalScroll(rememberScrollState())) {

                // ── Warning banner ────────────────────────────────────────────
                Surface(
                    color = MaterialTheme.colorScheme.errorContainer,
                    shape = MaterialTheme.shapes.small,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Row(
                        modifier = Modifier.padding(10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(
                            Icons.Default.Warning,
                            contentDescription = null,
                            modifier = Modifier.size(18.dp),
                            tint = MaterialTheme.colorScheme.onErrorContainer,
                        )
                        Text(
                            "If you lose these and your authenticator, you'll be locked out permanently.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onErrorContainer,
                        )
                    }
                }

                Spacer(Modifier.height(12.dp))
                Text(
                    "Each code can be used once. Store them somewhere safe (password manager, printed copy).",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.height(12.dp))

                // ── Codes grid ────────────────────────────────────────────────
                Surface(
                    shape = MaterialTheme.shapes.small,
                    color = MaterialTheme.colorScheme.surfaceVariant,
                    modifier = Modifier
                        .fillMaxWidth()
                        .border(
                            width = 1.dp,
                            color = MaterialTheme.colorScheme.primary.copy(alpha = 0.4f),
                            shape = MaterialTheme.shapes.small,
                        ),
                ) {
                    FlowRow(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(12.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        codes.forEach { code ->
                            Surface(
                                shape = MaterialTheme.shapes.extraSmall,
                                color = MaterialTheme.colorScheme.surface,
                                modifier = Modifier.border(
                                    width = 1.dp,
                                    color = MaterialTheme.colorScheme.outline.copy(alpha = 0.5f),
                                    shape = MaterialTheme.shapes.extraSmall,
                                ),
                            ) {
                                Text(
                                    text = code,
                                    style = MaterialTheme.typography.bodyMedium.copy(
                                        fontFamily = BrandMono.fontFamily,
                                        fontWeight = FontWeight.Medium,
                                    ),
                                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                                )
                            }
                        }
                    }
                }

                Spacer(Modifier.height(10.dp))

                // ── Copy all ──────────────────────────────────────────────────
                OutlinedButton(
                    onClick = {
                        ClipboardUtil.copySensitive(
                            context = context,
                            label = "Backup codes",
                            text = codes.joinToString("\n"),
                            clearAfterMillis = 30_000L,
                        )
                    },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Icon(
                        Icons.Default.ContentCopy,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp),
                    )
                    Spacer(Modifier.width(6.dp))
                    Text("Copy all codes")
                }

                Spacer(Modifier.height(12.dp))

                // ── Confirmation checkbox ─────────────────────────────────────
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Checkbox(
                        checked = savedConfirmed,
                        onCheckedChange = { savedConfirmed = it },
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        "I have saved these codes in a safe place.",
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
        },
        confirmButton = {
            Button(
                onClick = onDismiss,
                enabled = savedConfirmed,
            ) {
                Text("Done — go to dashboard")
            }
        },
    )
}
