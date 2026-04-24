@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.bizarreelectronics.crm.ui.screens.tickets.components

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
import androidx.compose.material.icons.filled.Send
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.dto.TicketNote
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.theme.ErrorRed
import com.bizarreelectronics.crm.util.DateFormatter

/** Note visibility type presented in the type selector. */
enum class NoteType(val label: String, val apiValue: String) {
    Internal("Internal", "internal"),
    CustomerVisible("Customer-visible", "customer"),
    Diagnostic("Diagnostic", "diagnostic"),
}

private fun stripHtml(html: String?): String =
    html?.replace(Regex("<[^>]*>"), "")?.trim() ?: ""

/**
 * Notes tab body: scrollable list of notes with type chips + inline compose box.
 *
 * The compose box is anchored at the bottom of the lazy list so it scrolls with
 * content (avoids it being hidden behind the keyboard on small screens — [imePadding]
 * is already applied at the Scaffold level).
 *
 * @param notes        note list from VM state.
 * @param isSubmitting when true, the send button shows a disabled state.
 * @param onSubmit     callback invoked with (text, noteType) when the user taps Send.
 */
@Composable
fun TicketNotesTab(
    notes: List<TicketNote>,
    isSubmitting: Boolean,
    modifier: Modifier = Modifier,
    onSubmit: (text: String, type: NoteType) -> Unit,
) {
    var noteText by rememberSaveable { mutableStateOf("") }
    var selectedType by rememberSaveable { mutableStateOf(NoteType.Internal) }

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

        NoteComposeBox(
            text = noteText,
            onTextChange = { noteText = it },
            selectedType = selectedType,
            onTypeChange = { selectedType = it },
            isSubmitting = isSubmitting,
            onSubmit = {
                if (noteText.isNotBlank()) {
                    onSubmit(noteText.trim(), selectedType)
                    noteText = ""
                }
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
            Text(stripHtml(note.msgText), style = MaterialTheme.typography.bodySmall)
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

@Composable
private fun NoteComposeBox(
    text: String,
    onTextChange: (String) -> Unit,
    selectedType: NoteType,
    onTypeChange: (NoteType) -> Unit,
    isSubmitting: Boolean,
    onSubmit: () -> Unit,
) {
    var typeMenuExpanded by rememberSaveable { mutableStateOf(false) }

    BrandCard(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(8.dp)) {
            ExposedDropdownMenuBox(
                expanded = typeMenuExpanded,
                onExpandedChange = { typeMenuExpanded = it },
            ) {
                OutlinedTextField(
                    value = selectedType.label,
                    onValueChange = {},
                    readOnly = true,
                    label = { Text("Type") },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(typeMenuExpanded) },
                    modifier = Modifier
                        .menuAnchor(MenuAnchorType.PrimaryNotEditable)
                        .fillMaxWidth(),
                    textStyle = MaterialTheme.typography.bodySmall,
                    colors = ExposedDropdownMenuDefaults.outlinedTextFieldColors(),
                )
                ExposedDropdownMenu(
                    expanded = typeMenuExpanded,
                    onDismissRequest = { typeMenuExpanded = false },
                ) {
                    NoteType.entries.forEach { noteType ->
                        DropdownMenuItem(
                            text = { Text(noteType.label) },
                            onClick = {
                                onTypeChange(noteType)
                                typeMenuExpanded = false
                            },
                        )
                    }
                }
            }
            Spacer(modifier = Modifier.height(4.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.Bottom,
            ) {
                OutlinedTextField(
                    value = text,
                    onValueChange = onTextChange,
                    modifier = Modifier.weight(1f),
                    placeholder = { Text("Add a note…") },
                    minLines = 2,
                    maxLines = 5,
                )
                IconButton(
                    onClick = onSubmit,
                    enabled = text.isNotBlank() && !isSubmitting,
                ) {
                    Icon(
                        Icons.Default.Send,
                        contentDescription = "Send note",
                        tint = if (text.isNotBlank() && !isSubmitting)
                            MaterialTheme.colorScheme.primary
                        else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f),
                    )
                }
            }
        }
    }
}
