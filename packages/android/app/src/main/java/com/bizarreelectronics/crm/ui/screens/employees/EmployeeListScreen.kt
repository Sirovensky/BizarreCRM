package com.bizarreelectronics.crm.ui.screens.employees

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
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
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import com.bizarreelectronics.crm.ui.components.shared.BrandListItem
import com.bizarreelectronics.crm.ui.components.shared.BrandListItemDivider
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class EmployeeListUiState(
    val employees: List<EmployeeListItem> = emptyList(),
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    val isOffline: Boolean = false,
    // Whether the signed-in user may invoke admin-only flows such as the
    // create-employee FAB. Derived once at VM construction from AuthPreferences
    // — refreshing role on login is handled by AuthPreferences.clear() firing
    // authCleared which forces a restart of this screen.
    val isAdmin: Boolean = false,
)

@HiltViewModel
class EmployeeListViewModel @Inject constructor(
    private val settingsApi: SettingsApi,
    private val serverMonitor: ServerReachabilityMonitor,
    authPreferences: AuthPreferences,
) : ViewModel() {

    // Seed the initial state with the admin flag so the UI can decide whether
    // to render the create-employee FAB without flicker on first composition.
    private val _state = MutableStateFlow(
        EmployeeListUiState(isAdmin = authPreferences.userRole == "admin"),
    )
    val state = _state.asStateFlow()

    init {
        loadEmployees()
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

    // D5-7: force-refresh hook for PullToRefreshBox. Sets isRefreshing so the
    // spinner renders, then loadEmployees() clears the flag when the API
    // call resolves (success OR failure). Non-breaking — existing callers of
    // loadEmployees() still work; this just adds an explicit pull-to-refresh
    // entry point for when Room/Web sync has drifted and the technician needs
    // a manual re-fetch bypass.
    fun refresh() {
        _state.value = _state.value.copy(isRefreshing = true)
        loadEmployees()
    }

    companion object {
        /** In-memory cache shared across ViewModel instances for offline fallback. */
        private var cachedEmployees: List<EmployeeListItem>? = null
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EmployeeListScreen(
    onClockInOutClick: () -> Unit = {},
    onCreateClick: () -> Unit = {},
    // When flipped from false to true by the nav layer (after a successful
    // create), the list reloads and then acknowledges via [onRefreshConsumed].
    // Non-nav callers can ignore both params.
    refreshTrigger: Boolean = false,
    onRefreshConsumed: () -> Unit = {},
    viewModel: EmployeeListViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

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
                        Icon(
                            Icons.Default.AccessTime,
                            contentDescription = "Clock In/Out",
                        )
                    }
                    IconButton(onClick = { viewModel.loadEmployees() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
                    }
                },
            )
        },
        // Admin-only FAB. We hide it for non-admin users because the backend
        // route (POST /settings/users) enforces the same gate with
        // adminOnly — this is a UX signal, not a security boundary.
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
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                )
            }
            state.error != null && state.employees.isEmpty() -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    ErrorState(
                        message = state.error ?: "Failed to load employees",
                        onRetry = { viewModel.loadEmployees() },
                    )
                }
            }
            state.employees.isEmpty() -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    EmptyState(
                        icon = Icons.Default.Group,
                        title = "No employees",
                        subtitle = "No employee accounts found.",
                    )
                }
            }
            else -> {
                // D5-7: wrap employee list in PullToRefreshBox so a technician
                // can force a server re-fetch when the cached list is stale,
                // without restarting the app.
                PullToRefreshBox(
                    isRefreshing = state.isRefreshing,
                    onRefresh = { viewModel.refresh() },
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                ) {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        // CROSS16-ext: bottom inset so the last row can scroll
                        // above the bottom-nav / gesture area.
                        contentPadding = PaddingValues(top = 8.dp, bottom = 80.dp),
                    ) {
                        // Offline banner when showing cached data
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
                        items(state.employees, key = { it.id }) { employee ->
                            EmployeeRow(employee = employee)
                            BrandListItemDivider()
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun EmployeeRow(employee: EmployeeListItem) {
    val isActive = employee.isActive == 1
    val isClockedIn = employee.isClockedIn == true

    BrandListItem(
        leading = {
            // CROSS44: employee avatar now uses an initial-circle (first-name
            // first-letter) to match the Customer list row pattern and make
            // each row visually scannable instead of a sea of identical Person
            // icons. Falls back to person-glyph when no name data is present.
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
                        // decorative — fallback avatar glyph inside an avatar Box; sibling name Text in the parent Row carries the announcement
                        contentDescription = null,
                        modifier = Modifier.size(20.dp),
                        tint = MaterialTheme.colorScheme.onPrimaryContainer,
                    )
                }
                // Clock-in status dot
                Box(
                    modifier = Modifier
                        .size(10.dp)
                        .align(Alignment.BottomEnd)
                        .background(
                            color = if (isClockedIn) SuccessGreen
                            else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
                            shape = CircleShape,
                        )
                        .border(
                            width = 1.5.dp,
                            color = MaterialTheme.colorScheme.surface,
                            shape = CircleShape,
                        ),
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
                if (isClockedIn) {
                    Text(
                        "Clocked in",
                        style = MaterialTheme.typography.labelSmall,
                        color = SuccessGreen,
                    )
                }
            }
        },
        support = {
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                // Role chip: teal text on surface2 (surfaceVariant) bg
                Surface(
                    shape = MaterialTheme.shapes.small,
                    color = MaterialTheme.colorScheme.surfaceVariant,
                ) {
                    // CROSS40: use `uppercase()` (String) to match every other role
                    // display site (SettingsScreen, ProfileScreen, EmployeeCreateScreen)
                    // so locales where `uppercaseChar()` diverges (e.g. Turkish i/İ)
                    // can't drift between screens.
                    Text(
                        text = (employee.role ?: "user").replaceFirstChar { it.uppercase() },
                        modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.secondary, // teal
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
            // Active / inactive status badge
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
