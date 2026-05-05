package com.bizarreelectronics.crm.ui.screens.customers

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Note
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.data.remote.api.CustomerApi
import com.bizarreelectronics.crm.data.remote.dto.CreateCustomerNoteRequest
import com.bizarreelectronics.crm.data.remote.dto.CustomerNote
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import javax.inject.Inject

// §5.14 — Customer notes screen.
//
// Displays the full note timeline for a customer, supports creating a new
// quick note (one-liner) and deleting owned notes with a ConfirmDialog.
// Rich text, attachments, pins, @mentions, edit history, and role-gating are
// deferred to §5.14 follow-up items blocked on server-side schema additions.
//
// Server: GET /customers/:id/notes, POST /customers/:id/notes,
//         DELETE /customers/:id/notes/:noteId  (CustomerApi — already wired).
//
// Route: Screen.CustomerNotes.route ("customers/{id}/notes")

private const val NOTE_MAX_CHARS = 5_000

data class CustomerNotesUiState(
    val notes: List<CustomerNote> = emptyList(),
    val isLoading: Boolean = false,
    val isSending: Boolean = false,
    val error: String? = null,
    val newNoteText: String = "",
    val deleteTargetNoteId: Long? = null,
)

@HiltViewModel
class CustomerNotesViewModel @Inject constructor(
    private val customerApi: CustomerApi,
    savedStateHandle: SavedStateHandle,
) : ViewModel() {

    val customerId: Long = checkNotNull(savedStateHandle["id"]) { "customerId required" }

    private val _state = MutableStateFlow(CustomerNotesUiState())
    val state = _state.asStateFlow()

    init {
        loadNotes()
    }

    fun loadNotes() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                val resp = customerApi.getNotes(customerId)
                _state.value = _state.value.copy(isLoading = false, notes = resp.data ?: emptyList())
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = e.message ?: "Failed to load notes",
                )
            }
        }
    }

    fun updateNewNoteText(text: String) {
        if (text.length > NOTE_MAX_CHARS) return
        _state.value = _state.value.copy(newNoteText = text)
    }

    fun postNote() {
        val body = _state.value.newNoteText.trim()
        if (body.isBlank()) return
        viewModelScope.launch {
            _state.value = _state.value.copy(isSending = true, error = null)
            try {
                val resp = customerApi.postNote(customerId, CreateCustomerNoteRequest(body))
                val created = resp.data ?: return@launch
                _state.value = _state.value.copy(
                    isSending = false,
                    newNoteText = "",
                    notes = listOf(created) + _state.value.notes,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isSending = false,
                    error = e.message ?: "Failed to save note",
                )
            }
        }
    }

    fun requestDelete(noteId: Long) {
        _state.value = _state.value.copy(deleteTargetNoteId = noteId)
    }

    fun cancelDelete() {
        _state.value = _state.value.copy(deleteTargetNoteId = null)
    }

    fun confirmDelete() {
        val noteId = _state.value.deleteTargetNoteId ?: return
        _state.value = _state.value.copy(deleteTargetNoteId = null)
        viewModelScope.launch {
            try {
                customerApi.deleteNote(customerId, noteId)
                _state.value = _state.value.copy(
                    notes = _state.value.notes.filter { it.id != noteId },
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message ?: "Failed to delete note")
            }
        }
    }

    fun clearError() {
        _state.value = _state.value.copy(error = null)
    }
}

// ── Timestamp formatter ─────────────────────────────────────────────────────

private val ISO_IN = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
    timeZone = TimeZone.getTimeZone("UTC")
}
private val ISO_IN_SHORT = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
    timeZone = TimeZone.getTimeZone("UTC")
}
private val DISPLAY_OUT = SimpleDateFormat("MMM d, yyyy · h:mm a", Locale.getDefault())

private fun formatTimestamp(iso: String?): String {
    if (iso.isNullOrBlank()) return ""
    return try {
        val date = try { ISO_IN.parse(iso) } catch (_: Exception) { ISO_IN_SHORT.parse(iso) }
        DISPLAY_OUT.format(date ?: return iso)
    } catch (_: Exception) {
        iso
    }
}

// ── Screen ──────────────────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CustomerNotesScreen(
    onBack: () -> Unit,
    viewModel: CustomerNotesViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(state.error) {
        val err = state.error ?: return@LaunchedEffect
        snackbarHostState.showSnackbar(err)
        viewModel.clearError()
    }

    // ── Delete confirmation dialog ─────────────────────────────────────────
    if (state.deleteTargetNoteId != null) {
        AlertDialog(
            onDismissRequest = viewModel::cancelDelete,
            title = { Text(stringResource(R.string.customer_note_delete_title)) },
            text = { Text(stringResource(R.string.customer_note_delete_message)) },
            confirmButton = {
                FilledTonalButton(
                    onClick = viewModel::confirmDelete,
                    colors = ButtonDefaults.filledTonalButtonColors(
                        containerColor = MaterialTheme.colorScheme.errorContainer,
                        contentColor = MaterialTheme.colorScheme.onErrorContainer,
                    ),
                ) {
                    Text(stringResource(R.string.action_delete))
                }
            },
            dismissButton = {
                TextButton(onClick = viewModel::cancelDelete) {
                    Text(stringResource(R.string.action_cancel))
                }
            },
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            BrandTopAppBar(
                title = stringResource(R.string.screen_customer_notes),
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.cd_navigate_back),
                        )
                    }
                },
            )
        },
        bottomBar = {
            // ── Compose new note ─────────────────────────────────────────
            Surface(
                tonalElevation = 2.dp,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp, vertical = 8.dp)
                        .imePadding(),
                    verticalAlignment = Alignment.Bottom,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    OutlinedTextField(
                        value = state.newNoteText,
                        onValueChange = viewModel::updateNewNoteText,
                        modifier = Modifier.weight(1f),
                        placeholder = { Text(stringResource(R.string.customer_note_compose_hint)) },
                        minLines = 1,
                        maxLines = 4,
                        enabled = !state.isSending,
                        supportingText = if (state.newNoteText.length > NOTE_MAX_CHARS - 100) {
                            { Text("${state.newNoteText.length}/$NOTE_MAX_CHARS") }
                        } else null,
                    )
                    FilledTonalIconButton(
                        onClick = viewModel::postNote,
                        enabled = state.newNoteText.isNotBlank() && !state.isSending,
                        modifier = Modifier.semantics {
                            contentDescription = "Post note"
                        },
                    ) {
                        if (state.isSending) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(18.dp),
                                strokeWidth = 2.dp,
                            )
                        } else {
                            Icon(
                                Icons.AutoMirrored.Filled.Send,
                                contentDescription = stringResource(R.string.customer_note_send_cd),
                            )
                        }
                    }
                }
            }
        },
    ) { padding ->
        when {
            state.isLoading -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            }

            state.notes.isEmpty() -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(
                            Icons.Default.Note,
                            contentDescription = null,
                            modifier = Modifier.size(48.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            stringResource(R.string.customer_notes_empty),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            else -> {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentPadding = PaddingValues(vertical = 8.dp),
                ) {
                    itemsIndexed(state.notes, key = { _, note -> note.id }) { _, note ->
                        NoteCard(
                            note = note,
                            onDelete = { viewModel.requestDelete(note.id) },
                        )
                    }
                }
            }
        }
    }
}

// ── Note card ──────────────────────────────────────────────────────────────

@Composable
private fun NoteCard(
    note: CustomerNote,
    onDelete: () -> Unit,
) {
    OutlinedCard(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 6.dp),
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    val author = note.authorUsername?.ifBlank { null }
                    if (author != null) {
                        Text(
                            author,
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                    Text(
                        formatTimestamp(note.createdAt),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                IconButton(
                    onClick = onDelete,
                    modifier = Modifier.semantics {
                        contentDescription = "Delete note"
                    },
                ) {
                    Icon(
                        Icons.Default.Delete,
                        contentDescription = stringResource(R.string.customer_note_delete_cd),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Text(
                note.body,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}
