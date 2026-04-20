package com.bizarreelectronics.crm.ui.screens.employees

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Badge
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.SettingsApi
import com.bizarreelectronics.crm.data.remote.dto.EmployeeListItem
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.theme.SuccessGreen
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * §14.2 Employee detail — read-only profile screen.
 *
 * Pulls from `GET /employees` (no per-id endpoint yet) and filters to the
 * `employeeId` from nav args. Shows avatar, name, role, email, active /
 * clocked-in / has-PIN badges. Editing + Reset PIN + Toggle active are
 * deferred until server endpoints land — this screen exists so the list
 * row tap has somewhere to go (the audit explicitly flagged "tapping
 * employee row goes nowhere").
 */
data class EmployeeDetailUiState(
    val employee: EmployeeListItem? = null,
    val isLoading: Boolean = true,
    val error: String? = null,
)

@HiltViewModel
class EmployeeDetailViewModel @Inject constructor(
    private val settingsApi: SettingsApi,
    savedStateHandle: SavedStateHandle,
) : ViewModel() {

    private val employeeId: Long = checkNotNull(savedStateHandle["id"]) {
        "EmployeeDetailViewModel requires an `id` nav arg"
    }

    private val _state = MutableStateFlow(EmployeeDetailUiState())
    val state = _state.asStateFlow()

    init { load() }

    fun load() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                val response = settingsApi.getEmployees()
                val match = response.data?.firstOrNull { it.id == employeeId }
                _state.value = if (match == null) {
                    _state.value.copy(isLoading = false, error = "Employee not found")
                } else {
                    _state.value.copy(isLoading = false, employee = match, error = null)
                }
            } catch (t: Throwable) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = t.message ?: "Failed to load employee",
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EmployeeDetailScreen(
    onBack: () -> Unit,
    viewModel: EmployeeDetailViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text("Employee") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        when {
            state.isLoading -> {
                Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                    Text("Loading…", style = MaterialTheme.typography.bodyMedium)
                }
            }
            state.employee == null -> {
                Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                    EmptyState(
                        icon = Icons.Default.Person,
                        title = "Not found",
                        subtitle = state.error ?: "We couldn't find that employee.",
                    )
                }
            }
            else -> EmployeeDetailBody(employee = state.employee!!, padding = padding)
        }
    }
}

@Composable
private fun EmployeeDetailBody(employee: EmployeeListItem, padding: androidx.compose.foundation.layout.PaddingValues) {
    val isActive = employee.isActive == 1
    val isClockedIn = employee.isClockedIn == true
    val hasPin = employee.hasPin == 1
    val displayName = listOfNotNull(employee.firstName, employee.lastName)
        .joinToString(" ")
        .ifBlank { employee.username ?: "Unknown" }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item {
            // Header card — large avatar + name + role.
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(20.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    val initial = (employee.firstName?.firstOrNull()
                        ?: employee.username?.firstOrNull())
                        ?.uppercase()
                        ?.toString()
                        .orEmpty()
                    Box(
                        modifier = Modifier
                            .size(72.dp)
                            .background(
                                color = MaterialTheme.colorScheme.primaryContainer,
                                shape = CircleShape,
                            ),
                        contentAlignment = Alignment.Center,
                    ) {
                        if (initial.isNotBlank()) {
                            Text(
                                text = initial,
                                style = MaterialTheme.typography.headlineMedium,
                                fontWeight = FontWeight.SemiBold,
                                color = MaterialTheme.colorScheme.onPrimaryContainer,
                            )
                        } else {
                            Icon(
                                Icons.Default.Person,
                                contentDescription = null,
                                modifier = Modifier.size(36.dp),
                                tint = MaterialTheme.colorScheme.onPrimaryContainer,
                            )
                        }
                    }
                    Text(
                        text = displayName,
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.SemiBold,
                    )
                    employee.role?.let {
                        Text(
                            text = it.replaceFirstChar { c -> c.uppercase() },
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        StatusChip(
                            label = if (isActive) "Active" else "Inactive",
                            colored = isActive,
                        )
                        if (isClockedIn) {
                            StatusChip(label = "Clocked in", colored = true, color = SuccessGreen)
                        }
                        if (hasPin) {
                            StatusChip(label = "PIN set", colored = true)
                        }
                    }
                }
            }
        }

        item {
            // Identity / contact card.
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("Contact", style = MaterialTheme.typography.titleSmall)
                    DetailRow(icon = Icons.Default.Person, label = "Username", value = employee.username ?: "—")
                    DetailRow(icon = Icons.Default.Email, label = "Email", value = employee.email ?: "—")
                    DetailRow(icon = Icons.Default.Badge, label = "Role", value = employee.role ?: "—")
                }
            }
        }

        item {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("Account", style = MaterialTheme.typography.titleSmall)
                    DetailRow(
                        icon = Icons.Default.Lock,
                        label = "PIN",
                        value = if (hasPin) "Configured" else "Not set",
                    )
                    DetailRow(
                        icon = Icons.Default.Schedule,
                        label = "Created",
                        value = employee.createdAt ?: "—",
                    )
                    DetailRow(
                        icon = Icons.Default.Schedule,
                        label = "Updated",
                        value = employee.updatedAt ?: "—",
                    )
                }
            }
        }

        item {
            Spacer(Modifier.height(16.dp))
            Text(
                text = "Edit / Reset PIN / Deactivate land here once the server " +
                    "exposes per-employee endpoints (§14.2 follow-up).",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 4.dp),
            )
        }
    }
}

@Composable
private fun DetailRow(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Icon(
            icon,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(20.dp),
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = label,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                text = value,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}

@Composable
private fun StatusChip(
    label: String,
    colored: Boolean,
    color: androidx.compose.ui.graphics.Color = MaterialTheme.colorScheme.primary,
) {
    AssistChip(
        onClick = {},
        label = { Text(label, style = MaterialTheme.typography.labelMedium) },
        colors = if (colored) {
            AssistChipDefaults.assistChipColors(
                containerColor = color.copy(alpha = 0.18f),
                labelColor = color,
            )
        } else {
            AssistChipDefaults.assistChipColors()
        },
    )
}
