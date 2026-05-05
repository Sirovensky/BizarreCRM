package com.bizarreelectronics.crm.ui.screens.employees

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.SettingsApi
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/** System role options the server accepts (VALID_ROLES in settings.routes.ts). */
private val SYSTEM_ROLES = listOf("technician", "cashier", "manager", "admin")

data class AssignRoleUiState(
    val employeeId: Long = 0L,
    val currentRole: String = "",
    val selectedRole: String = "",
    val isSaving: Boolean = false,
    val saved: Boolean = false,
    val error: String? = null,
)

@HiltViewModel
class AssignRoleViewModel @Inject constructor(
    private val settingsApi: SettingsApi,
    savedStateHandle: SavedStateHandle,
) : ViewModel() {

    private val employeeId: Long = checkNotNull(savedStateHandle["id"])
    private val currentRole: String = savedStateHandle.get<String>("role") ?: "technician"

    private val _state = MutableStateFlow(
        AssignRoleUiState(
            employeeId = employeeId,
            currentRole = currentRole,
            selectedRole = currentRole,
        ),
    )
    val state = _state.asStateFlow()

    fun selectRole(role: String) {
        _state.value = _state.value.copy(selectedRole = role)
    }

    fun save() {
        val role = _state.value.selectedRole
        viewModelScope.launch {
            _state.value = _state.value.copy(isSaving = true, error = null)
            runCatching {
                settingsApi.updateEmployee(employeeId, mapOf("role" to role))
            }
                .onSuccess {
                    _state.value = _state.value.copy(isSaving = false, saved = true, currentRole = role)
                }
                .onFailure { t ->
                    _state.value = _state.value.copy(
                        isSaving = false,
                        error = t.message ?: "Failed to assign role",
                    )
                }
        }
    }

    fun clearError() { _state.value = _state.value.copy(error = null) }
}

// ─── Screen ──────────────────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AssignRoleScreen(
    onBack: () -> Unit,
    viewModel: AssignRoleViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHost = remember { SnackbarHostState() }

    LaunchedEffect(state.error) {
        val msg = state.error ?: return@LaunchedEffect
        snackbarHost.showSnackbar(msg)
        viewModel.clearError()
    }

    LaunchedEffect(state.saved) {
        if (state.saved) onBack()
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHost) },
        topBar = {
            BrandTopAppBar(
                title = "Assign Role",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    if (state.isSaving) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(24.dp),
                            strokeWidth = 2.dp,
                        )
                        Spacer(Modifier.width(16.dp))
                    } else {
                        TextButton(
                            onClick = { viewModel.save() },
                            enabled = state.selectedRole != state.currentRole,
                        ) { Text("Save") }
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                "Select a system role for this employee.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(4.dp))
            LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                items(SYSTEM_ROLES) { role ->
                    RoleOption(
                        role = role,
                        selected = state.selectedRole == role,
                        isCurrent = state.currentRole == role,
                        onSelect = { viewModel.selectRole(role) },
                    )
                }
            }
        }
    }
}

@Composable
private fun RoleOption(
    role: String,
    selected: Boolean,
    isCurrent: Boolean,
    onSelect: () -> Unit,
) {
    OutlinedCard(
        modifier = Modifier.fillMaxWidth(),
        onClick = onSelect,
        colors = if (selected) CardDefaults.outlinedCardColors(
            containerColor = MaterialTheme.colorScheme.primaryContainer,
        ) else CardDefaults.outlinedCardColors(),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Column {
                Text(
                    text = role.replaceFirstChar { it.uppercase() },
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                )
                if (isCurrent) {
                    Text(
                        "Current role",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
            }
            if (selected) {
                RadioButton(selected = true, onClick = null)
            } else {
                RadioButton(selected = false, onClick = onSelect)
            }
        }
    }
}
