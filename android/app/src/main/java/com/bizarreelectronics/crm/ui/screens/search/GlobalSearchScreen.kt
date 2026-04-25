package com.bizarreelectronics.crm.ui.screens.search

import android.speech.RecognizerIntent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandStatusBadge
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState

// ---------------------------------------------------------------------------
// GlobalSearchScreen
// ---------------------------------------------------------------------------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GlobalSearchScreen(
    /** Called when the user taps a result.
     *  [type] one of: customer | ticket | invoice | inventory | employee | lead | appointment | sms
     *  [id] numeric PK (0 for sms — use [secondaryKey] instead)
     *  [secondaryKey] phone number for sms results, null for all others
     */
    onResult: (type: String, id: Long, secondaryKey: String?) -> Unit,
    viewModel: GlobalSearchViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val focusRequester = remember { FocusRequester() }
    val focusManager = LocalFocusManager.current

    // Voice search launcher — item 6
    val voiceLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartActivityForResult(),
    ) { result ->
        val text = result.data
            ?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
            ?.firstOrNull()
        if (!text.isNullOrBlank()) {
            viewModel.updateQuery(text)
            viewModel.executeSearch()
        }
    }

    LaunchedEffect(Unit) {
        focusRequester.requestFocus()
    }

    // Save-query dialog — item 8
    if (state.showSaveQueryDialog) {
        SaveQueryDialog(
            initialName = state.query.take(40),
            onSave = { name -> viewModel.saveQuery(name) },
            onDismiss = { viewModel.dismissSaveQueryDialog() },
        )
    }

    Scaffold(
        modifier = Modifier.imePadding(),
        topBar = {
            TopAppBar(
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                ),
                title = {
                    InlineSearchField(
                        query = state.query,
                        onQueryChange = viewModel::updateQuery,
                        onSearch = {
                            focusManager.clearFocus()
                            viewModel.executeSearch()
                        },
                        onVoice = {
                            val intent = android.content.Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                                putExtra(RecognizerIntent.EXTRA_PROMPT, "Say something to search…")
                            }
                            runCatching { voiceLauncher.launch(intent) }
                        },
                        focusRequester = focusRequester,
                    )
                },
                actions = {
                    if (state.query.isNotBlank()) {
                        // Pin/save the current query — item 8
                        IconButton(onClick = { viewModel.requestSaveCurrentQuery() }) {
                            Icon(
                                Icons.Default.PushPin,
                                contentDescription = "Save search",
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            // item 11 — offline banner
            if (!state.isOnline) {
                OfflineBanner()
            }

            Box(modifier = Modifier.fillMaxSize()) {
                when {
                    // Idle
                    state.query.isBlank() -> {
                        IdleState(
                            recentSearches = state.recentSearches,
                            savedQueries = state.savedQueries,
                            onRecentTapped = viewModel::onRecentTapped,
                            onClearRecents = viewModel::clearRecentSearches,
                            onSavedQueryTapped = viewModel::onSavedQueryTapped,
                            onRemoveSavedQuery = viewModel::removeSavedQuery,
                        )
                    }

                    // item 10 — shimmer while loading
                    state.isLoading -> {
                        BrandSkeleton(
                            rows = 8,
                            modifier = Modifier.fillMaxSize(),
                        )
                    }

                    state.error != null -> {
                        ErrorState(
                            message = state.error ?: "Search failed",
                            onRetry = { viewModel.executeSearch() },
                        )
                    }

                    // item 9 — no results
                    state.hasSearched && state.results.isEmpty() -> {
                        NoResultsState(query = state.query)
                    }

                    // item 3 — grouped results with count chip
                    else -> {
                        ResultsList(
                            grouped = state.results,
                            onResult = onResult,
                        )
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Search field
// ---------------------------------------------------------------------------

@Composable
private fun InlineSearchField(
    query: String,
    onQueryChange: (String) -> Unit,
    onSearch: () -> Unit,
    onVoice: () -> Unit,
    focusRequester: FocusRequester,
    modifier: Modifier = Modifier,
) {
    TextField(
        value = query,
        onValueChange = onQueryChange,
        modifier = modifier
            .fillMaxWidth()
            .focusRequester(focusRequester),
        placeholder = {
            Text(
                "Search everything…",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodyMedium,
            )
        },
        leadingIcon = {
            Icon(
                Icons.Default.Search,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.secondary,
            )
        },
        trailingIcon = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (query.isNotEmpty()) {
                    IconButton(onClick = { onQueryChange("") }) {
                        Icon(
                            Icons.Default.Clear,
                            contentDescription = "Clear",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                // item 6 — voice button
                IconButton(onClick = onVoice) {
                    Icon(
                        Icons.Default.Mic,
                        contentDescription = "Voice search",
                        tint = if (query.isEmpty())
                            MaterialTheme.colorScheme.secondary
                        else
                            MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        },
        singleLine = true,
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
        keyboardActions = KeyboardActions(onSearch = { onSearch() }),
        shape = RoundedCornerShape(16.dp),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
            unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
            disabledContainerColor = MaterialTheme.colorScheme.surfaceVariant,
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
            disabledIndicatorColor = Color.Transparent,
        ),
    )
}

// ---------------------------------------------------------------------------
// item 11 — offline banner
// ---------------------------------------------------------------------------

@Composable
private fun OfflineBanner() {
    Surface(
        color = MaterialTheme.colorScheme.errorContainer,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(
                Icons.Default.WifiOff,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onErrorContainer,
                modifier = Modifier.size(18.dp),
            )
            Text(
                "Showing cached results",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onErrorContainer,
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Idle state — recents + saved queries
// ---------------------------------------------------------------------------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun IdleState(
    recentSearches: List<String>,
    savedQueries: List<SavedQuery>,
    onRecentTapped: (String) -> Unit,
    onClearRecents: () -> Unit,
    onSavedQueryTapped: (SavedQuery) -> Unit,
    onRemoveSavedQuery: (String) -> Unit,
) {
    LazyColumn(modifier = Modifier.fillMaxSize()) {
        // item 8 — saved/pinned queries at top
        if (savedQueries.isNotEmpty()) {
            item(key = "saved-header") {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        Icons.Default.PushPin,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        "Saved searches",
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            item(key = "saved-chips") {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState())
                        .padding(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    savedQueries.forEach { sq ->
                        InputChip(
                            selected = false,
                            onClick = { onSavedQueryTapped(sq) },
                            label = { Text(sq.name) },
                            leadingIcon = {
                                Icon(
                                    Icons.Default.Search,
                                    contentDescription = null,
                                    modifier = Modifier.size(16.dp),
                                )
                            },
                            trailingIcon = {
                                IconButton(
                                    onClick = { onRemoveSavedQuery(sq.id) },
                                    modifier = Modifier.size(18.dp),
                                ) {
                                    Icon(
                                        Icons.Default.Close,
                                        contentDescription = "Remove saved search",
                                        modifier = Modifier.size(14.dp),
                                    )
                                }
                            },
                        )
                    }
                }
            }
            item(key = "saved-divider") {
                HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
            }
        }

        // item 7 — recent searches
        if (recentSearches.isNotEmpty()) {
            item(key = "recent-header") {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        "Recent",
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.weight(1f),
                    )
                    TextButton(onClick = onClearRecents) { Text("Clear") }
                }
            }
            items(items = recentSearches, key = { "recent-$it" }) { query ->
                ListItem(
                    modifier = Modifier.clickable { onRecentTapped(query) },
                    headlineContent = { Text(query, style = MaterialTheme.typography.bodyMedium) },
                    leadingContent = {
                        Icon(
                            Icons.Default.History,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    },
                )
            }
            item(key = "recent-divider") {
                HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
            }
        }

        // item 9 — search tips in empty state
        item(key = "tips") {
            SearchTips()
        }
    }
}

// ---------------------------------------------------------------------------
// item 9 — empty / tips
// ---------------------------------------------------------------------------

@Composable
private fun SearchTips() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 32.dp, vertical = 24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            Icons.Default.Search,
            contentDescription = null,
            modifier = Modifier.size(40.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
        )
        Text(
            "Search everything",
            style = MaterialTheme.typography.headlineMedium,
            color = MaterialTheme.colorScheme.onSurface,
        )
        Text(
            "Search across tickets, customers, invoices, inventory, employees, leads, appointments and SMS threads in one go.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(4.dp))
        val tips = listOf(
            "Try a ticket ID like #1042 or T-1042",
            "Search by phone number or email",
            "SKU or part name finds inventory fast",
            "Tap the 🎤 mic for voice search",
            "Pin a search with the 📌 icon to save it",
        )
        tips.forEach { tip ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.Top,
            ) {
                Text("•", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.secondary)
                Text(tip, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun NoResultsState(query: String) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 48.dp, vertical = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(
            Icons.Default.SearchOff,
            contentDescription = null,
            modifier = Modifier.size(36.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
        )
        Text(
            "No results",
            style = MaterialTheme.typography.headlineMedium,
            color = MaterialTheme.colorScheme.onSurface,
        )
        Text(
            "Nothing matched \"$query\"",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.secondary,
        )
        Spacer(Modifier.height(4.dp))
        Text(
            "Try a different search",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        // Tips even on no-results
        val tips = listOf(
            "Check the spelling",
            "Try a shorter or broader term",
            "Search by ID, phone, or email",
        )
        tips.forEach { tip ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.Top,
            ) {
                Text("•", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.secondary)
                Text(tip, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

// ---------------------------------------------------------------------------
// item 3 — grouped results list with count chip
// ---------------------------------------------------------------------------

@Composable
private fun ResultsList(
    grouped: Map<String, List<SearchResult>>,
    onResult: (type: String, id: Long, secondaryKey: String?) -> Unit,
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(bottom = 96.dp),
    ) {
        grouped.forEach { (type, results) ->
            item(key = "header-$type") {
                GroupHeader(type = type, count = results.size)
            }
            items(
                items = results,
                key = { r -> "${r.type}-${r.id}-${r.secondaryKey.orEmpty()}" },
                contentType = { it.type },
            ) { result ->
                ResultRow(result = result, onResult = onResult)
                HorizontalDivider(
                    color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
                    thickness = 1.dp,
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Group header with count chip
// ---------------------------------------------------------------------------

@Composable
private fun GroupHeader(type: String, count: Int) {
    val label = when (type) {
        "customer"    -> "Customers"
        "ticket"      -> "Tickets"
        "inventory"   -> "Inventory"
        "invoice"     -> "Invoices"
        "employee"    -> "Employees"
        "lead"        -> "Leads"
        "appointment" -> "Appointments"
        "sms"         -> "SMS Threads"
        else          -> type.replaceFirstChar { it.uppercase() }
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            text = label.uppercase(),
            style = MaterialTheme.typography.headlineMedium, // Barlow Condensed SemiBold
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        // Count chip — item 3
        Surface(
            shape = CircleShape,
            color = MaterialTheme.colorScheme.secondaryContainer,
        ) {
            Text(
                text = "$count",
                modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSecondaryContainer,
            )
        }
    }
}

// ---------------------------------------------------------------------------
// Single result row
// ---------------------------------------------------------------------------

@Composable
private fun ResultRow(
    result: SearchResult,
    onResult: (type: String, id: Long, secondaryKey: String?) -> Unit,
) {
    val icon: ImageVector = when (result.type) {
        "ticket"      -> Icons.Default.ConfirmationNumber
        "customer"    -> Icons.Default.Person
        "inventory"   -> Icons.Default.Inventory2
        "invoice"     -> Icons.Default.Receipt
        "employee"    -> Icons.Default.Badge
        "lead"        -> Icons.Default.PersonSearch
        "appointment" -> Icons.Default.CalendarToday
        "sms"         -> Icons.Default.Sms
        else          -> Icons.Default.Article
    }

    ListItem(
        modifier = Modifier.clickable { onResult(result.type, result.id, result.secondaryKey) },
        headlineContent = {
            Text(result.title, style = MaterialTheme.typography.bodyMedium)
        },
        supportingContent = {
            Text(
                result.subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        },
        leadingContent = {
            if (result.type == "customer") {
                // Initial-circle avatar matching CustomerList style
                val initial = result.title.firstOrNull { it.isLetter() }
                    ?.uppercaseChar()?.toString() ?: "?"
                Box(
                    modifier = Modifier
                        .size(36.dp)
                        .clip(CircleShape)
                        .background(MaterialTheme.colorScheme.primaryContainer),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        initial,
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onPrimaryContainer,
                    )
                }
            } else {
                Icon(
                    icon,
                    contentDescription = result.type,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
        trailingContent = {
            BrandStatusBadge(
                label = when (result.type) {
                    "customer"    -> "Customer"
                    "ticket"      -> "Ticket"
                    "inventory"   -> "Inventory"
                    "invoice"     -> "Invoice"
                    "employee"    -> "Employee"
                    "lead"        -> "Lead"
                    "appointment" -> "Appt"
                    "sms"         -> "SMS"
                    else          -> result.type.replaceFirstChar { it.uppercase() }
                },
                status = result.type,
            )
        },
    )
}

// ---------------------------------------------------------------------------
// item 8 — save-query dialog
// ---------------------------------------------------------------------------

@Composable
private fun SaveQueryDialog(
    initialName: String,
    onSave: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    var name by remember { mutableStateOf(initialName) }
    AlertDialog(
        onDismissRequest = onDismiss,
        icon = { Icon(Icons.Default.PushPin, contentDescription = null) },
        title = { Text("Save search") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    "Name this search so you can find it quickly later.",
                    style = MaterialTheme.typography.bodyMedium,
                )
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("Name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = { if (name.isNotBlank()) onSave(name) },
                enabled = name.isNotBlank(),
            ) { Text("Save") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}
