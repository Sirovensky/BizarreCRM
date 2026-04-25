package com.bizarreelectronics.crm.ui.screens.reports

import android.content.Intent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.ui.platform.LocalContext
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar

/**
 * Custom report builder screen (ActionPlan §15 L1754-L1757).
 *
 * Scrollable list of saved custom queries with a "New custom query" FAB.
 * Tapping the FAB opens a bottom sheet with a DSL stub text field and a
 * field picker stub.  Full implementation is deferred.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CustomReportScreen() {
    var showNewSheet by rememberSaveable { mutableStateOf(false) }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    val context = LocalContext.current

    // Placeholder saved queries list — will be replaced with VM data when endpoint ships.
    // IDs are sequential stubs; a real implementation will use server-assigned UUIDs.
    val savedQueries = remember {
        listOf(
            SavedQuery(id = 1, name = "Monthly revenue by payment method", dsl = "revenue WHERE period = MONTH"),
            SavedQuery(id = 2, name = "Open tickets older than 7 days", dsl = "tickets WHERE status = OPEN AND age > 7"),
        )
    }

    Scaffold(
        topBar = { BrandTopAppBar(title = "Custom Reports") },
        floatingActionButton = {
            ExtendedFloatingActionButton(
                onClick = { showNewSheet = true },
                icon = { Icon(Icons.Default.Add, contentDescription = null) },
                text = { Text("New custom query") },
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            item {
                Text(
                    "Saved Queries",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.semantics { heading() },
                )
            }
            items(savedQueries, key = { it.id }) { query ->
                SavedQueryRow(
                    query = query,
                    onRun = { /* TODO: run the query and show results */ },
                    onShare = { shareCustomReport(context, query.id, query.name) },
                )
            }
            item {
                Text(
                    "Full custom query builder (SQL-like DSL + field picker) is deferred.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 8.dp),
                )
            }
        }
    }

    if (showNewSheet) {
        NewCustomQuerySheet(
            onDismiss = { showNewSheet = false },
            sheetState = sheetState,
        )
    }
}

// ─── Data model ──────────────────────────────────────────────────────────────

private data class SavedQuery(val id: Long, val name: String, val dsl: String)

// ─── Composables ─────────────────────────────────────────────────────────────

@Composable
private fun SavedQueryRow(query: SavedQuery, onRun: () -> Unit, onShare: () -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(query.name, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
                Text(query.dsl, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            IconButton(onClick = onShare) {
                Icon(Icons.Default.Share, contentDescription = "Share ${query.name}")
            }
            IconButton(onClick = onRun) {
                Icon(Icons.Default.PlayArrow, contentDescription = "Run ${query.name}")
            }
        }
    }
}

// ─── Deep-link sharing ────────────────────────────────────────────────────────

/**
 * Fires an ACTION_SEND intent with a deep-link to the custom report.
 *
 * Link format: `bizarrecrm://reports/custom/<id>`
 * Matches the navDeepLink registered in AppNavGraph for [Screen.ReportCustom].
 */
private fun shareCustomReport(context: android.content.Context, id: Long, name: String) {
    val link = "bizarrecrm://reports/custom/$id"
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_SUBJECT, "Report: $name")
        putExtra(Intent.EXTRA_TEXT, link)
    }
    context.startActivity(Intent.createChooser(intent, "Share report link"))
}

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun NewCustomQuerySheet(
    onDismiss: () -> Unit,
    sheetState: androidx.compose.material3.SheetState,
) {
    var queryText by rememberSaveable { mutableStateOf("") }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(
                "New Custom Query",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
            OutlinedTextField(
                value = queryText,
                onValueChange = { queryText = it },
                label = { Text("Query DSL (stub)") },
                placeholder = { Text("e.g. revenue WHERE period = MONTH") },
                modifier = Modifier.fillMaxWidth(),
                minLines = 3,
            )
            Text(
                "Field picker and full DSL support are deferred. Queries entered here are not yet executed.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Button(
                onClick = onDismiss,
                modifier = Modifier.fillMaxWidth(),
                enabled = false, // disabled until endpoint ships
            ) {
                Text("Save Query (coming soon)")
            }
            Spacer(Modifier.height(8.dp))
        }
    }
}
