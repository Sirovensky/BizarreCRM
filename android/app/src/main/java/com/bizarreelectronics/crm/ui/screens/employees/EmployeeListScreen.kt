package com.bizarreelectronics.crm.ui.screens.employees

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.ui.theme.*
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.SettingsApi
import com.bizarreelectronics.crm.data.remote.dto.EmployeeListItem
import com.bizarreelectronics.crm.service.WebSocketService
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import com.bizarreelectronics.crm.util.isMediumOrExpandedWidth
import com.bizarreelectronics.crm.ui.components.shared.BrandListItem
import com.bizarreelectronics.crm.ui.components.shared.BrandListItemDivider
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.screens.employees.components.EmployeeFilter
import com.bizarreelectronics.crm.ui.screens.employees.components.EmployeeFilterChips
import com.bizarreelectronics.crm.ui.screens.employees.components.PresenceBadge
import com.bizarreelectronics.crm.ui.screens.employees.components.PresenceStatus
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

// region — ViewModel

data class EmployeeListUiState(
    val employees: List<EmployeeListItem> = emptyList(),
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val isOffline: Boolean = false,
    // Whether the signed-in user may invoke admin-only flows such as the
    // create-employee FAB. Derived once at VM construction from AuthPreferences.
    val isAdmin: Boolean = false,
    // §14.1 L1610 — active filter chip
    val activeFilter: EmployeeFilter = EmployeeFilter.All,
    // §14.1 L1611 — real-time presence map: employeeId → PresenceStatus.
    // Populated from WebSocket "presence" events; absent = Off (stub gray).
    val presenceMap: Map<Long, PresenceStatus> = emptyMap(),
) {
    /** Derived filtered list applied in UI without extra API calls. */
    val filtered: List<EmployeeListItem>
        get() = when (activeFilter) {
            EmployeeFilter.All -> employees
            EmployeeFilter.Admin -> employees.filter { it.role == "admin" }
            EmployeeFilter.Technician -> employees.filter { it.role == "technician" }
            EmployeeFilter.Active -> employees.filter { it.isActive == 1 }
            EmployeeFilter.Inactive -> employees.filter { it.isActive != 1 }
            EmployeeFilter.ClockedIn -> employees.filter { it.isClockedIn == true }
        }
}

@HiltViewModel
class EmployeeListViewModel @Inject constructor(
    private val settingsApi: SettingsApi,
    private val serverMonitor: ServerReachabilityMonitor,
    private val webSocketService: WebSocketService,
    authPreferences: AuthPreferences,
) : ViewModel() {

    private val _state = MutableStateFlow(
        EmployeeListUiState(isAdmin = authPreferences.userRole == "admin"),
    )
    val state = _state.asStateFlow()

    init {
        loadEmployees()
        observePresence()
    }

    fun loadEmployees() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null, isOffline = false)
            try {
                val response = settingsApi.getEmployees()
                val employees = response.data ?: emptyList()
                cachedEmployees = employees
                _state.value = _state.value.copy(
                    employees = employees,
                    isLoading = false,
                    isRefreshing = false,
                )
            } catch (e: Exception) {
                val cached = cachedEmployees
                if (cached != null) {
                    _state.value = _state.value.copy(
                        employees = cached,
                        isLoading = false,
                        isRefreshing = false,
                        isOffline = true,
                        error = "Offline — showing cached data",
                    )
                } else {
                    _state.value = _state.value.copy(
                        isLoading = false,
                        isRefreshing = false,
                        isOffline = !serverMonitor.isEffectivelyOnline.value,
                        error = if (!serverMonitor.isEffectivelyOnline.value) {
                            "Offline — no cached data available"
                        } else {
                            e.message ?: "Failed to load employees"
                        },
                    )
                }
            }
        }
    }

    fun refresh() {
        _state.value = _state.value.copy(isRefreshing = true)
        loadEmployees()
    }

    fun setFilter(filter: EmployeeFilter) {
        _state.value = _state.value.copy(activeFilter = filter)
    }

    /**
     * §14.1 L1611 — Subscribe to WebSocket "presence" events.
     * Event shape expected: { type: "presence", employeeId: 42, status: "clocked_in"|"on_break"|"off" }
     * Falls back gracefully if the field is absent or null.
     */
    private fun observePresence() {
        viewModelScope.launch {
            webSocketService.events.collect { event ->
                if (event.type != "presence") return@collect
                try {
                    val json = com.google.gson.Gson().fromJson(event.data, Map::class.java)
                    val idRaw = json["employeeId"] ?: return@collect
                    val statusRaw = json["status"]?.toString() ?: return@collect
                    val employeeId = (idRaw as? Number)?.toLong() ?: return@collect
                    val presence = when (statusRaw) {
                        "clocked_in" -> PresenceStatus.ClockedIn
                        "on_break" -> PresenceStatus.OnBreak
                        else -> PresenceStatus.Off
                    }
                    val updated = _state.value.presenceMap + (employeeId to presence)
                    _state.value = _state.value.copy(presenceMap = updated)
                } catch (_: Exception) {
                    // Malformed WS payload — ignore silently
                }
            }
        }
    }

    companion object {
        private var cachedEmployees: List<EmployeeListItem>? = null
    }
}

// endregion

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EmployeeListScreen(
    onClockInOutClick: () -> Unit = {},
    onCreateClick: () -> Unit = {},
    onEmployeeClick: (Long) -> Unit = {},
    refreshTrigger: Boolean = false,
    onRefreshConsumed: () -> Unit = {},
    viewModel: EmployeeListViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    // §14.1 L1612 — tablet layout detection (uses project's rememberWindowMode helper)
    val isTablet = isMediumOrExpandedWidth()

    LaunchedEffect(refreshTrigger) {
        if (refreshTrigger) {
            viewModel.loadEmployees()
            onRefreshConsumed()
        }
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Employees",
                actions = {
                    IconButton(onClick = onClockInOutClick) {
                        Icon(Icons.Default.AccessTime, contentDescription = "Clock In/Out")
                    }
                    IconButton(onClick = { viewModel.loadEmployees() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
                    }
                },
            )
        },
        floatingActionButton = {
            if (state.isAdmin) {
                FloatingActionButton(
                    onClick = onCreateClick,
                    containerColor = MaterialTheme.colorScheme.primary,
                ) {
                    Icon(Icons.Default.PersonAdd, contentDescription = "Add employee")
                }
            }
        },
    ) { padding ->
        when {
            state.isLoading -> {
                BrandSkeleton(
                    rows = 6,
                    modifier = Modifier.fillMaxSize().padding(padding),
                )
            }
            state.error != null && state.employees.isEmpty() -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    ErrorState(
                        message = state.error ?: "Failed to load employees",
                        onRetry = { viewModel.loadEmployees() },
                    )
                }
            }
            else -> {
                Column(modifier = Modifier.fillMaxSize().padding(padding)) {
                    // §14.1 L1610 — filter chip row
                    EmployeeFilterChips(
                        selected = state.activeFilter,
                        onSelect = { viewModel.setFilter(it) },
                        modifier = Modifier.fillMaxWidth(),
                    )

                    if (state.employees.isEmpty()) {
                        Box(
                            modifier = Modifier.fillMaxSize(),
                            contentAlignment = Alignment.Center,
                        ) {
                            EmptyState(
                                icon = Icons.Default.Group,
                                title = "No employees",
                                subtitle = "No employee accounts found.",
                            )
                        }
                    } else {
                        PullToRefreshBox(
                            isRefreshing = state.isRefreshing,
                            onRefresh = { viewModel.refresh() },
                            modifier = Modifier.fillMaxSize(),
                        ) {
                            if (isTablet) {
                                // §14.1 L1612 — tablet: multi-column grid with header row
                                EmployeeTabletGrid(
                                    employees = state.filtered,
                                    presenceMap = state.presenceMap,
                                    isOffline = state.isOffline,
                                    offlineBanner = state.error,
                                    onEmployeeClick = onEmployeeClick,
                                )
                            } else {
                                LazyColumn(
                                    modifier = Modifier.fillMaxSize(),
                                    contentPadding = PaddingValues(top = 4.dp, bottom = 80.dp),
                                ) {
                                    if (state.isOffline && state.error != null) {
                                        item {
                                            Text(
                                                text = state.error ?: "",
                                                modifier = Modifier
                                                    .fillMaxWidth()
                                                    .padding(horizontal = 16.dp, vertical = 6.dp),
                                                style = MaterialTheme.typography.labelSmall,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                            )
                                        }
                                    }
                                    items(state.filtered, key = { it.id }) { employee ->
                                        val presence = state.presenceMap[employee.id]
                                            ?: if (employee.isClockedIn == true) PresenceStatus.ClockedIn
                                            else PresenceStatus.Off
                                        EmployeeRow(
                                            employee = employee,
                                            presence = presence,
                                            onClick = { onEmployeeClick(employee.id) },
                                        )
                                        BrandListItemDivider()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// region — Tablet grid layout

@Composable
private fun EmployeeTabletGrid(
    employees: List<EmployeeListItem>,
    presenceMap: Map<Long, PresenceStatus>,
    isOffline: Boolean,
    offlineBanner: String?,
    onEmployeeClick: (Long) -> Unit,
) {
    LazyVerticalGrid(
        columns = GridCells.Fixed(1),
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(bottom = 80.dp),
    ) {
        // Header row
        item {
            if (isOffline && offlineBanner != null) {
                Text(
                    text = offlineBanner,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 6.dp),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            EmployeeTableHeader()
        }
        items(employees, key = { it.id }) { employee ->
            val presence = presenceMap[employee.id]
                ?: if (employee.isClockedIn == true) PresenceStatus.ClockedIn
                else PresenceStatus.Off
            EmployeeTableRow(
                employee = employee,
                presence = presence,
                onClick = { onEmployeeClick(employee.id) },
            )
            BrandListItemDivider()
        }
    }
}

@Composable
private fun EmployeeTableHeader() {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("Name", Modifier.weight(2f), style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text("Email", Modifier.weight(2f), style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text("Role", Modifier.weight(1f), style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text("Status", Modifier.weight(1f), style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text("Hours", Modifier.weight(1f), style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun EmployeeTableRow(
    employee: EmployeeListItem,
    presence: PresenceStatus,
    onClick: () -> Unit,
) {
    val isActive = employee.isActive == 1
    val displayName = listOfNotNull(employee.firstName, employee.lastName)
        .joinToString(" ").ifBlank { employee.username ?: "Unknown" }

    Surface(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // Name + presence dot
            Row(
                modifier = Modifier.weight(2f),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                PresenceBadge(status = presence, size = 8.dp, borderWidth = 1.dp)
                Text(
                    text = displayName,
                    style = MaterialTheme.typography.bodyMedium,
                    maxLines = 1,
                )
            }
            Text(
                text = employee.email ?: "—",
                modifier = Modifier.weight(2f),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
            )
            Text(
                text = (employee.role ?: "—").replaceFirstChar { it.uppercase() },
                modifier = Modifier.weight(1f),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.secondary,
            )
            Text(
                text = if (isActive) "Active" else "Inactive",
                modifier = Modifier.weight(1f),
                style = MaterialTheme.typography.bodySmall,
                color = if (isActive) SuccessGreen else MaterialTheme.colorScheme.onSurfaceVariant,
            )
            // Hours: stub "—" until weekly endpoint lands
            Text(
                text = "—",
                modifier = Modifier.weight(1f),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// endregion

// region — Phone list row

@Composable
private fun EmployeeRow(
    employee: EmployeeListItem,
    presence: PresenceStatus,
    onClick: () -> Unit,
) {
    val isActive = employee.isActive == 1

    BrandListItem(
        onClick = onClick,
        leading = {
            val initial = (employee.firstName?.firstOrNull()
                ?: employee.username?.firstOrNull())
                ?.uppercase() ?: ""
            Box(
                modifier = Modifier
                    .size(36.dp)
                    .background(
                        color = MaterialTheme.colorScheme.primaryContainer,
                        shape = CircleShape,
                    ),
                contentAlignment = Alignment.Center,
            ) {
                if (initial.isNotBlank()) {
                    Text(
                        text = initial,
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onPrimaryContainer,
                    )
                } else {
                    Icon(
                        Icons.Default.Person,
                        contentDescription = null,
                        modifier = Modifier.size(20.dp),
                        tint = MaterialTheme.colorScheme.onPrimaryContainer,
                    )
                }
                // §14.1 L1611 — presence dot (replaces old isClockedIn dot)
                PresenceBadge(
                    status = presence,
                    size = 10.dp,
                    borderWidth = 1.5.dp,
                    modifier = Modifier.align(Alignment.BottomEnd),
                )
            }
        },
        headline = {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Text(
                    text = listOfNotNull(employee.firstName, employee.lastName)
                        .joinToString(" ")
                        .ifBlank { employee.username ?: "Unknown" },
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                when (presence) {
                    PresenceStatus.ClockedIn -> Text(
                        "Clocked in", style = MaterialTheme.typography.labelSmall,
                        color = SuccessGreen,
                    )
                    PresenceStatus.OnBreak -> Text(
                        "On break", style = MaterialTheme.typography.labelSmall,
                        color = WarningAmber,
                    )
                    PresenceStatus.Off -> Unit
                }
            }
        },
        support = {
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Surface(
                    shape = MaterialTheme.shapes.small,
                    color = MaterialTheme.colorScheme.surfaceVariant,
                ) {
                    Text(
                        text = (employee.role ?: "user").replaceFirstChar { it.uppercase() },
                        modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.secondary,
                    )
                }
                if (!employee.email.isNullOrBlank()) {
                    Text(
                        text = employee.email,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        },
        trailing = {
            Surface(
                shape = MaterialTheme.shapes.small,
                color = MaterialTheme.colorScheme.surfaceVariant,
            ) {
                Text(
                    text = if (isActive) "Active" else "Inactive",
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                    style = MaterialTheme.typography.labelSmall,
                    color = if (isActive) SuccessGreen
                    else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
    )
}

// endregion
