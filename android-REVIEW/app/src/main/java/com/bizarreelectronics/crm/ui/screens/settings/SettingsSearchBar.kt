package com.bizarreelectronics.crm.ui.screens.settings

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.collectLatest

/**
 * L1976 — Settings search bar with 300ms debounce.
 *
 * The composable emits [onResultsChanged] with the filtered [SettingsEntry]
 * list every time the debounced query changes. When the query is blank the
 * callback receives an empty list (no filter applied — the full settings list
 * is shown by the caller rather than duplicated here).
 *
 * @param onResultsChanged  Called with filtered entries on each debounced query change.
 *                          Receives an empty list when the query is blank.
 */
@OptIn(ExperimentalMaterial3Api::class, FlowPreview::class)
@Composable
fun SettingsSearchBar(
    modifier: Modifier = Modifier,
    onResultsChanged: (List<SettingsEntry>) -> Unit,
) {
    var query by remember { mutableStateOf("") }
    val queryFlow = remember { MutableStateFlow("") }

    LaunchedEffect(Unit) {
        queryFlow
            .debounce(300L)
            .collectLatest { q ->
                onResultsChanged(if (q.isBlank()) emptyList() else SettingsMetadata.search(q))
            }
    }

    OutlinedTextField(
        value = query,
        onValueChange = { newValue ->
            query = newValue
            queryFlow.value = newValue
        },
        modifier = modifier
            .fillMaxWidth()
            .semantics { contentDescription = "Search settings" },
        placeholder = { Text("Search settings") },
        leadingIcon = {
            Icon(Icons.Default.Search, contentDescription = null)
        },
        trailingIcon = {
            if (query.isNotEmpty()) {
                IconButton(onClick = {
                    query = ""
                    queryFlow.value = ""
                    onResultsChanged(emptyList())
                }) {
                    Icon(Icons.Default.Close, contentDescription = "Clear search")
                }
            }
        },
        singleLine = true,
        shape = MaterialTheme.shapes.medium,
    )
}

/**
 * L1976 — Renders a list of [SettingsEntry] search results.
 * Each row is a clickable card that calls [onNavigate] with the entry's route.
 */
@Composable
fun SettingsSearchResults(
    results: List<SettingsEntry>,
    onNavigate: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        results.forEach { entry ->
            Card(
                modifier = Modifier.fillMaxWidth(),
                onClick = { onNavigate(entry.route) },
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(entry.title, style = MaterialTheme.typography.bodyMedium)
                    Text(
                        entry.description,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}
