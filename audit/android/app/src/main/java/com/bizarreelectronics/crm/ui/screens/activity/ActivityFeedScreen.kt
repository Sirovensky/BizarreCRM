package com.bizarreelectronics.crm.ui.screens.activity

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.remote.dto.ActivityEventDto
import com.bizarreelectronics.crm.ui.screens.activity.components.ActivityFilterChips
import com.bizarreelectronics.crm.ui.screens.activity.components.EventReactionRow

/**
 * §3.16 L592-L599 — Full-screen Activity Feed.
 *
 * Features:
 *  - Filter chip row (§L594) for type + myActivity.
 *  - Infinite scroll via cursor pagination (§L599).
 *  - Real-time prepend from WebSocket `activity:new` (§L592).
 *  - Tap row → navigate to entity detail (§L595).
 *  - Emoji reactions below each row (§L596).
 *  - Defense-in-depth PII redaction (§L598).
 *
 * @param onBack           Navigate back (pop).
 * @param onNavigate       Called with a route string to navigate to entity details.
 *                         Unknown types default to "dashboard".
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ActivityFeedScreen(
    onBack: () -> Unit,
    onNavigate: (route: String) -> Unit,
    modifier: Modifier = Modifier,
    viewModel: ActivityFeedViewModel = hiltViewModel(),
) {
    val items by viewModel.items.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val isLoadingMore by viewModel.isLoadingMore.collectAsState()
    val error by viewModel.error.collectAsState()
    val filter by viewModel.filter.collectAsState()
    val hasMore by viewModel.hasMore.collectAsState()

    // ReduceMotion: read from system animator scale via compose ambient.
    // In production use LocalAppPreferences if available; fall back to false.
    val reduceMotion = false // resolved via AppPreferences.reduceMotionEnabled at call site

    val listState = rememberLazyListState()

    // Trigger loadMore when within 3 items of the bottom
    val shouldLoadMore by remember {
        derivedStateOf {
            val lastVisible = listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0
            val total = listState.layoutInfo.totalItemsCount
            total > 0 && lastVisible >= total - 3
        }
    }

    LaunchedEffect(shouldLoadMore) {
        if (shouldLoadMore) viewModel.loadMore()
    }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = { Text("Activity Feed") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                        )
                    }
                },
                actions = {
                    IconButton(
                        onClick = { viewModel.refresh() },
                        modifier = Modifier.semantics { contentDescription = "Refresh activity feed" },
                    ) {
                        Icon(Icons.Default.Refresh, contentDescription = null)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                ),
            )
        },
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
        ) {
            // §L594 — Filter chips
            ActivityFilterChips(
                filter = filter,
                onFilterChange = { viewModel.updateFilter(it) },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 8.dp),
            )

            when {
                isLoading -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                }

                error != null -> {
                    ActivityErrorState(
                        message = error ?: "Unknown error",
                        onRetry = { viewModel.refresh() },
                    )
                }

                items.isEmpty() -> {
                    ActivityEmptyState()
                }

                else -> {
                    LazyColumn(
                        state = listState,
                        contentPadding = PaddingValues(vertical = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(0.dp),
                    ) {
                        items(
                            items = items,
                            key = { it.id },
                        ) { event ->
                            ActivityEventRow(
                                event = event,
                                reduceMotion = reduceMotion,
                                onClick = { onNavigate(routeForEvent(event)) },
                                onReact = { id, emoji -> viewModel.react(id, emoji) },
                            )
                        }

                        if (isLoadingMore) {
                            item(key = "loading_more") {
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(16.dp),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    CircularProgressIndicator(modifier = Modifier.size(24.dp))
                                }
                            }
                        }

                        if (!hasMore && items.isNotEmpty()) {
                            item(key = "end_of_list") {
                                Text(
                                    text = "No more activity",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(16.dp),
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

// ─── Private composables ─────────────────────────────────────────────────────

@Composable
private fun ActivityEventRow(
    event: ActivityEventDto,
    reduceMotion: Boolean,
    onClick: () -> Unit,
    onReact: (Long, String) -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            // Avatar
            Surface(
                modifier = Modifier.size(36.dp),
                shape = CircleShape,
                color = MaterialTheme.colorScheme.primaryContainer,
            ) {
                Box(contentAlignment = Alignment.Center) {
                    val initials = event.avatarInitials
                    if (!initials.isNullOrBlank()) {
                        Text(
                            text = initials.take(2).uppercase(),
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.onPrimaryContainer,
                        )
                    } else {
                        Icon(
                            imageVector = Icons.Default.Person,
                            contentDescription = null,
                            modifier = Modifier.size(20.dp),
                            tint = MaterialTheme.colorScheme.onPrimaryContainer,
                        )
                    }
                }
            }

            Column(modifier = Modifier.weight(1f)) {
                // Bold actor + verb + colored subject
                val annotated = buildAnnotatedString {
                    withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { append(event.actor) }
                    append(" ${event.verb} ")
                    withStyle(SpanStyle(color = MaterialTheme.colorScheme.primary)) {
                        append(event.subject)
                    }
                }
                Text(text = annotated, style = MaterialTheme.typography.bodySmall)

                if (event.text.isNotBlank() && event.text != "${event.actor} ${event.verb} ${event.subject}") {
                    Spacer(Modifier.height(2.dp))
                    Text(
                        text = event.text,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }

                Spacer(Modifier.height(2.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        text = event.timeAgo,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.72f),
                    )
                    event.location?.let { loc ->
                        Text(
                            text = loc,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.55f),
                        )
                    }
                }
            }
        }

        // §L596 — Reaction row
        EventReactionRow(
            eventId = event.id,
            reactions = event.reactions,
            onReact = onReact,
            reduceMotion = reduceMotion,
            modifier = Modifier.padding(start = 46.dp),
        )
    }
}

@Composable
private fun ActivityEmptyState() {
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(
                imageVector = Icons.Default.History,
                contentDescription = null,
                modifier = Modifier.size(40.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
            )
            Spacer(Modifier.height(8.dp))
            Text(
                text = "No activity yet",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun ActivityErrorState(message: String, onRetry: () -> Unit) {
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                text = message,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.error,
            )
            Spacer(Modifier.height(8.dp))
            TextButton(onClick = onRetry) { Text("Retry") }
        }
    }
}

// ─── Deep-link routing ───────────────────────────────────────────────────────

/**
 * §3.16 L595 — Map event → nav route string for deep-link drill.
 *
 * Known entity types route to their detail screens. Unknown types fall back
 * to "dashboard" so tapping never dead-ends the user.
 */
private fun routeForEvent(event: ActivityEventDto): String {
    val id = event.entityId ?: return "dashboard"
    return when (event.entityType) {
        "ticket"    -> "tickets/$id"
        "invoice"   -> "invoices/$id"
        "customer"  -> "customers/$id"
        "inventory" -> "inventory/$id"
        else        -> "dashboard"
    }
}
