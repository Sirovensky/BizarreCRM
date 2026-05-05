package com.bizarreelectronics.crm.ui.screens.employees

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Save
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.data.remote.api.PermissionEntryDto
import com.bizarreelectronics.crm.data.remote.api.RolesApi
import com.bizarreelectronics.crm.data.remote.api.UpdatePermissionsBody
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ConfirmDialog
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.util.isMediumOrExpandedWidth
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

// ─── Constants ───────────────────────────────────────────────────────────────

/**
 * Built-in system roles whose permission matrix is display-only.
 * Server rejects any attempt to modify these from outside admin.full,
 * but we also disable toggles on the client for clarity.
 */
private val SYSTEM_ROLE_NAMES = setOf("admin", "manager", "technician", "cashier", "owner")

/**
 * §49.1 — Permission category groups derived from the key prefix.
 *
 * Order determines section order in the UI. Keys not matching any prefix
 * fall into the "Other" bucket at the end.
 */
private val CATEGORY_ORDER = listOf(
    "tickets"    to "Tickets",
    "customers"  to "Customers",
    "inventory"  to "Inventory",
    "invoices"   to "Invoices",
    "refunds"    to "Refunds",
    "deposits"   to "Deposits",
    "gift_cards" to "Gift Cards",
    "pos"        to "POS",
    "leads"      to "Leads",
    "estimates"  to "Estimates",
    "reports"    to "Reports",
    "sms"        to "SMS",
    "email"      to "Email",
    "employees"  to "Team",
    "settings"   to "Settings",
    "users"      to "Users",
    "admin"      to "Admin",
)

// ─── Data model ──────────────────────────────────────────────────────────────

/** One displayable permission row. */
data class PermissionRow(
    val key: String,
    val label: String,   // human-readable; derived from key suffix
    val allowed: Boolean,
)

/** Grouped section for the list/grid. */
data class PermissionCategory(
    val title: String,
    val rows: List<PermissionRow>,
)

data class PermissionMatrixUiState(
    val roleName: String = "",
    val isSystemRole: Boolean = false,
    val categories: List<PermissionCategory> = emptyList(),
    /** Working copy of currently toggled permissions (key → allowed). */
    val pending: Map<String, Boolean> = emptyMap(),
    val isLoading: Boolean = true,
    val isSaving: Boolean = false,
    val error: String? = null,
    val snackMessage: String? = null,
    val showResetConfirm: Boolean = false,
    val isDirty: Boolean = false,
)

// ─── ViewModel ───────────────────────────────────────────────────────────────

@HiltViewModel
class PermissionMatrixViewModel @Inject constructor(
    private val rolesApi: RolesApi,
    savedStateHandle: SavedStateHandle,
) : ViewModel() {

    private val roleId: Long = checkNotNull(savedStateHandle["roleId"])

    private val _state = MutableStateFlow(PermissionMatrixUiState())
    val state: StateFlow<PermissionMatrixUiState> = _state.asStateFlow()

    init { load() }

    fun load() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            runCatching { rolesApi.getRolePermissions(roleId) }
                .onSuccess { resp ->
                    val data = resp.data ?: run {
                        _state.value = _state.value.copy(
                            isLoading = false,
                            error = "Empty server response",
                        )
                        return@onSuccess
                    }
                    val role = data.role
                    val serverMatrix = data.matrix

                    val pending = serverMatrix.associate { it.key to it.allowed }
                    val categories = buildCategories(serverMatrix)

                    _state.value = _state.value.copy(
                        roleName = role.name,
                        isSystemRole = role.name in SYSTEM_ROLE_NAMES,
                        categories = categories,
                        pending = pending,
                        isLoading = false,
                        isDirty = false,
                    )
                }
                .onFailure { t ->
                    _state.value = _state.value.copy(
                        isLoading = false,
                        error = t.message ?: "Failed to load permissions",
                    )
                }
        }
    }

    fun toggle(key: String, allowed: Boolean) {
        if (_state.value.isSystemRole) return   // UI disables but guard anyway
        val updated = _state.value.pending + (key to allowed)
        _state.value = _state.value.copy(
            pending = updated,
            isDirty = true,
        )
    }

    fun requestReset() {
        _state.value = _state.value.copy(showResetConfirm = true)
    }

    fun cancelReset() {
        _state.value = _state.value.copy(showResetConfirm = false)
    }

    /**
     * §49.3 — "Reset to defaults" re-fetches the server's current matrix so
     * the in-progress pending map is discarded and the server defaults apply.
     * This avoids embedding the ROLE_PERMISSIONS table on the client.
     */
    fun confirmReset() {
        _state.value = _state.value.copy(showResetConfirm = false)
        load()
    }

    fun save() {
        val pending = _state.value.pending
        if (pending.isEmpty() || _state.value.isSaving) return
        val updates = pending.map { (k, v) -> PermissionEntryDto(key = k, allowed = v) }
        viewModelScope.launch {
            _state.value = _state.value.copy(isSaving = true, error = null)
            runCatching {
                rolesApi.updateRolePermissions(roleId, UpdatePermissionsBody(updates = updates))
            }
                .onSuccess {
                    _state.value = _state.value.copy(
                        isSaving = false,
                        isDirty = false,
                        snackMessage = "Permissions saved",
                    )
                }
                .onFailure { t ->
                    _state.value = _state.value.copy(
                        isSaving = false,
                        snackMessage = t.message ?: "Failed to save permissions",
                    )
                }
        }
    }

    fun clearSnack() {
        _state.value = _state.value.copy(snackMessage = null)
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private fun buildCategories(matrix: List<PermissionEntryDto>): List<PermissionCategory> {
        // Group by prefix (first segment of "prefix.action")
        val byPrefix: MutableMap<String, MutableList<PermissionRow>> = LinkedHashMap()
        matrix.forEach { entry ->
            val dot = entry.key.indexOf('.')
            val prefix = if (dot > 0) entry.key.substring(0, dot) else entry.key
            val suffix = if (dot > 0) entry.key.substring(dot + 1) else entry.key
            val label = suffix.replace('_', ' ')
                .split(' ')
                .joinToString(" ") { word -> word.replaceFirstChar { it.uppercase() } }
            byPrefix.getOrPut(prefix) { mutableListOf() }
                .add(PermissionRow(key = entry.key, label = label, allowed = entry.allowed))
        }

        // Emit in CATEGORY_ORDER, then any leftovers
        val result = mutableListOf<PermissionCategory>()
        for ((prefix, catLabel) in CATEGORY_ORDER) {
            val rows = byPrefix.remove(prefix) ?: continue
            result += PermissionCategory(title = catLabel, rows = rows)
        }
        if (byPrefix.isNotEmpty()) {
            val otherRows = byPrefix.values.flatten()
            result += PermissionCategory(title = "Other", rows = otherRows)
        }
        return result
    }
}

// ─── Screen ──────────────────────────────────────────────────────────────────

/**
 * §49 Roles Matrix Editor.
 *
 * Phone (compact width): single-column list; each permission is a [ListItem]
 * with a [Switch] on the trailing side, grouped under category [OutlinedCard]
 * section headers.
 *
 * Tablet/ChromeOS (medium/expanded width): 2-D grid — permission categories
 * in rows, checkboxes in columns per-role would require multi-role loading;
 * for MVP this screen is per-role, so the tablet layout shows a 2-column
 * grid of [OutlinedCard] tiles per category instead of a single column.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PermissionMatrixScreen(
    onBack: () -> Unit,
    viewModel: PermissionMatrixViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val isTablet = isMediumOrExpandedWidth()
    val snackbarHost = remember { SnackbarHostState() }

    LaunchedEffect(state.snackMessage) {
        val msg = state.snackMessage ?: return@LaunchedEffect
        snackbarHost.showSnackbar(msg)
        viewModel.clearSnack()
    }

    // ── Reset confirm dialog ─────────────────────────────────────────────────
    if (state.showResetConfirm) {
        ConfirmDialog(
            title = stringResource(R.string.perm_reset_title),
            message = stringResource(R.string.perm_reset_message),
            confirmLabel = stringResource(R.string.perm_reset_confirm),
            onConfirm = { viewModel.confirmReset() },
            onDismiss = { viewModel.cancelReset() },
            isDestructive = true,
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHost) },
        topBar = {
            BrandTopAppBar(
                title = if (state.roleName.isNotBlank())
                    "${state.roleName.replaceFirstChar { it.uppercase() }} — Permissions"
                else
                    stringResource(R.string.screen_permission_matrix),
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.cd_back),
                        )
                    }
                },
                actions = {
                    if (!state.isSystemRole) {
                        if (state.isSaving) {
                            CircularProgressIndicator(
                                modifier = Modifier
                                    .size(24.dp)
                                    .padding(end = 16.dp),
                                strokeWidth = 2.dp,
                            )
                        } else {
                            IconButton(
                                onClick = { viewModel.save() },
                                enabled = state.isDirty,
                            ) {
                                Icon(
                                    Icons.Default.Save,
                                    contentDescription = stringResource(R.string.perm_save_cd),
                                )
                            }
                        }
                    }
                },
            )
        },
    ) { padding ->
        when {
            state.isLoading -> Box(
                Modifier
                    .fillMaxSize()
                    .padding(padding),
                contentAlignment = Alignment.Center,
            ) { CircularProgressIndicator() }

            state.error != null -> Box(
                Modifier
                    .fillMaxSize()
                    .padding(padding),
            ) {
                ErrorState(message = state.error!!, onRetry = { viewModel.load() })
            }

            state.categories.isEmpty() -> Box(
                Modifier
                    .fillMaxSize()
                    .padding(padding),
            ) {
                EmptyState(
                    icon = Icons.Default.Lock,
                    title = stringResource(R.string.perm_empty_title),
                    subtitle = stringResource(R.string.perm_empty_subtitle),
                )
            }

            else -> Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
            ) {
                // System-role locked banner
                if (state.isSystemRole) {
                    Surface(
                        color = MaterialTheme.colorScheme.secondaryContainer,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Row(
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Icon(
                                Icons.Default.Lock,
                                contentDescription = null,
                                modifier = Modifier.size(18.dp),
                                tint = MaterialTheme.colorScheme.onSecondaryContainer,
                            )
                            Text(
                                stringResource(R.string.perm_system_locked),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSecondaryContainer,
                            )
                        }
                    }
                }

                // "Reset to defaults" action (custom roles only)
                if (!state.isSystemRole) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 4.dp),
                        horizontalArrangement = Arrangement.End,
                    ) {
                        FilledTonalButton(onClick = { viewModel.requestReset() }) {
                            Text(stringResource(R.string.perm_reset_action))
                        }
                    }
                }

                if (isTablet) {
                    TabletMatrixContent(
                        categories = state.categories,
                        pending = state.pending,
                        isSystemRole = state.isSystemRole,
                        onToggle = { key, allowed -> viewModel.toggle(key, allowed) },
                    )
                } else {
                    PhoneMatrixContent(
                        categories = state.categories,
                        pending = state.pending,
                        isSystemRole = state.isSystemRole,
                        onToggle = { key, allowed -> viewModel.toggle(key, allowed) },
                    )
                }
            }
        }
    }
}

// ─── Phone layout ─────────────────────────────────────────────────────────────

/**
 * §49.1 Phone — per-role vertical list; each permission is a [ListItem] with
 * a [Switch] on the trailing side, grouped under collapsible category headers.
 */
@Composable
private fun PhoneMatrixContent(
    categories: List<PermissionCategory>,
    pending: Map<String, Boolean>,
    isSystemRole: Boolean,
    onToggle: (String, Boolean) -> Unit,
) {
    LazyColumn(
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        categories.forEach { category ->
            item(key = "header_${category.title}") {
                Text(
                    category.title,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.padding(top = 8.dp, bottom = 2.dp),
                )
            }
            items(category.rows, key = { it.key }) { row ->
                val checked = pending[row.key] ?: row.allowed
                OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                    ListItem(
                        headlineContent = {
                            Text(
                                row.label,
                                style = MaterialTheme.typography.bodyMedium,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        },
                        supportingContent = {
                            Text(
                                row.key,
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        },
                        trailingContent = {
                            Switch(
                                checked = checked,
                                onCheckedChange = { if (!isSystemRole) onToggle(row.key, it) },
                                enabled = !isSystemRole,
                            )
                        },
                    )
                }
            }
        }
    }
}

// ─── Tablet layout ────────────────────────────────────────────────────────────

/**
 * §49.1 Tablet/ChromeOS — 2-column grid of [OutlinedCard] category sections.
 * Each section shows a compact list of permission rows with [Checkbox] controls
 * rather than full-width [Switch] rows, making better use of available width.
 */
@Composable
private fun TabletMatrixContent(
    categories: List<PermissionCategory>,
    pending: Map<String, Boolean>,
    isSystemRole: Boolean,
    onToggle: (String, Boolean) -> Unit,
) {
    // Use a scrollable column rather than LazyColumn so we can use a
    // FlowRow-style pair layout without nested lazy lists.
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Pair categories side-by-side
        val paired = categories.chunked(2)
        paired.forEach { pair ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                pair.forEach { category ->
                    OutlinedCard(modifier = Modifier.weight(1f)) {
                        Column(modifier = Modifier.padding(bottom = 8.dp)) {
                            Text(
                                category.title,
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.SemiBold,
                                color = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.padding(
                                    start = 16.dp, end = 16.dp, top = 12.dp, bottom = 4.dp,
                                ),
                            )
                            HorizontalDivider()
                            category.rows.forEach { row ->
                                val checked = pending[row.key] ?: row.allowed
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(horizontal = 12.dp, vertical = 4.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                ) {
                                    Text(
                                        row.label,
                                        style = MaterialTheme.typography.bodySmall,
                                        modifier = Modifier
                                            .weight(1f)
                                            .padding(end = 8.dp),
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                    Checkbox(
                                        checked = checked,
                                        onCheckedChange = { if (!isSystemRole) onToggle(row.key, it) },
                                        enabled = !isSystemRole,
                                    )
                                }
                            }
                        }
                    }
                }
                // Fill the last row if odd count
                if (pair.size == 1) {
                    Spacer(modifier = Modifier.weight(1f))
                }
            }
        }
    }
}
