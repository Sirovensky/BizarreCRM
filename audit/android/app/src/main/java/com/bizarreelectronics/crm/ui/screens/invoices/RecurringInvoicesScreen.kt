package com.bizarreelectronics.crm.ui.screens.invoices

/**
 * §SCAN-478 — Recurring Invoices list screen.
 *
 * Shows all recurring-invoice templates from GET /api/v1/recurring-invoices.
 * Status filter chips: All / Active / Paused / Cancelled.
 * Each row has an overflow menu with lifecycle actions (Pause / Resume / Cancel).
 *
 * All API calls are 404-tolerant: if the server returns 404, the screen shows
 * an empty state with a "Not available on this server" subtitle rather than
 * an error. Network errors show [ErrorState] with retry.
 *
 * Navigation entry point: InvoiceListScreen overflow menu → "Recurring Invoices".
 */

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.RecurringInvoicesApi
import com.bizarreelectronics.crm.data.remote.dto.RecurringInvoiceItem
import com.bizarreelectronics.crm.ui.components.WaveDivider
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.BrandStatusBadge
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import javax.inject.Inject

// ── ViewModel ─────────────────────────────────────────────────────────────────

data class RecurringInvoicesState(
    val templates: List<RecurringInvoiceItem> = emptyList(),
    val isLoading: Boolean = false,
    val isRefreshing: Boolean = false,
    /** null = all, "active", "paused", "cancelled" */
    val statusFilter: String? = null,
    val error: String? = null,
    /** true when the server returned 404 (endpoint not deployed on this build). */
    val notAvailable: Boolean = false,
    val actionMessage: String? = null,
)

@HiltViewModel
class RecurringInvoicesViewModel @Inject constructor(
    private val api: RecurringInvoicesApi,
) : ViewModel() {

    private val _state = MutableStateFlow(RecurringInvoicesState())
    val state: StateFlow<RecurringInvoicesState> = _state.asStateFlow()

    init {
        load(isRefresh = false)
    }

    fun load(isRefresh: Boolean = false) {
        viewModelScope.launch {
            _state.value = _state.value.copy(
                isLoading = !isRefresh,
                isRefreshing = isRefresh,
                error = null,
                notAvailable = false,
            )
            runCatching {
                api.listTemplates(status = _state.value.statusFilter)
            }.onSuccess { response ->
                _state.value = _state.value.copy(
                    templates = response.data?.templates ?: emptyList(),
                    isLoading = false,
                    isRefreshing = false,
                )
            }.onFailure { e ->
                val is404 = (e as? HttpException)?.code() == 404
                _state.value = _state.value.copy(
                    isLoading = false,
                    isRefreshing = false,
                    notAvailable = is404,
                    error = if (is404) null else (e.message ?: "Failed to load recurring invoices"),
                )
            }
        }
    }

    fun setStatusFilter(status: String?) {
        _state.value = _state.value.copy(statusFilter = status)
        load(isRefresh = false)
    }

    fun pause(id: Long) = lifecycleAction(id, "pause") { api.pauseTemplate(id) }
    fun resume(id: Long) = lifecycleAction(id, "resume") { api.resumeTemplate(id) }
    fun cancel(id: Long) = lifecycleAction(id, "cancel") { api.cancelTemplate(id) }

    private fun lifecycleAction(
        id: Long,
        action: String,
        call: suspend () -> Any,
    ) {
        viewModelScope.launch {
            runCatching { call() }
                .onSuccess {
                    _state.value = _state.value.copy(actionMessage = "Template ${action}d")
                    load(isRefresh = true)
                }
                .onFailure { e ->
                    val is404 = (e as? HttpException)?.code() == 404
                    _state.value = _state.value.copy(
                        actionMessage = if (is404) "Action not available on this server"
                        else (e.message ?: "Action failed"),
                    )
                }
        }
    }

    fun clearActionMessage() {
        _state.value = _state.value.copy(actionMessage = null)
    }
}

// ── Screen ───────────────────────────────────────────────────────────────────

private val STATUS_CHIPS = listOf(
    null to "All",
    "active" to "Active",
    "paused" to "Paused",
    "cancelled" to "Cancelled",
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RecurringInvoicesScreen(
    onBack: () -> Unit,
    viewModel: RecurringInvoicesViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(state.actionMessage) {
        state.actionMessage?.let { msg ->
            snackbarHostState.showSnackbar(msg)
            viewModel.clearActionMessage()
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            Column {
                BrandTopAppBar(
                    title = "Recurring Invoices",
                    navigationIcon = {
                        IconButton(onClick = onBack) {
                            Icon(
                                imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                                contentDescription = "Back",
                            )
                        }
                    },
                    actions = {
                        IconButton(onClick = { viewModel.load(isRefresh = true) }) {
                            Icon(Icons.Default.Refresh, contentDescription = "Refresh")
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
            // Status filter chips
            LazyRow(
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(STATUS_CHIPS, key = { it.first ?: "all" }) { (value, label) ->
                    FilterChip(
                        selected = state.statusFilter == value,
                        onClick = { viewModel.setStatusFilter(value) },
                        label = { Text(label) },
                    )
                }
            }

            when {
                state.isLoading -> {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .semantics { contentDescription = "Loading recurring invoices" },
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator()
                    }
                }

                state.notAvailable -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        EmptyState(
                            icon = Icons.Default.Autorenew,
                            title = "Recurring Invoices",
                            subtitle = "Not available on this server version",
                        )
                    }
                }

                state.error != null -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        ErrorState(
                            message = state.error ?: "Error loading recurring invoices",
                            onRetry = { viewModel.load() },
                        )
                    }
                }

                state.templates.isEmpty() -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        EmptyState(
                            icon = Icons.Default.Autorenew,
                            title = "No recurring invoices",
                            subtitle = when (state.statusFilter) {
                                "active"    -> "No active templates"
                                "paused"    -> "No paused templates"
                                "cancelled" -> "No cancelled templates"
                                else        -> "Recurring invoice templates will appear here"
                            },
                        )
                    }
                }

                else -> {
                    PullToRefreshBox(
                        isRefreshing = state.isRefreshing,
                        onRefresh = { viewModel.load(isRefresh = true) },
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        LazyColumn(
                            contentPadding = PaddingValues(
                                start = 16.dp, end = 16.dp, top = 8.dp, bottom = 80.dp,
                            ),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            items(state.templates, key = { it.id }) { template ->
                                RecurringInvoiceRow(
                                    template = template,
                                    onPause = { viewModel.pause(template.id) },
                                    onResume = { viewModel.resume(template.id) },
                                    onCancel = { viewModel.cancel(template.id) },
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

// ── Row ──────────────────────────────────────────────────────────────────────

@Composable
private fun RecurringInvoiceRow(
    template: RecurringInvoiceItem,
    onPause: () -> Unit,
    onResume: () -> Unit,
    onCancel: () -> Unit,
) {
    var showMenu by remember { mutableStateOf(false) }
    var showCancelConfirm by remember { mutableStateOf(false) }

    if (showCancelConfirm) {
        AlertDialog(
            onDismissRequest = { showCancelConfirm = false },
            title = { Text("Cancel template?") },
            text = { Text("\"${template.name}\" will stop generating invoices. This cannot be undone.") },
            confirmButton = {
                TextButton(onClick = { showCancelConfirm = false; onCancel() }) {
                    Text("Cancel template", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showCancelConfirm = false }) { Text("Keep") }
            },
        )
    }

    BrandCard(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = template.name,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                if (!template.customerName.isNullOrBlank()) {
                    Text(
                        text = template.customerName,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Text(
                    text = intervalLabel(template.intervalKind, template.intervalCount),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                template.nextRunAt?.let { next ->
                    Text(
                        text = "Next: $next",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Column(horizontalAlignment = Alignment.End) {
                BrandStatusBadge(
                    label = template.status.replaceFirstChar { it.uppercase() },
                    status = template.status,
                )
                Spacer(modifier = Modifier.height(4.dp))
                Box {
                    IconButton(
                        onClick = { showMenu = true },
                        modifier = Modifier.size(28.dp),
                    ) {
                        Icon(
                            Icons.Default.MoreVert,
                            contentDescription = "More options for ${template.name}",
                            modifier = Modifier.size(18.dp),
                        )
                    }
                    DropdownMenu(
                        expanded = showMenu,
                        onDismissRequest = { showMenu = false },
                    ) {
                        if (template.status == "active") {
                            DropdownMenuItem(
                                text = { Text("Pause") },
                                onClick = { showMenu = false; onPause() },
                                leadingIcon = { Icon(Icons.Default.Pause, null) },
                            )
                        }
                        if (template.status == "paused") {
                            DropdownMenuItem(
                                text = { Text("Resume") },
                                onClick = { showMenu = false; onResume() },
                                leadingIcon = { Icon(Icons.Default.PlayArrow, null) },
                            )
                        }
                        if (template.status != "cancelled") {
                            DropdownMenuItem(
                                text = { Text("Cancel", color = MaterialTheme.colorScheme.error) },
                                onClick = { showMenu = false; showCancelConfirm = true },
                                leadingIcon = {
                                    Icon(
                                        Icons.Default.Cancel,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.error,
                                    )
                                },
                            )
                        }
                    }
                }
            }
        }
    }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

private fun intervalLabel(kind: String, count: Int): String {
    val unit = when (kind.lowercase()) {
        "daily"   -> if (count == 1) "day" else "days"
        "weekly"  -> if (count == 1) "week" else "weeks"
        "monthly" -> if (count == 1) "month" else "months"
        "yearly"  -> if (count == 1) "year" else "years"
        else      -> kind
    }
    return if (count == 1) "Every $unit" else "Every $count $unit"
}
