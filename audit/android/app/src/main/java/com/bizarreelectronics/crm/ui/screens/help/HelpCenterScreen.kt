package com.bizarreelectronics.crm.ui.screens.help

import androidx.annotation.RawRes
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.filled.HelpOutline
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/**
 * A single help topic backed by a bundled Markdown resource.
 *
 * @param titleResId  String resource for the topic label shown in the list.
 * @param rawResId    Raw resource (res/raw/help_*.md) containing the content.
 * @param keywords    Lower-case words used for client-side FTS search.
 */
data class HelpTopic(
    val titleResId: Int,
    @RawRes val rawResId: Int,
    val keywords: List<String>,
)

/** All bundled help topics. Order determines display order in the list. */
val ALL_HELP_TOPICS = listOf(
    HelpTopic(
        titleResId = R.string.help_topic_tickets,
        rawResId = R.raw.help_tickets,
        keywords = listOf("ticket", "repair", "status", "parts", "photo", "imei", "serial"),
    ),
    HelpTopic(
        titleResId = R.string.help_topic_customers,
        rawResId = R.raw.help_customers,
        keywords = listOf("customer", "contact", "phone", "email", "notes", "health", "ltv", "merge"),
    ),
    HelpTopic(
        titleResId = R.string.help_topic_invoices,
        rawResId = R.raw.help_invoices,
        keywords = listOf("invoice", "payment", "refund", "overdue", "draft", "export"),
    ),
    HelpTopic(
        titleResId = R.string.help_topic_pos,
        rawResId = R.raw.help_pos,
        keywords = listOf("pos", "sale", "cart", "terminal", "cash", "card", "receipt", "split", "gift"),
    ),
    HelpTopic(
        titleResId = R.string.help_topic_inventory,
        rawResId = R.raw.help_inventory,
        keywords = listOf("inventory", "stock", "barcode", "sku", "purchase", "order", "reorder"),
    ),
    HelpTopic(
        titleResId = R.string.help_topic_settings,
        rawResId = R.raw.help_settings,
        keywords = listOf("settings", "profile", "security", "pin", "biometric", "theme", "language", "hardware"),
    ),
)

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

data class HelpCenterUiState(
    val query: String = "",
    val filteredTopics: List<HelpTopic> = ALL_HELP_TOPICS,
    val selectedTopic: HelpTopic? = null,
    val topicContent: String = "",
    val isLoadingContent: Boolean = false,
)

@HiltViewModel
class HelpCenterViewModel @Inject constructor() : ViewModel() {

    private val _uiState = MutableStateFlow(HelpCenterUiState())
    val uiState: StateFlow<HelpCenterUiState> = _uiState.asStateFlow()

    fun onQueryChange(query: String) {
        val q = query.lowercase().trim()
        val filtered = if (q.isEmpty()) {
            ALL_HELP_TOPICS
        } else {
            ALL_HELP_TOPICS.filter { topic ->
                topic.keywords.any { kw -> kw.contains(q) }
            }
        }
        _uiState.value = _uiState.value.copy(query = query, filteredTopics = filtered)
    }

    fun onTopicSelected(topic: HelpTopic, rawContent: String) {
        _uiState.value = _uiState.value.copy(
            selectedTopic = topic,
            topicContent = rawContent,
        )
    }

    fun onBackFromTopic() {
        _uiState.value = _uiState.value.copy(
            selectedTopic = null,
            topicContent = "",
        )
    }

    fun clearQuery() {
        onQueryChange("")
    }
}

// ---------------------------------------------------------------------------
// Composables
// ---------------------------------------------------------------------------

/**
 * §72.1 — Settings → Help center.
 *
 * Shows all bundled help topics grouped in a searchable list. Each topic opens
 * a detail view rendered from the bundled Markdown file in res/raw/.
 *
 * All content is served offline (no network required).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HelpCenterScreen(
    onBack: () -> Unit,
    onContactSupport: (() -> Unit)? = null,
    viewModel: HelpCenterViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsState()
    val context = LocalContext.current

    // If a topic is selected, show its detail view
    if (state.selectedTopic != null) {
        HelpTopicDetailScreen(
            topic = state.selectedTopic!!,
            content = state.topicContent,
            onBack = { viewModel.onBackFromTopic() },
        )
        return
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = stringResource(R.string.screen_help_center),
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.cd_navigate_back),
                        )
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
            // §72.1 — Search bar for FTS topic filtering
            var searchActive by remember { mutableStateOf(false) }
            SearchBar(
                inputField = {
                    SearchBarDefaults.InputField(
                        query = state.query,
                        onQueryChange = { viewModel.onQueryChange(it) },
                        onSearch = { searchActive = false },
                        expanded = searchActive,
                        onExpandedChange = { searchActive = it },
                        placeholder = { Text(stringResource(R.string.help_search_hint)) },
                        leadingIcon = {
                            Icon(
                                imageVector = Icons.Default.Search,
                                contentDescription = stringResource(R.string.cd_search),
                            )
                        },
                        trailingIcon = {
                            if (state.query.isNotEmpty()) {
                                IconButton(onClick = { viewModel.clearQuery() }) {
                                    Icon(
                                        imageVector = Icons.Default.Close,
                                        contentDescription = stringResource(R.string.help_search_clear_cd),
                                    )
                                }
                            }
                        },
                    )
                },
                expanded = searchActive,
                onExpandedChange = { searchActive = it },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
            ) {}

            if (state.filteredTopics.isEmpty()) {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = stringResource(R.string.help_search_no_results),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            } else {
                LazyColumn(
                    contentPadding = PaddingValues(bottom = 16.dp),
                ) {
                    items(state.filteredTopics) { topic ->
                        val topicTitle = stringResource(topic.titleResId)
                        HelpTopicRow(
                            title = topicTitle,
                            onClick = {
                                val raw = runCatching {
                                    context.resources.openRawResource(topic.rawResId)
                                        .bufferedReader()
                                        .readText()
                                }.getOrDefault("")
                                viewModel.onTopicSelected(topic, raw)
                            },
                        )
                        HorizontalDivider(modifier = Modifier.padding(horizontal = 16.dp))
                    }
                }
            }

            // Contact support entry point at the bottom
            if (onContactSupport != null) {
                HorizontalDivider()
                ListItem(
                    headlineContent = {
                        Text(stringResource(R.string.help_contact_support))
                    },
                    leadingContent = {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.HelpOutline,
                            contentDescription = stringResource(R.string.help_contact_support_cd),
                        )
                    },
                    trailingContent = {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowForward,
                            contentDescription = null,
                        )
                    },
                    modifier = Modifier.clickable { onContactSupport() },
                )
            }
        }
    }
}

@Composable
private fun HelpTopicRow(
    title: String,
    onClick: () -> Unit,
) {
    ListItem(
        headlineContent = { Text(title) },
        trailingContent = {
            Icon(
                imageVector = Icons.AutoMirrored.Filled.ArrowForward,
                contentDescription = null,
            )
        },
        modifier = Modifier
            .clickable(onClick = onClick)
            .semantics { contentDescription = title },
    )
}

// ---------------------------------------------------------------------------
// Topic detail
// ---------------------------------------------------------------------------

/**
 * Renders a single help topic's Markdown content as plain styled text.
 *
 * Using plain Compose Text for now per the constraint to avoid pulling in an
 * external Markdown library. The content is displayed with simple heading
 * detection: lines beginning with `# ` or `## ` are rendered with
 * titleLarge / titleMedium style; everything else uses bodyMedium.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HelpTopicDetailScreen(
    topic: HelpTopic,
    content: String,
    onBack: () -> Unit,
) {
    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = stringResource(topic.titleResId),
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.cd_navigate_back),
                        )
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            content.lines().forEach { line ->
                when {
                    line.startsWith("# ") -> {
                        Text(
                            text = line.removePrefix("# "),
                            style = MaterialTheme.typography.titleLarge,
                            modifier = Modifier.padding(top = 8.dp, bottom = 4.dp),
                        )
                    }
                    line.startsWith("## ") -> {
                        Text(
                            text = line.removePrefix("## "),
                            style = MaterialTheme.typography.titleMedium,
                            modifier = Modifier.padding(top = 12.dp, bottom = 2.dp),
                        )
                    }
                    line.startsWith("- ") -> {
                        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(
                                text = "•",
                                style = MaterialTheme.typography.bodyMedium,
                            )
                            Text(
                                text = line.removePrefix("- "),
                                style = MaterialTheme.typography.bodyMedium,
                            )
                        }
                    }
                    line.isBlank() -> {
                        Spacer(modifier = Modifier.height(4.dp))
                    }
                    else -> {
                        Text(
                            text = line,
                            style = MaterialTheme.typography.bodyMedium,
                        )
                    }
                }
            }
        }
    }
}
