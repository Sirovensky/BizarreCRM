@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.bizarreelectronics.crm.ui.screens.tickets.components

import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.dto.EmployeeListItem
import com.bizarreelectronics.crm.data.remote.dto.TicketNote
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.theme.ErrorRed
import com.bizarreelectronics.crm.util.DateFormatter
import com.bizarreelectronics.crm.util.MarkdownLiteParser

/** Note visibility type presented in the type selector. Kept for backwards compat with TicketTabs. */
enum class NoteType(val label: String, val apiValue: String) {
    Internal("Internal", "internal"),
    CustomerVisible("Customer-visible", "customer"),
    Diagnostic("Diagnostic", "diagnostic"),
}

/**
 * Notes tab body: scrollable list of notes (with markdown-lite + @mention rendering)
 * plus the upgraded [TicketNoteCompose] at the bottom.
 *
 * @param notes        note list from VM state.
 * @param employees    staff list for @ mention suggestions.
 * @param isSubmitting disable the send button while a network call is in-flight.
 * @param onSubmit     callback invoked with (text, type, isFlagged, attachments).
 */
@Composable
fun TicketNotesTab(
    notes: List<TicketNote>,
    isSubmitting: Boolean,
    modifier: Modifier = Modifier,
    employees: List<EmployeeListItem> = emptyList(),
    onSubmit: (text: String, type: NoteType, isFlagged: Boolean, attachments: List<Uri>) -> Unit = { _, _, _, _ -> },
) {
    Column(modifier = modifier.fillMaxWidth()) {
        if (notes.isEmpty()) {
            BrandCard(modifier = Modifier.fillMaxWidth()) {
                Text(
                    "No notes yet.",
                    modifier = Modifier.padding(16.dp),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f, fill = false),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(notes, key = { it.id }) { note ->
                    NoteCard(note)
                }
            }
        }

        Spacer(modifier = Modifier.height(12.dp))

        // Upgraded compose box — converts ExtNoteType back to legacy NoteType for callers
        TicketNoteCompose(
            employees = employees,
            isSubmitting = isSubmitting,
            onSubmit = { text, extType, flagged, uris ->
                val legacyType = when (extType) {
                    ExtNoteType.Customer -> NoteType.CustomerVisible
                    ExtNoteType.Diagnostic -> NoteType.Diagnostic
                    else -> NoteType.Internal
                }
                onSubmit(text, legacyType, flagged, uris)
            },
        )
    }
}

@Composable
private fun NoteCard(note: TicketNote) {
    BrandCard(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        note.userName ?: "Staff",
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.SemiBold,
                    )
                    NoteTypeChip(note.type)
                }
                Text(
                    DateFormatter.formatDateTime(note.createdAt),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Spacer(modifier = Modifier.height(4.dp))

            // Render with markdown-lite (bold/italic/code/bullet/links)
            val rawContent = note.msgText?.replace(Regex("<[^>]*>"), "")?.trim() ?: ""
            val linkColor = MaterialTheme.colorScheme.primary
            val annotated = androidx.compose.runtime.remember(rawContent) {
                MarkdownLiteParser.parse(rawContent, linkColor)
            }
            Text(
                text = annotated,
                style = MaterialTheme.typography.bodySmall,
            )

            if (note.isFlagged == true) {
                Spacer(modifier = Modifier.height(4.dp))
                Icon(
                    Icons.Default.Flag,
                    contentDescription = "Flagged note",
                    modifier = Modifier.size(14.dp),
                    tint = ErrorRed,
                )
            }
        }
    }
}

@Composable
private fun NoteTypeChip(type: String?) {
    val (label, color) = when (type?.lowercase()) {
        "customer" -> "Customer-visible" to MaterialTheme.colorScheme.secondary
        "diagnostic" -> "Diagnostic" to MaterialTheme.colorScheme.tertiary
        "sms" -> "SMS" to MaterialTheme.colorScheme.tertiary
        "email" -> "Email" to MaterialTheme.colorScheme.secondary
        else -> "Internal" to MaterialTheme.colorScheme.onSurfaceVariant
    }
    Surface(
        shape = MaterialTheme.shapes.extraSmall,
        color = color.copy(alpha = 0.14f),
    ) {
        Text(
            label,
            modifier = Modifier.padding(horizontal = 4.dp, vertical = 1.dp),
            style = MaterialTheme.typography.labelSmall,
            color = color,
        )
    }
}
