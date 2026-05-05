package com.bizarreelectronics.crm.ui.screens.team

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Forum
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.remote.api.TeamChatRoom
import com.bizarreelectronics.crm.ui.components.WaveDivider
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.components.shared.SearchBar
import com.bizarreelectronics.crm.ui.screens.team.components.AvatarInitial
import com.bizarreelectronics.crm.util.DateFormatter

/**
 * §47 — Team Chat room list screen.
 * Shows all rooms the authenticated user belongs to.
 * 404-tolerant: displays "Team chat not configured" empty state on 404.
 * Role-gate: staff+ only (enforced on server; client shows empty state if denied).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TeamChatListScreen(
    onRoomClick: (roomId: String, roomName: String) -> Unit,
    viewModel: TeamChatListViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    Scaffold(
        topBar = {
            Column {
                BrandTopAppBar(
                    title = "Team Chat",
                    actions = {
                        IconButton(onClick = { viewModel.loadRooms() }) {
                            Icon(
                                Icons.Default.Refresh,
                                contentDescription = "Refresh",
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    },
                )
                WaveDivider()
            }
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            SearchBar(
                query = state.searchQuery,
                onQueryChange = { viewModel.onSearchChanged(it) },
                placeholder = "Search rooms\u2026",
                modifier = Modifier
                    .padding(horizontal = 16.dp, vertical = 8.dp)
                    .semantics { contentDescription = "Search team chat rooms" },
            )

            when {
                state.isLoading -> {
                    BrandSkeleton(
                        rows = 5,
                        modifier = Modifier
                            .fillMaxSize()
                            .semantics(mergeDescendants = true) {
                                contentDescription = "Loading rooms"
                            },
                    )
                }
                state.notConfigured -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        EmptyState(
                            icon = Icons.Default.Forum,
                            title = "Team chat not configured",
                            subtitle = "Ask your admin to enable team chat.",
                            includeWave = false,
                        )
                    }
                }
                state.error != null -> {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .semantics { liveRegion = LiveRegionMode.Assertive },
                        contentAlignment = Alignment.Center,
                    ) {
                        ErrorState(
                            message = state.error ?: "Something went wrong",
                            onRetry = { viewModel.loadRooms() },
                        )
                    }
                }
                state.rooms.isEmpty() -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        EmptyState(
                            icon = Icons.Default.Forum,
                            title = "No rooms",
                            subtitle = "You have no team chat rooms yet.",
                            includeWave = false,
                        )
                    }
                }
                else -> {
                    PullToRefreshBox(
                        isRefreshing = state.isRefreshing,
                        onRefresh = { viewModel.refresh() },
                    ) {
                        LazyColumn(
                            contentPadding = PaddingValues(bottom = 80.dp),
                            modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
                        ) {
                            items(state.rooms, key = { it.id }) { room ->
                                RoomRow(
                                    room = room,
                                    onClick = { onRoomClick(room.id, room.name) },
                                )
                                HorizontalDivider(
                                    color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
                                    thickness = 1.dp,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun RoomRow(
    room: TeamChatRoom,
    onClick: () -> Unit,
) {
    val hasUnread = room.unreadCount > 0
    val a11yDesc = buildString {
        append("${room.name}.")
        if (hasUnread) append(" ${room.unreadCount} unread.")
        if (room.isPinned) append(" Pinned.")
        if (room.lastMessage != null) append(" Last: ${room.lastMessage}.")
        append(" Tap to open.")
    }

    ListItem(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .semantics(mergeDescendants = true) {
                contentDescription = a11yDesc
                role = Role.Button
            },
        headlineContent = {
            Row(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    room.name,
                    fontWeight = if (hasUnread) FontWeight.Bold else FontWeight.Normal,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false),
                )
                if (room.isPinned) {
                    Icon(
                        Icons.Default.PushPin,
                        contentDescription = "Pinned",
                        modifier = Modifier.size(14.dp),
                        tint = MaterialTheme.colorScheme.primary,
                    )
                }
                if (room.type == "dm") {
                    Icon(
                        Icons.Default.Lock,
                        contentDescription = "Direct message",
                        modifier = Modifier.size(14.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        },
        supportingContent = {
            Text(
                room.lastMessage ?: room.description ?: "",
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                fontWeight = if (hasUnread) FontWeight.SemiBold else FontWeight.Normal,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        },
        leadingContent = {
            Box {
                AvatarInitial(name = room.name, size = 36)
                if (hasUnread) {
                    Badge(
                        containerColor = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.align(Alignment.TopEnd),
                    ) {
                        Text(
                            if (room.unreadCount > 99) "99+" else "${room.unreadCount}",
                            style = MaterialTheme.typography.labelSmall,
                        )
                    }
                }
            }
        },
        trailingContent = {
            if (room.lastMessageAt != null) {
                Text(
                    DateFormatter.formatRelative(room.lastMessageAt),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
    )
}
