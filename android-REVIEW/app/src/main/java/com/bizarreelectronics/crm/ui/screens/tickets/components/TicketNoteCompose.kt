@file:OptIn(ExperimentalMaterial3Api::class)

package com.bizarreelectronics.crm.ui.screens.tickets.components

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.bizarreelectronics.crm.data.remote.dto.EmployeeListItem
import com.bizarreelectronics.crm.util.MentionPickerDropdown
import com.bizarreelectronics.crm.util.MentionUtil

/** Extended note type — adds SMS / Email to the existing Internal / Customer / Diagnostic set. */
enum class ExtNoteType(val label: String, val apiValue: String) {
    Internal("Internal", "internal"),
    Customer("Customer", "customer"),
    Diagnostic("Diagnostic", "diagnostic"),
    Sms("SMS", "sms"),
    Email("Email", "email"),
}

/**
 * Full-featured compose box for ticket notes (L730-L735).
 *
 * Features:
 *  - Segmented-style type picker (Internal / Customer / Diagnostic / SMS / Email)
 *  - Flag toggle Switch
 *  - Multiline OutlinedTextField with @ mention detection
 *  - MentionPickerDropdown overlay
 *  - "Add image" PhotoPicker → inline Coil preview thumbnails
 *
 * @param employees     staff list for mention suggestions (from SettingsApi).
 * @param isSubmitting  disable the send button while a network call is in-flight.
 * @param onSubmit      called with (text, type, isFlagged, attachmentUris).
 */
@Composable
fun TicketNoteCompose(
    employees: List<EmployeeListItem>,
    isSubmitting: Boolean,
    modifier: Modifier = Modifier,
    onSubmit: (text: String, type: ExtNoteType, isFlagged: Boolean, attachments: List<Uri>) -> Unit,
) {
    var fieldValue by remember { mutableStateOf(TextFieldValue("")) }
    var selectedType by rememberSaveable { mutableStateOf(ExtNoteType.Internal) }
    var isFlagged by rememberSaveable { mutableStateOf(false) }
    var attachments by remember { mutableStateOf(emptyList<Uri>()) }
    var mentionSuggestions by remember { mutableStateOf(emptyList<EmployeeListItem>()) }

    // @-mention detection: filter employees by query
    val mentionQuery = MentionUtil.mentionQueryAtCursor(fieldValue)
    val mentionExpanded = mentionQuery != null && employees.isNotEmpty()

    LaunchedEffect(mentionQuery) {
        mentionSuggestions = if (mentionQuery != null) {
            employees.filter { emp ->
                val name = listOfNotNull(emp.firstName, emp.lastName, emp.username)
                    .joinToString(" ")
                    .lowercase()
                name.contains(mentionQuery.lowercase())
            }.take(6)
        } else {
            emptyList()
        }
    }

    // Photo picker (Android Photo Picker API)
    val photoPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.PickMultipleVisualMedia(5),
    ) { uris -> attachments = (attachments + uris).distinct() }

    BrandCard(modifier = modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {

            // --- Type selector (scrollable row of filter chips) ---
            LazyRow(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                contentPadding = PaddingValues(horizontal = 2.dp),
            ) {
                items(ExtNoteType.entries) { noteType ->
                    FilterChip(
                        selected = selectedType == noteType,
                        onClick = { selectedType = noteType },
                        label = { Text(noteType.label, style = MaterialTheme.typography.labelSmall) },
                    )
                }
            }

            // --- Flag toggle ---
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(
                    Icons.Default.Flag,
                    contentDescription = null,
                    modifier = Modifier.size(16.dp),
                    tint = if (isFlagged) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    "Flag note",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f),
                )
                Switch(
                    checked = isFlagged,
                    onCheckedChange = { isFlagged = it },
                    modifier = Modifier.height(24.dp),
                )
            }

            // --- Text field with mention dropdown ---
            Box {
                OutlinedTextField(
                    value = fieldValue,
                    onValueChange = { fieldValue = it },
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("Add a note… use @ to mention someone") },
                    minLines = 3,
                    maxLines = 8,
                    textStyle = MaterialTheme.typography.bodySmall,
                )
                MentionPickerDropdown(
                    expanded = mentionExpanded,
                    suggestions = mentionSuggestions,
                    onSelect = { emp ->
                        fieldValue = MentionUtil.insertMention(fieldValue, emp)
                        mentionSuggestions = emptyList()
                    },
                    onDismiss = { mentionSuggestions = emptyList() },
                )
            }

            // --- Attachment previews ---
            if (attachments.isNotEmpty()) {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    items(attachments) { uri ->
                        Box {
                            AsyncImage(
                                model = uri,
                                contentDescription = "Attachment preview",
                                contentScale = ContentScale.Crop,
                                modifier = Modifier
                                    .size(64.dp)
                                    .clip(RoundedCornerShape(8.dp)),
                            )
                            IconButton(
                                onClick = { attachments = attachments - uri },
                                modifier = Modifier
                                    .size(18.dp)
                                    .align(Alignment.TopEnd),
                            ) {
                                Icon(
                                    Icons.Default.Close,
                                    contentDescription = "Remove attachment",
                                    modifier = Modifier.size(12.dp),
                                    tint = Color.White,
                                )
                            }
                        }
                    }
                }
            }

            // --- Action row: add image + send ---
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(
                    onClick = {
                        photoPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                    },
                ) {
                    Icon(
                        Icons.Default.AttachFile,
                        contentDescription = "Add image",
                        tint = MaterialTheme.colorScheme.primary,
                    )
                }
                IconButton(
                    onClick = {
                        val text = fieldValue.text.trim()
                        if (text.isNotBlank()) {
                            onSubmit(text, selectedType, isFlagged, attachments)
                            fieldValue = TextFieldValue("")
                            attachments = emptyList()
                            isFlagged = false
                        }
                    },
                    enabled = fieldValue.text.isNotBlank() && !isSubmitting,
                ) {
                    Icon(
                        Icons.Default.Send,
                        contentDescription = "Send note",
                        tint = if (fieldValue.text.isNotBlank() && !isSubmitting)
                            MaterialTheme.colorScheme.primary
                        else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f),
                    )
                }
            }
        }
    }
}

// Re-export BrandCard alias so this file is self-contained without pulling in
// a non-existent local import — TicketNotesTab already imports it.
@Composable
private fun BrandCard(
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    com.bizarreelectronics.crm.ui.components.shared.BrandCard(modifier = modifier, content = content)
}
