package com.bizarreelectronics.crm.ui.screens.tickets.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * §4.1 L640 — Column / density picker for the ticket list (tablet / ChromeOS).
 *
 * Controls which optional columns are visible on the ticket list rows.
 * The picker is a [ModalBottomSheet]; call-sites gate it on
 * `isMediumOrExpandedWidth()`.
 *
 * ### Columns
 * - [showAssignee]         — assigned tech avatar + name
 * - [showInternalNote]     — first line of most-recent internal note
 * - [showDiagnosticNote]   — first line of diagnostic note
 * - [showDevice]           — device make / model string
 * - [showUrgencyDot]       — urgency colour dot
 *
 * ### Persistence
 * The caller converts [TicketColumnVisibility] to / from a JSON string (or five
 * SharedPreferences booleans) and stores them via [AppPreferences]. This
 * component is pure-UI and stateless beyond its own sheet visibility.
 */

// ─── Model ────────────────────────────────────────────────────────────────────

/**
 * Which optional ticket-row columns are visible.
 *
 * Defaults: [showAssignee] and [showDevice] on; the rest off (matches phone behaviour).
 */
data class TicketColumnVisibility(
    val showAssignee: Boolean = true,
    val showInternalNote: Boolean = false,
    val showDiagnosticNote: Boolean = false,
    val showDevice: Boolean = true,
    val showUrgencyDot: Boolean = true,
) {
    companion object {
        /** Saver for [rememberSaveable] — persists all five booleans. */
        val Saver: Saver<TicketColumnVisibility, List<Boolean>> = Saver(
            save = {
                listOf(
                    it.showAssignee,
                    it.showInternalNote,
                    it.showDiagnosticNote,
                    it.showDevice,
                    it.showUrgencyDot,
                )
            },
            restore = { list ->
                TicketColumnVisibility(
                    showAssignee      = list.getOrElse(0) { true },
                    showInternalNote  = list.getOrElse(1) { false },
                    showDiagnosticNote = list.getOrElse(2) { false },
                    showDevice        = list.getOrElse(3) { true },
                    showUrgencyDot    = list.getOrElse(4) { true },
                )
            },
        )

        /** Encode to a compact string for [AppPreferences] storage. */
        fun TicketColumnVisibility.encode(): String =
            "${showAssignee}|${showInternalNote}|${showDiagnosticNote}|${showDevice}|${showUrgencyDot}"

        /** Decode from a compact string stored by [encode]. Returns defaults on parse error. */
        fun decode(raw: String): TicketColumnVisibility {
            val parts = raw.split("|")
            return TicketColumnVisibility(
                showAssignee       = parts.getOrNull(0)?.toBooleanStrictOrNull() ?: true,
                showInternalNote   = parts.getOrNull(1)?.toBooleanStrictOrNull() ?: false,
                showDiagnosticNote = parts.getOrNull(2)?.toBooleanStrictOrNull() ?: false,
                showDevice         = parts.getOrNull(3)?.toBooleanStrictOrNull() ?: true,
                showUrgencyDot     = parts.getOrNull(4)?.toBooleanStrictOrNull() ?: true,
            )
        }
    }
}

// ─── Sheet ────────────────────────────────────────────────────────────────────

/**
 * Bottom-sheet column / density picker.
 *
 * @param current       Currently active column visibility config.
 * @param onApply       Callback with updated config when the user taps Apply.
 * @param onDismiss     Called when the sheet is dismissed without applying.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TicketColumnDensityPicker(
    current: TicketColumnVisibility,
    onApply: (TicketColumnVisibility) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    // Local draft — mutations don't commit until Apply is tapped
    var draft by rememberSaveable(current, stateSaver = TicketColumnVisibility.Saver) {
        mutableStateOf(current)
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .padding(bottom = 32.dp),
        ) {
            Text(
                text = "Columns",
                style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.padding(bottom = 4.dp),
            )
            Text(
                text = "Choose which columns appear on ticket rows.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(bottom = 12.dp),
            )

            ColumnToggleRow(
                label = "Assignee",
                checked = draft.showAssignee,
                onCheckedChange = { draft = draft.copy(showAssignee = it) },
            )
            ColumnToggleRow(
                label = "Internal note (first line)",
                checked = draft.showInternalNote,
                onCheckedChange = { draft = draft.copy(showInternalNote = it) },
            )
            ColumnToggleRow(
                label = "Diagnostic note (first line)",
                checked = draft.showDiagnosticNote,
                onCheckedChange = { draft = draft.copy(showDiagnosticNote = it) },
            )
            ColumnToggleRow(
                label = "Device",
                checked = draft.showDevice,
                onCheckedChange = { draft = draft.copy(showDevice = it) },
            )
            ColumnToggleRow(
                label = "Urgency dot",
                checked = draft.showUrgencyDot,
                onCheckedChange = { draft = draft.copy(showUrgencyDot = it) },
            )

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 16.dp),
                horizontalArrangement = Arrangement.End,
            ) {
                TextButton(onClick = onDismiss) { Text("Cancel") }
                TextButton(onClick = { onApply(draft) }) { Text("Apply") }
            }
        }
    }
}

// ─── Row ─────────────────────────────────────────────────────────────────────

@Composable
private fun ColumnToggleRow(
    label: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.weight(1f),
        )
        Checkbox(
            checked = checked,
            onCheckedChange = onCheckedChange,
        )
    }
}
