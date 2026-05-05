package com.bizarreelectronics.crm.ui.screens.employees

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.ManageAccounts
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.CreateRoleBody
import com.bizarreelectronics.crm.data.remote.api.RolesApi
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

// ─── Data model ──────────────────────────────────────────────────────────────

data class CustomRole(
    val id: Long,
    val name: String,
    val description: String,
)

data class CustomRolesUiState(
    val roles: List<CustomRole> = emptyList(),
    val isLoading: Boolean = true,
    val error: String? = null,
    val serverUnsupported: Boolean = false,
    val pendingDeleteRole: CustomRole? = null,
    val showCreateDialog: Boolean = false,
    val snackMessage: String? = null,
)

// ─── ViewModel ───────────────────────────────────────────────────────────────

@HiltViewModel
class CustomRolesViewModel @Inject constructor(
    private val rolesApi: RolesApi,
) : ViewModel() {

    private val _state = MutableStateFlow(CustomRolesUiState())
    val state = _state.asStateFlow()

    init { load() }

    fun load() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = _state.value.roles.isEmpty(), error = null)
            runCatching { rolesApi.getRoles() }
                .onSuccess { resp ->
                    val parsed = parseRoles(resp.data)
                    _state.value = _state.value.copy(
                        isLoading = false,
                        roles = parsed,
                        serverUnsupported = false,
                        error = null,
                    )
                }
                .onFailure { t ->
                    val is404 = t is retrofit2.HttpException && t.code() == 404
                    _state.value = _state.value.copy(
                        isLoading = false,
                        serverUnsupported = is404,
                        error = if (is404) null else (t.message ?: "Failed to load roles"),
                    )
                }
        }
    }

    fun showCreate() { _state.value = _state.value.copy(showCreateDialog = true) }
    fun dismissCreate() { _state.value = _state.value.copy(showCreateDialog = false) }

    fun createRole(name: String, description: String) {
        viewModelScope.launch {
            val body = CreateRoleBody(
                name = name,
                description = description.takeIf { it.isNotBlank() },
            )
            runCatching { rolesApi.createRole(body) }
                .onSuccess {
                    _state.value = _state.value.copy(
                        showCreateDialog = false,
                        snackMessage = "Role \"$name\" created",
                    )
                    load()
                }
                .onFailure { t ->
                    _state.value = _state.value.copy(snackMessage = t.message ?: "Failed to create role")
                }
        }
    }

    fun requestDelete(role: CustomRole) { _state.value = _state.value.copy(pendingDeleteRole = role) }
    fun cancelDelete() { _state.value = _state.value.copy(pendingDeleteRole = null) }

    fun confirmDelete() {
        val role = _state.value.pendingDeleteRole ?: return
        _state.value = _state.value.copy(pendingDeleteRole = null)
        viewModelScope.launch {
            runCatching { rolesApi.deleteRole(role.id) }
                .onSuccess {
                    _state.value = _state.value.copy(snackMessage = "Role deleted")
                    load()
                }
                .onFailure { _state.value = _state.value.copy(snackMessage = "Failed to delete role") }
        }
    }

    fun clearSnack() { _state.value = _state.value.copy(snackMessage = null) }

    @Suppress("UNCHECKED_CAST")
    private fun parseRoles(data: Any?): List<CustomRole> {
        val list = when (data) {
            is List<*> -> data
            is Map<*, *> -> (data["roles"] as? List<*>) ?: return emptyList()
            else -> return emptyList()
        }
        return list.mapNotNull { raw ->
            val m = raw as? Map<*, *> ?: return@mapNotNull null
            CustomRole(
                id = (m["id"] as? Number)?.toLong() ?: return@mapNotNull null,
                name = m["name"] as? String ?: return@mapNotNull null,
                description = m["description"] as? String ?: "",
            )
        }
    }
}

// ─── Screen ──────────────────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CustomRolesScreen(
    onBack: () -> Unit,
    /** §49 — Navigate to the permission matrix for [roleId]. */
    onEditPermissions: ((roleId: Long) -> Unit)? = null,
    viewModel: CustomRolesViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHost = remember { SnackbarHostState() }

    LaunchedEffect(state.snackMessage) {
        val msg = state.snackMessage ?: return@LaunchedEffect
        snackbarHost.showSnackbar(msg)
        viewModel.clearSnack()
    }

    // ── Delete confirm dialog ────────────────────────────────────────────────
    state.pendingDeleteRole?.let { role ->
        AlertDialog(
            onDismissRequest = { viewModel.cancelDelete() },
            title = { Text("Delete role?") },
            text = {
                Text(
                    "Delete the \"${role.name}\" role? Any employees assigned this custom role " +
                        "will retain their system role assignment.",
                )
            },
            confirmButton = {
                TextButton(onClick = { viewModel.confirmDelete() }) {
                    Text("Delete", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { viewModel.cancelDelete() }) { Text("Cancel") }
            },
        )
    }

    // ── Create dialog ────────────────────────────────────────────────────────
    if (state.showCreateDialog) {
        CreateRoleDialog(
            onDismiss = { viewModel.dismissCreate() },
            onConfirm = { name, desc -> viewModel.createRole(name, desc) },
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHost) },
        topBar = {
            BrandTopAppBar(
                title = "Custom Roles",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
        floatingActionButton = {
            FloatingActionButton(onClick = { viewModel.showCreate() }) {
                Icon(Icons.Default.Add, contentDescription = "Create role")
            }
        },
    ) { padding ->
        when {
            state.isLoading -> Box(
                Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center,
            ) { CircularProgressIndicator() }

            state.serverUnsupported -> Box(
                Modifier.fillMaxSize().padding(padding),
            ) {
                EmptyState(
                    icon = Icons.Default.ManageAccounts,
                    title = "Custom roles not available",
                    subtitle = "Custom role management is not configured on this server.",
                )
            }

            state.error != null -> Box(
                Modifier.fillMaxSize().padding(padding),
            ) {
                ErrorState(
                    message = state.error!!,
                    onRetry = { viewModel.load() },
                )
            }

            state.roles.isEmpty() -> Box(
                Modifier.fillMaxSize().padding(padding),
            ) {
                EmptyState(
                    icon = Icons.Default.ManageAccounts,
                    title = "No custom roles",
                    subtitle = "Tap + to create a custom role.",
                )
            }

            else -> LazyColumn(
                contentPadding = PaddingValues(
                    start = 16.dp, end = 16.dp,
                    top = padding.calculateTopPadding() + 8.dp,
                    bottom = padding.calculateBottomPadding() + 8.dp,
                ),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(state.roles, key = { it.id }) { role ->
                    CustomRoleCard(
                        role = role,
                        onDelete = { viewModel.requestDelete(role) },
                        onEditPermissions = onEditPermissions?.let { cb -> { cb(role.id) } },
                    )
                }
            }
        }
    }
}

// ─── Sub-components ──────────────────────────────────────────────────────────

@Composable
private fun CustomRoleCard(
    role: CustomRole,
    onDelete: () -> Unit,
    onEditPermissions: (() -> Unit)? = null,
) {
    OutlinedCard(
        modifier = Modifier.fillMaxWidth(),
        onClick = onEditPermissions ?: {},
    ) {
        ListItem(
            headlineContent = {
                Text(role.name, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
            },
            supportingContent = {
                if (role.description.isNotBlank()) {
                    Text(role.description, style = MaterialTheme.typography.bodySmall)
                } else if (onEditPermissions != null) {
                    Text(
                        "Tap to edit permissions",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            },
            trailingContent = {
                IconButton(onClick = onDelete) {
                    Icon(Icons.Default.Delete, contentDescription = "Delete ${role.name} role")
                }
            },
        )
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
        title = { Text("New Custom Role") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("Role name *") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = description,
                    onValueChange = { description = it },
                    label = { Text("Description (optional)") },
                    modifier = Modifier.fillMaxWidth(),
                    maxLines = 2,
                )
            }
        },
        confirmButton = {
            FilledTonalButton(
                onClick = { if (name.isNotBlank()) onConfirm(name.trim(), description.trim()) },
                enabled = name.isNotBlank(),
            ) { Text("Create") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}
