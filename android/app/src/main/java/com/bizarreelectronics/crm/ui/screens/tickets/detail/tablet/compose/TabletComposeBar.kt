package com.bizarreelectronics.crm.ui.screens.tickets.detail.tablet.compose

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/**
 * Tablet compose bar — pinned to the bottom of the right pane.
 *
 * Three message kinds via `SingleChoiceSegmentedButtonRow`:
 *   - **Int.** = internal note (`viewModel.addNote(text, "internal")`)
 *   - **Diag** = diagnostic note (`viewModel.addNote(text, "diagnostic")`)
 *   - **sms**  = customer SMS — for v1 the send button routes to the
 *     SMS thread screen via [onNavigateToSms]; the typed text is
 *     dropped on hand-off (no message-prefill arg yet on the SMS
 *     route). Disabled when no phone is on file.
 *
 * `SingleChoiceSegmentedButtonRow` is the stable analogue of M3
 * Expressive `ButtonGroup`; we deliberately avoid the alpha component
 * after the prior burn at `057417c0` (reverted in `6399cdfa`).
 *
 * @param onAddNote receives `(text, type)` where type ∈ {"internal",
 *   "diagnostic"}. Required.
 * @param onNavigateToSms opens the SMS thread for the customer's
 *   phone — null hides the SMS option entirely.
 * @param customerPhone customer phone for the SMS hand-off; null
 *   disables the sms segment but keeps it visible.
 */
@Composable
internal fun TabletComposeBar(
    onAddNote: (text: String, type: String) -> Unit,
    onNavigateToSms: ((String) -> Unit)?,
    customerPhone: String?,
) {
    var draft by rememberSaveable { mutableStateOf("") }
    var kind by rememberSaveable { mutableStateOf(KIND_INTERNAL) }

    val canSend = remember(draft, kind, customerPhone) {
        draft.isNotBlank() && when (kind) {
            KIND_SMS -> !customerPhone.isNullOrBlank() && onNavigateToSms != null
            else -> true
        }
    }

    Surface(
        color = MaterialTheme.colorScheme.surface,
        shape = RoundedCornerShape(topStart = 18.dp, topEnd = 18.dp),
        modifier = Modifier
            .fillMaxWidth()
            .padding(8.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 10.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            // Kind segmented row.
            SingleChoiceSegmentedButtonRow {
                KIND_OPTIONS.forEachIndexed { idx, opt ->
                    val isSmsAndNoPhone = opt.id == KIND_SMS &&
                        (customerPhone.isNullOrBlank() || onNavigateToSms == null)
                    SegmentedButton(
                        selected = kind == opt.id,
                        onClick = { kind = opt.id },
                        shape = SegmentedButtonDefaults.itemShape(
                            index = idx,
                            count = KIND_OPTIONS.size,
                        ),
                        colors = SegmentedButtonDefaults.colors(
                            activeContainerColor = MaterialTheme.colorScheme.primaryContainer,
                            activeContentColor = MaterialTheme.colorScheme.onPrimaryContainer,
                        ),
                        enabled = !isSmsAndNoPhone,
                        modifier = Modifier.semantics {
                            contentDescription = "Compose ${opt.label} message"
                        },
                    ) {
                        Text(
                            opt.label,
                            style = MaterialTheme.typography.labelMedium,
                            fontWeight = FontWeight.Medium,
                        )
                    }
                }
            }

            // Input field — flex-fills.
            OutlinedTextField(
                value = draft,
                onValueChange = { draft = it.take(2000) },
                modifier = Modifier.weight(1f),
                placeholder = {
                    Text(
                        when (kind) {
                            KIND_INTERNAL -> "Write an internal note…"
                            KIND_DIAGNOSTIC -> "Write a diagnostic note…"
                            KIND_SMS -> "Tap send to open SMS thread for the customer"
                            else -> "Write a message…"
                        },
                        style = MaterialTheme.typography.bodyMedium,
                    )
                },
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = MaterialTheme.colorScheme.primary,
                    focusedLabelColor = MaterialTheme.colorScheme.primary,
                ),
                singleLine = false,
                maxLines = 4,
            )

            // Send FAB — cream filled circle.
            Surface(
                color = if (canSend) MaterialTheme.colorScheme.primary
                else MaterialTheme.colorScheme.surfaceVariant,
                contentColor = if (canSend) MaterialTheme.colorScheme.onPrimary
                else MaterialTheme.colorScheme.onSurfaceVariant,
                shape = CircleShape,
                onClick = onSend@{
                    if (!canSend) return@onSend
                    val text = draft.trim()
                    when (kind) {
                        KIND_INTERNAL -> onAddNote(text, "internal")
                        KIND_DIAGNOSTIC -> onAddNote(text, "diagnostic")
                        KIND_SMS -> customerPhone?.let { onNavigateToSms?.invoke(it) }
                    }
                    draft = ""
                },
                modifier = Modifier
                    .size(44.dp)
                    .semantics {
                        contentDescription = "Send ${KIND_OPTIONS.first { it.id == kind }.label.lowercase()}"
                    },
            ) {
                Box(modifier = Modifier.size(44.dp), contentAlignment = Alignment.Center) {
                    Icon(
                        Icons.AutoMirrored.Filled.Send,
                        contentDescription = null,
                        modifier = Modifier.size(20.dp),
                    )
                }
            }
        }
    }
}

private const val KIND_INTERNAL = "int"
private const val KIND_DIAGNOSTIC = "diag"
private const val KIND_SMS = "sms"

private data class KindOption(val id: String, val label: String)

private val KIND_OPTIONS = listOf(
    KindOption(KIND_INTERNAL, "Int."),
    KindOption(KIND_DIAGNOSTIC, "Diag"),
    KindOption(KIND_SMS, "sms"),
)
