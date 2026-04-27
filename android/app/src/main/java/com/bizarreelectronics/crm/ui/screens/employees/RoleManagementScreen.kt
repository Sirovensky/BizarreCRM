package com.bizarreelectronics.crm.ui.screens.employees

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.ManageAccounts
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.CreateRoleBody
import com.bizarreelectronics.crm.data.remote.api.CustomRoleDto
import com.bizarreelectronics.crm.data.remote.api.RolesApi
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

// ── State ─────────────────────────────────────────────────────────────────────

data class RoleManagementUiState(
    val roles: List<CustomRoleDto> = emptyList(),
    val isLoading: Boolean = true,
    val error: String? = null,
    val actionMessage: String? = null,
    val showCreateDialog: Boolean = false,
    val pendingDeleteId: Long? = null,
)

// ── ViewModel ─────────────────────────────────────────────────────────────────

/**
 * §14.4 — Custom role management.
 * Uses GET /roles, POST /roles, DELETE /roles/:id (roles.routes.ts).
 * Admin-only — 403 is surfaced as a snackbar.
 */
@HiltViewModel
class RoleManagementViewModel @Inject constructor(
    private val rolesApi: RolesApi,
) : ViewModel() {

    private val _state = MutableStateFlow(RoleManagementUiState())
    val state = _state.asStateFlow()

    init { loadRoles() }

    fun loadRoles() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                val response = rolesApi.getRoles()
                _state.value = _state.value.copy(
                    isLoading = false,
                    roles = response.data ?: emptyList(),
                )
            } catch (e: retrofit2.HttpException) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = when (e.code()) {
                        403 -> "Admin access required to manage roles"
                        404 -> "Custom roles not available on this server"
                        else -> "Failed to load roles (${e.code()})"
                    },
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = e.message ?: "Failed to load roles",
                )
            }
        }
    }

    fun showCreateDialog() {
        _state.value = _state.value.copy(showCreateDialog = true)
    }

    fun dismissCreateDialog() {
        _state.value = _state.value.copy(showCreateDialog = false)
    }

    fun createRole(name: String, description: String) {
        if (name.isBlank()) return
        viewModelScope.launch {
            _state.value = _state.value.copy(showCreateDialog = false)
            runCatching {
                rolesApi.createRole(CreateRoleBody(name = name.trim().lowercase(), description = description.ifBlank { null }))
            }
                .onSuccess {
                    _state.value = _state.value.copy(actionMessage = "Role '${name.lowercase()}' created")
                    loadRoles()
                }
                .onFailure { t ->
                    val msg = if (t is retrofit2.HttpException && t.code() == 409) {
                        "Role '${name.lowercase()}' already exists"
                    } else {
                        t.message ?: "Failed to create role"
                    }
                    _state.value = _state.value.copy(actionMessage = msg)
                }
        }
    }

    fun confirmDelete(roleId: Long) {
        _state.value = _state.value.copy(pendingDeleteId = roleId)
    }

    fun dismissDelete() {
        _state.value = _state.value.copy(pendingDeleteId = null)
    }

    fun deleteRole() {
        val id = _state.value.pendingDeleteId ?: return
        viewModelScope.launch {
            _state.value = _state.value.copy(pendingDeleteId = null)
            runCatching { rolesApi.deleteRole(id) }
                .onSuccess {
                    _state.value = _state.value.copy(actionMessage = "Role deleted")
                    loadRoles()
                }
                .onFailure {
                    _state.value = _state.value.copy(actionMessage = it.message ?: "Failed to delete role")
                }
        }
    }

    fun clearActionMessage() {
        _state.value = _state.value.copy(actionMessage = null)
    }
}

// ── Screen ────────────────────────────────────────────────────────────────────

@Composable
fun RoleManagementScreen(
    onBack: () -> Unit,
    viewModel: RoleManagementViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(state.actionMessage) {
        state.actionMessage?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearActionMessage()
        }
    }

    // Delete confirm dialog
    if (state.pendingDeleteId != null) {
        AlertDialog(
            onDismissRequest = { viewModel.dismissDelete() },
            title = { Text("Delete role?") },
            text = { Text("This role will be permanently removed. Users assigned this role will not be affected immediately.") },
            confirmButton = {
                TextButton(onClick = { viewModel.deleteRole() }) {
                    Text("Delete", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { viewModel.dismissDelete() }) { Text("Cancel") }
            },
        )
    }

    // Create role dialog
    if (state.showCreateDialog) {
        CreateRoleDialog(
            onDismiss = { viewModel.dismissCreateDialog() },
            onConfirm = { name, desc -> viewModel.createRole(name, desc) },
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            BrandTopAppBar(
                title = "Role Management",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
        floatingActionButton = {
            FloatingActionButton(onClick = { viewModel.showCreateDialog() }) {
                Icon(Icons.Default.Add, contentDescription = "Create role")
            }
        },
    ) { padding ->
        when {
            state.isLoading -> Box(
                Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center,
            ) { CircularProgressIndicator() }

            state.error != null && state.roles.isEmpty() -> Box(
                Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center,
            ) {
                ErrorState(message = state.error!!, onRetry = { viewModel.loadRoles() })
            }

            state.roles.isEmpty() -> Box(
                Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center,
            ) {
                EmptyState(
                    icon = Icons.Default.ManageAccounts,
                    title = "No custom roles",
                    subtitle = "Tap + to create your first custom role.",
                )
            }

            else -> LazyColumn(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentPadding = PaddingValues(bottom = 80.dp),
            ) {
                items(state.roles, key = { it.id }) { role ->
                    RoleRow(
                        role = role,
                        onDelete = { viewModel.confirmDelete(role.id) },
                    )
                    HorizontalDivider()
                }
            }
        }
    }
}

@Composable
private fun RoleRow(role: CustomRoleDto, onDelete: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                role.name.replaceFirstChar { it.uppercase() },
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
            )
            if (!role.description.isNullOrBlank()) {
                Text(
                    role.description,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        if (role.isActive == 1) {
            Text(
                "Active",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.secondary,
            )
        }
        IconButton(onClick = onDelete, modifier = Modifier.size(36.dp)) {
            Icon(
                Icons.Default.Delete,
                contentDescription = "Delete ${role.name}",
                modifier = Modifier.size(18.dp),
                tint = MaterialTheme.colorScheme.error,
            )
        }
    }
}

@Composable
private fun CreateRoleDialog(
    onDismiss: () -> Unit,
    onConfirm: (name: String, description: String) -> Unit,
) {
    var name by remember { mutableStateOf("") }
    var description by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Create Role") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("Role name *") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    supportingText = {
                        Text(
                            "Lowercase, no spaces (e.g. lead-tech)",
                            style = MaterialTheme.typography.labelSmall,
                        )
                    },
                )
                OutlinedTextField(
                    value = description,
                    onValueChange = { description = it },
                    label = { Text("Description (optional)") },
                    maxLines = 2,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onConfirm(name, description) },
                enabled = name.isNotBlank(),
            ) { Text("Create") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}
