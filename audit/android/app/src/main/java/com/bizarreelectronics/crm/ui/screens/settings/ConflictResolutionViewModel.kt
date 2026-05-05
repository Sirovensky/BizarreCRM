package com.bizarreelectronics.crm.ui.screens.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.ConflictResolutionRequest
import com.bizarreelectronics.crm.data.remote.api.SyncApi
import com.bizarreelectronics.crm.data.sync.ConflictRecord
import com.bizarreelectronics.crm.data.sync.ConflictResolver
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import java.io.IOException
import javax.inject.Inject

// ─── UI model ─────────────────────────────────────────────────────────────────

/** Per-field user choice. */
enum class FieldChoice { MINE, THEIRS, MERGE }

/** UI-level representation of one pending conflict. */
data class ConflictUi(
    val conflictId: Long,
    val entityType: String,
    val entityId: Long,
    val fields: List<FieldConflictUi>,
)

data class FieldConflictUi(
    val fieldName: String,
    val clientValue: String,
    val serverValue: String,
    val choice: FieldChoice = FieldChoice.THEIRS,
)

private fun ConflictRecord.toUi(): ConflictUi = ConflictUi(
    conflictId = id,
    entityType = entityType,
    entityId = entityId,
    fields = promptFields.values.map { f ->
        FieldConflictUi(
            fieldName = f.fieldName,
            clientValue = f.clientValue,
            serverValue = f.serverValue,
        )
    },
)

// ─── UiState ──────────────────────────────────────────────────────────────────

sealed class ConflictResolutionUiState {
    /** No pending conflicts — show empty state. */
    data object Empty : ConflictResolutionUiState()

    /** List of pending conflicts ready for user review. */
    data class Content(val conflicts: List<ConflictUi>) : ConflictResolutionUiState()

    /** A submission is in progress. */
    data class Submitting(val conflictId: Long) : ConflictResolutionUiState()

    /** An error occurred during submission. */
    data class Error(val message: String) : ConflictResolutionUiState()
}

// ─── ViewModel ────────────────────────────────────────────────────────────────

/**
 * Plan §20.5 L2118 — ViewModel for [ConflictResolutionScreen].
 *
 * Loads pending conflicts from [ConflictResolver.pendingConflicts] and submits
 * user resolutions to [SyncApi.resolveConflict]. On success, clears the conflict
 * from the resolver's in-memory list.
 */
@HiltViewModel
class ConflictResolutionViewModel @Inject constructor(
    private val conflictResolver: ConflictResolver,
    private val syncApi: SyncApi,
) : ViewModel() {

    private val _uiState = MutableStateFlow<ConflictResolutionUiState>(ConflictResolutionUiState.Empty)
    val uiState: StateFlow<ConflictResolutionUiState> = _uiState.asStateFlow()

    /** Snackbar message after submit. */
    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        val conflicts = conflictResolver.pendingConflicts
        _uiState.value = if (conflicts.isEmpty()) {
            ConflictResolutionUiState.Empty
        } else {
            ConflictResolutionUiState.Content(conflicts.map { it.toUi() })
        }
    }

    /**
     * Submit the user's field-level resolutions for [conflictId].
     *
     * [choices] maps field name → [FieldChoice]. [myValues] maps field name →
     * the client's value (JSON string) for `MINE` choices.
     */
    fun submit(
        conflictId: Long,
        entityType: String,
        entityId: Long,
        choices: Map<String, FieldChoice>,
        myValues: Map<String, String> = emptyMap(),
    ) {
        val resolutions = choices.mapValues { (_, choice) ->
            when (choice) {
                FieldChoice.MINE   -> "mine"
                FieldChoice.THEIRS -> "theirs"
                FieldChoice.MERGE  -> "merge"
            }
        }
        val request = ConflictResolutionRequest(
            conflictId = conflictId,
            entityType = entityType,
            entityId = entityId,
            resolutions = resolutions,
            myValues = myValues,
        )

        _uiState.value = ConflictResolutionUiState.Submitting(conflictId)

        viewModelScope.launch {
            try {
                val response = syncApi.resolveConflict(request)
                if (response.success) {
                    conflictResolver.clearConflict(conflictId)
                    _message.value = "Conflict resolved"
                    refresh()
                } else {
                    _uiState.value = ConflictResolutionUiState.Error(
                        response.message ?: "Server rejected the resolution"
                    )
                }
            } catch (e: HttpException) {
                _uiState.value = ConflictResolutionUiState.Error("Server error (${e.code()})")
            } catch (e: IOException) {
                _uiState.value = ConflictResolutionUiState.Error("Network error — changes not saved")
            } catch (e: Exception) {
                _uiState.value = ConflictResolutionUiState.Error("Unexpected error: ${e.message}")
            }
        }
    }

    fun clearMessage() {
        _message.value = null
    }
}
