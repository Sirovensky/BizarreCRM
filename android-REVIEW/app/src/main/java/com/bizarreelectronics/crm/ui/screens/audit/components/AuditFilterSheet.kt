package com.bizarreelectronics.crm.ui.screens.audit.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

// ─── Filter state ─────────────────────────────────────────────────────────────

data class AuditFilter(
    val actor: String = "",
    val entityType: String = "",
    val action: String = "",
    val from: String = "",
    val to: String = "",
)

private val ENTITY_TYPES = listOf("ticket", "customer", "invoice", "inventory", "user", "settings")
private val ACTIONS = listOf("create", "update", "delete", "login", "logout", "view")

// ─── Bottom sheet ─────────────────────────────────────────────────────────────

/**
 * §52 — Bottom-sheet filter panel for the audit log.
 *
 * Exposes: actor text field, entity-type chip group, action chip group, and
 * from/to date-range text fields (ISO-8601). Apply/Clear buttons.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun AuditFilterSheet(
    current: AuditFilter,
    onApply: (AuditFilter) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    var draft by remember(current) { mutableStateOf(current) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("Filter audit log", style = androidx.compose.material3.MaterialTheme.typography.titleMedium)

            OutlinedTextField(
                value = draft.actor,
                onValueChange = { draft = draft.copy(actor = it) },
                label = { Text("Actor (username)") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )

            Text("Entity type", style = androidx.compose.material3.MaterialTheme.typography.labelMedium)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ENTITY_TYPES.forEach { type ->
                    FilterChip(
                        selected = draft.entityType == type,
                        onClick = {
                            draft = draft.copy(entityType = if (draft.entityType == type) "" else type)
                        },
                        label = { Text(type) },
                    )
                }
            }

            Text("Action", style = androidx.compose.material3.MaterialTheme.typography.labelMedium)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ACTIONS.forEach { action ->
                    FilterChip(
                        selected = draft.action == action,
                        onClick = {
                            draft = draft.copy(action = if (draft.action == action) "" else action)
                        },
                        label = { Text(action) },
                    )
                }
            }

            OutlinedTextField(
                value = draft.from,
                onValueChange = { draft = draft.copy(from = it) },
                label = { Text("From (YYYY-MM-DD)") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = draft.to,
                onValueChange = { draft = draft.copy(to = it) },
                label = { Text("To (YYYY-MM-DD)") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )

            Spacer(Modifier.height(4.dp))

            Button(
                onClick = { onApply(draft) },
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Apply filters") }

            TextButton(
                onClick = { onApply(AuditFilter()) },
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Clear all filters") }
        }
    }
}
