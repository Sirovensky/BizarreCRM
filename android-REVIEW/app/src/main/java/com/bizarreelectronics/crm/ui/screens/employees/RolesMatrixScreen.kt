package com.bizarreelectronics.crm.ui.screens.employees

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Save
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.PermissionEntryDto
import com.bizarreelectronics.crm.data.remote.api.RolesApi
import com.bizarreelectronics.crm.data.remote.api.UpdatePermissionsBody
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

// ── Capability categories (§49.1) ─────────────────────────────────────────────

/**
 * Maps a server permission key prefix to its display category.
 * Order here controls display order in the matrix.
 */
private val CATEGORY_ORDER = listOf(
    "tickets"    to "Tickets",
    "customers"  to "Customers",
    "inventory"  to "Inventory",
    "invoices"   to "Invoices",
    "refunds"    to "Invoices",      // grouped under Invoices
    "deposits"   to "Invoices",
    "gift_cards" to "Invoices",
    "pos"        to "POS",
    "leads"      to "Tickets",       // grouped under Tickets
    "estimates"  to "Tickets",
    "reports"    to "Reports",
    "sms"        to "Communications",
    "email"      to "Communications",
    "employees"  to "Team",
    "users"      to "Settings",
    "settings"   to "Settings",
)

private fun categoryFor(key: String): String {
    val prefix = key.substringBefore(".")
    return CATEGORY_ORDER.firstOrNull { it.first == prefix }?.second ?: "Other"
}

private val CATEGORY_DISPLAY_ORDER = listOf(
    "Tickets", "Customers", "Inventory", "Invoices", "POS",
    "Reports", "Communications", "Team", "Settings", "Other",
)

/** Human-readable label for a permission key (e.g. "tickets.create" → "Create"). */
private fun labelFor(key: String): String {
    val action = key.substringAfter(".")
    return action.replace("_", " ").split(" ").joinToString(" ") { w ->
        w.replaceFirstChar { it.uppercase() }
    }
}

// ── Constants ─────────────────────────────────────────────────────────────────

private val SYSTEM_ROLES_MATRIX = setOf("owner", "admin", "manager", "technician", "cashier")

// ── State ─────────────────────────────────────────────────────────────────────

data class MatrixUiState(
    val roleId: Long = 0,
    val roleName: String = "",
    val isSystemRole: Boolean = false,
    /** Ordered list of (category, permissionKey) pairs. */
    val entries: List<PermissionEntryDto> = emptyList(),
    /** Live toggle state: key → allowed. Starts as copy of server state. */
    val pending: Map<String, Boolean> = emptyMap(),
    val isDirty: Boolean = false,
    val isLoading: Boolean = true,
    val isSaving: Boolean = false,
    val error: String? = null,
    val actionMessage: String? = null,
)

// ── ViewModel ─────────────────────────────────────────────────────────────────

/**
 * §49 — Roles Matrix Editor ViewModel.
 *
 * Loads GET /roles/:id/permissions, surfaces it as a category-grouped list,
 * tracks per-key toggles, and persists via PUT /roles/:id/permissions (full
 * batch, server applies atomically).
 *
 * System roles: server enforces immutability on admin.full for "admin" role;
 * client shows locked UI for all system-role keys on system roles.
 */
@HiltViewModel
class RolesMatrixViewModel @Inject constructor(
    private val rolesApi: RolesApi,
    savedStateHandle: SavedStateHandle,
) : ViewModel() {

    private val roleId: Long = checkNotNull(savedStateHandle["roleId"])
    private val roleName: String = checkNotNull(savedStateHandle["roleName"])

    private val _state = MutableStateFlow(
        MatrixUiState(roleId = roleId, roleName = roleName)
    )
    val state = _state.asStateFlow()

    init { load() }

    fun load() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                val response = rolesApi.getRolePermissions(roleId)
                val matrix = response.data?.matrix ?: emptyList()
                val pendingMap = matrix.associate { it.key to it.allowed }
                _state.value = _state.value.copy(
                    isLoading = false,
                    isSystemRole = roleName.lowercase() in SYSTEM_ROLES_MATRIX,
                    entries = matrix,
                    pending = pendingMap,
                    isDirty = false,
                )
            } catch (e: retrofit2.HttpException) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = when (e.code()) {
                        403 -> "Admin access required"
                        404 -> "Role not found"
                        else -> "Failed to load permissions (${e.code()})"
                    },
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = e.message ?: "Failed to load permissions",
                )
            }
        }
    }

    fun toggle(key: String, newValue: Boolean) {
        val cur = _state.value
        // §49.3 — system roles: allow toggling (user can add extras); server
        // enforces the admin.full guard on its side.
        val updated = cur.pending.toMutableMap().also { it[key] = newValue }
        _state.value = cur.copy(pending = updated, isDirty = true)
    }

    fun save() {
        val cur = _state.value
        if (!cur.isDirty || cur.isSaving) return
        viewModelScope.launch {
            _state.value = cur.copy(isSaving = true)
            val updates = cur.pending.map { (key, allowed) ->
                PermissionEntryDto(key = key, allowed = allowed)
            }
            runCatching {
                rolesApi.updateRolePermissions(
                    roleId = roleId,
                    body = UpdatePermissionsBody(updates = updates),
                )
            }
                .onSuccess {
                    _state.value = _state.value.copy(
                        isSaving = false,
                        isDirty = false,
                        actionMessage = "Permissions saved",
                    )
                }
                .onFailure { t ->
                    val msg = if (t is retrofit2.HttpException) {
                        when (t.code()) {
                            400 -> "Bad request — check permission keys"
                            403 -> "Admin access required"
                            else -> "Save failed (${t.code()})"
                        }
                    } else {
                        t.message ?: "Save failed"
                    }
                    _state.value = _state.value.copy(isSaving = false, actionMessage = msg)
                }
        }
    }

    fun clearActionMessage() {
        _state.value = _state.value.copy(actionMessage = null)
    }
}

// ── Screen ────────────────────────────────────────────────────────────────────

/**
 * §49 — Roles Matrix Editor screen.
 *
 * Phone (compact width): per-role vertical list — each capability row has a
 * label + subtitle (category) + a Toggle Switch.
 *
 * Tablet/ChromeOS (medium/expanded width): full 2-D scrollable grid —
 * capability rows × role columns. Here the screen always shows a single role's
 * column because navigation delivers one roleId at a time; the grid-header
 * shows the role name above its toggle column.
 *
 * System roles (§49.3): base permissions are shown locked with a padlock icon;
 * toggles are disabled for system roles to prevent accidental breaks (server
 * enforces admin.full immutability anyway).
 *
 * Dirty state: a floating Save FAB becomes enabled when any toggle is changed.
 * Persists via PUT /roles/:id/permissions (atomic batch on server).
 */
@Composable
fun RolesMatrixScreen(
    roleId: Long,
    roleName: String,
    onBack: () -> Unit,
    viewModel: RolesMatrixViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(state.actionMessage) {
        state.actionMessage?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearActionMessage()
        }
    }

    // Derive category-grouped entries in display order
    val grouped: Map<String, List<PermissionEntryDto>> = state.entries
        .groupBy { categoryFor(it.key) }
        .let { raw ->
            val ordered = linkedMapOf<String, List<PermissionEntryDto>>()
            for (cat in CATEGORY_DISPLAY_ORDER) {
                raw[cat]?.let { ordered[cat] = it }
            }
            raw.keys.filter { it !in CATEGORY_DISPLAY_ORDER }.forEach { cat ->
                raw[cat]?.let { ordered[cat] = it }
            }
            ordered
        }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            BrandTopAppBar(
                title = "${roleName.replaceFirstChar { it.uppercase() }} — Permissions",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    if (state.isSaving) {
                        CircularProgressIndicator(
                            modifier = Modifier
                                .size(24.dp)
                                .padding(end = 8.dp),
                            strokeWidth = 2.dp,
                        )
                    } else if (state.isDirty) {
                        IconButton(onClick = { viewModel.save() }) {
                            Icon(Icons.Default.Save, contentDescription = "Save permissions")
                        }
                    }
                },
            )
        },
    ) { padding ->
        when {
            state.isLoading -> Box(
                Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center,
            ) { CircularProgressIndicator() }

            state.error != null && state.entries.isEmpty() -> Box(
                Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center,
            ) {
                ErrorState(message = state.error!!, onRetry = { viewModel.load() })
            }

            state.entries.isEmpty() -> Box(
                Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center,
            ) {
                EmptyState(
                    icon = Icons.Default.GridView,
                    title = "No permissions",
                    subtitle = "No permission keys found for this role.",
                    includeWave = true,
                )
            }

            else -> {
                // Phone layout: category-grouped vertical list with Switch per row
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentPadding = PaddingValues(bottom = 80.dp),
                ) {
                    // System role notice
                    if (state.isSystemRole) {
                        item(key = "__system_notice") {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 16.dp, vertical = 10.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                Icon(
                                    Icons.Default.Lock,
                                    contentDescription = null,
                                    modifier = Modifier.size(16.dp),
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                Text(
                                    "System role — base permissions are locked.",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                            HorizontalDivider()
                        }
                    }

                    grouped.forEach { (category, entries) ->
                        // Category header
                        item(key = "cat_$category") {
                            Text(
                                category,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 4.dp),
                                style = MaterialTheme.typography.labelMedium,
                                fontWeight = FontWeight.SemiBold,
                                color = MaterialTheme.colorScheme.secondary, // teal
                            )
                        }

                        items(entries, key = { it.key }) { entry ->
                            val isChecked = state.pending[entry.key] ?: entry.allowed
                            // §49.3: disable toggles for system roles (server enforces)
                            val isEnabled = !state.isSystemRole && !state.isSaving
                            PermissionToggleRow(
                                permKey = entry.key,
                                label = labelFor(entry.key),
                                isChecked = isChecked,
                                isEnabled = isEnabled,
                                isSystemRole = state.isSystemRole,
                                onToggle = { newVal -> viewModel.toggle(entry.key, newVal) },
                            )
                            HorizontalDivider(
                                color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
                            )
                        }
                    }

                    // Save button at bottom for discoverability
                    if (state.isDirty) {
                        item(key = "__save_btn") {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 24.dp, vertical = 16.dp),
                                contentAlignment = Alignment.Center,
                            ) {
                                Button(
                                    onClick = { viewModel.save() },
                                    enabled = !state.isSaving,
                                    modifier = Modifier.fillMaxWidth(),
                                ) {
                                    if (state.isSaving) {
                                        CircularProgressIndicator(
                                            modifier = Modifier.size(18.dp),
                                            strokeWidth = 2.dp,
                                            color = MaterialTheme.colorScheme.onPrimary,
                                        )
                                        Spacer(Modifier.width(8.dp))
                                    } else {
                                        Icon(
                                            Icons.Default.Save,
                                            contentDescription = null,
                                            modifier = Modifier.size(18.dp),
                                        )
                                        Spacer(Modifier.width(8.dp))
                                    }
                                    Text("Save permissions")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// ── Row composable ─────────────────────────────────────────────────────────────

@Composable
private fun PermissionToggleRow(
    permKey: String,
    label: String,
    isChecked: Boolean,
    isEnabled: Boolean,
    isSystemRole: Boolean,
    onToggle: (Boolean) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(
                    label,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                )
                // §49.3: padlock next to checked system permissions
                if (isSystemRole && isChecked) {
                    Icon(
                        Icons.Default.Lock,
                        contentDescription = "Base permission — locked for system role",
                        modifier = Modifier.size(11.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                    )
                }
            }
            Text(
                permKey,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Switch(
            checked = isChecked,
            onCheckedChange = onToggle,
            enabled = isEnabled,
        )
    }
}
