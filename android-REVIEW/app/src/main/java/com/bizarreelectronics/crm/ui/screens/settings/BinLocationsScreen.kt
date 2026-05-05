package com.bizarreelectronics.crm.ui.screens.settings

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Place
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.InventoryApi
import com.bizarreelectronics.crm.data.remote.dto.BinLocationItem
import com.bizarreelectronics.crm.data.remote.dto.CreateBinLocationRequest
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import javax.inject.Inject

// ─── UiState ──────────────────────────────────────────────────────────────────

data class BinLocationsUiState(
    val bins: List<BinLocationItem> = emptyList(),
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    /** Bin being confirmed for deletion; null = no dialog open. */
    val pendingDelete: BinLocationItem? = null,
    val isDeleting: Boolean = false,
    val isCreating: Boolean = false,
)

// ─── ViewModel ────────────────────────────────────────────────────────────────

@HiltViewModel
class BinLocationsViewModel @Inject constructor(
    private val inventoryApi: InventoryApi,
) : ViewModel() {

    private val _state = MutableStateFlow(BinLocationsUiState())
    val state = _state.asStateFlow()

    /** One-shot snackbar messages emitted to the screen. */
    val snackMessages = MutableSharedFlow<String>(extraBufferCapacity = 4)

    init {
        load()
    }

    fun load(isRefresh: Boolean = false) {
        viewModelScope.launch {
            _state.value = _state.value.copy(
                isLoading = !isRefresh,
                isRefreshing = isRefresh,
                error = null,
            )
            runCatching { inventoryApi.getBinLocations() }
                .onSuccess { resp ->
                    _state.value = _state.value.copy(
                        isLoading = false,
                        isRefreshing = false,
                        bins = resp.data ?: emptyList(),
                    )
                }
                .onFailure { ex ->
                    val msg = when {
                        ex is HttpException && ex.code() == 404 ->
                            null // endpoint not deployed; show empty list gracefully
                        else -> ex.message ?: "Failed to load bin locations"
                    }
                    _state.value = _state.value.copy(
                        isLoading = false,
                        isRefreshing = false,
                        error = msg,
                        bins = if (msg == null) emptyList() else _state.value.bins,
                    )
                }
        }
    }

    fun requestDelete(bin: BinLocationItem) {
        _state.value = _state.value.copy(pendingDelete = bin)
    }

    fun cancelDelete() {
        _state.value = _state.value.copy(pendingDelete = null)
    }

    fun confirmDelete() {
        val target = _state.value.pendingDelete ?: return
        viewModelScope.launch {
            _state.value = _state.value.copy(isDeleting = true)
            runCatching { inventoryApi.deleteBinLocation(target.id) }
                .onSuccess {
                    _state.value = _state.value.copy(
                        isDeleting = false,
                        pendingDelete = null,
                        bins = _state.value.bins.filterNot { it.id == target.id },
                    )
                    snackMessages.emit("Bin \"${target.code}\" removed")
                }
                .onFailure { ex ->
                    _state.value = _state.value.copy(isDeleting = false, pendingDelete = null)
                    snackMessages.emit("Could not remove bin: ${ex.message}")
                }
        }
    }

    fun createBin(code: String, description: String, aisle: String, shelf: String, bin: String) {
        if (code.isBlank()) return
        viewModelScope.launch {
            _state.value = _state.value.copy(isCreating = true)
            runCatching {
                inventoryApi.createBinLocation(
                    CreateBinLocationRequest(
                        code = code.trim(),
                        description = description.trimOrNull(),
                        aisle = aisle.trimOrNull(),
                        shelf = shelf.trimOrNull(),
                        bin = bin.trimOrNull(),
                    )
                )
            }
                .onSuccess { resp ->
                    val created = resp.data
                    _state.value = _state.value.copy(
                        isCreating = false,
                        bins = if (created != null) _state.value.bins + created else _state.value.bins,
                    )
                    snackMessages.emit("Bin \"${code.trim()}\" created")
                }
                .onFailure { ex ->
                    _state.value = _state.value.copy(isCreating = false)
                    val msg = when {
                        ex is HttpException && ex.code() == 409 -> "Code \"${code.trim()}\" is already taken"
                        else -> "Could not create bin: ${ex.message}"
                    }
                    snackMessages.emit(msg)
                }
        }
    }

    private fun String.trimOrNull(): String? = trim().takeIf { it.isNotBlank() }
}

// ─── Screen ───────────────────────────────────────────────────────────────────

/**
 * §6.8 — Bin Locations manager (Settings → Inventory → Bin Locations).
 *
 * Lets admins create / view / delete warehouse bin addresses (aisle + shelf + bin).
 * Full CRUD against GET/POST/DELETE /inventory-enrich/bin-locations.
 *
 * 404-tolerant: if the server predates the bin-locations table the screen shows
 * an empty list rather than an error, so tenants on older server builds aren't
 * blocked from loading Settings.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BinLocationsScreen(
    onBack: () -> Unit,
    viewModel: BinLocationsViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHost = remember { SnackbarHostState() }
    var showCreateDialog by rememberSaveable { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        viewModel.snackMessages.collect { msg -> snackbarHost.showSnackbar(msg) }
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Bin Locations",
                navigationIcon = {
                    IconButton(
                        onClick = onBack,
                        modifier = Modifier.semantics { contentDescription = "Back" },
                    ) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
            )
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = { showCreateDialog = true },
                containerColor = MaterialTheme.colorScheme.primary,
                modifier = Modifier.semantics { contentDescription = "Add bin location" },
            ) {
                Icon(Icons.Default.Add, contentDescription = null)
            }
        },
        snackbarHost = { SnackbarHost(snackbarHost) },
    ) { padding ->
        when {
            state.isLoading -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentAlignment = Alignment.Center,
                ) { CircularProgressIndicator() }
            }

            state.error != null -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    ErrorState(
                        message = state.error ?: "Error loading bin locations",
                        onRetry = { viewModel.load() },
                    )
                }
            }

            else -> {
                PullToRefreshBox(
                    isRefreshing = state.isRefreshing,
                    onRefresh = { viewModel.load(isRefresh = true) },
                    modifier = Modifier.fillMaxSize().padding(padding),
                ) {
                    if (state.bins.isEmpty()) {
                        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                            EmptyState(
                                title = "No bin locations yet",
                                subtitle = "Tap + to create your first aisle / shelf / bin address.",
                            )
                        }
                    } else {
                        LazyColumn(
                            contentPadding = PaddingValues(16.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                            modifier = Modifier.fillMaxSize(),
                        ) {
                            item {
                                Text(
                                    "${state.bins.size} location${if (state.bins.size != 1) "s" else ""}",
                                    style = MaterialTheme.typography.labelMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                            items(state.bins, key = { it.id }) { bin ->
                                BinLocationRow(
                                    bin = bin,
                                    onDelete = { viewModel.requestDelete(bin) },
                                )
                            }
                            item { Spacer(modifier = Modifier.height(80.dp)) } // FAB clearance
                        }
                    }
                }
            }
        }

        // ── Delete confirmation ────────────────────────────────────────────────
        if (state.pendingDelete != null) {
            AlertDialog(
                onDismissRequest = { if (!state.isDeleting) viewModel.cancelDelete() },
                title = { Text("Remove bin location?") },
                text = {
                    Text(
                        "Bin \"${state.pendingDelete!!.code}\" will be soft-deleted. " +
                            "Items already assigned to this bin keep their assignment.",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                },
                confirmButton = {
                    TextButton(
                        onClick = viewModel::confirmDelete,
                        enabled = !state.isDeleting,
                    ) {
                        if (state.isDeleting) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(16.dp),
                                strokeWidth = 2.dp,
                            )
                        } else {
                            Text("Remove", color = MaterialTheme.colorScheme.error)
                        }
                    }
                },
                dismissButton = {
                    TextButton(
                        onClick = viewModel::cancelDelete,
                        enabled = !state.isDeleting,
                    ) { Text("Cancel") }
                },
            )
        }

        // ── Create dialog ──────────────────────────────────────────────────────
        AnimatedVisibility(visible = showCreateDialog) {
            CreateBinDialog(
                isCreating = state.isCreating,
                onDismiss = { showCreateDialog = false },
                onCreate = { code, desc, aisle, shelf, bin ->
                    viewModel.createBin(code, desc, aisle, shelf, bin)
                    showCreateDialog = false
                },
            )
        }
    }
}

// ─── Row ──────────────────────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BinLocationRow(
    bin: BinLocationItem,
    onDelete: () -> Unit,
) {
    val swipeState = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            if (value == SwipeToDismissBoxValue.EndToStart) {
                onDelete()
                false // don't auto-dismiss; dialog confirms
            } else false
        }
    )

    SwipeToDismissBox(
        state = swipeState,
        backgroundContent = {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(end = 16.dp),
                contentAlignment = Alignment.CenterEnd,
            ) {
                Icon(
                    Icons.Default.Delete,
                    contentDescription = "Delete bin ${bin.code}",
                    tint = MaterialTheme.colorScheme.error,
                )
            }
        },
        enableDismissFromStartToEnd = false,
    ) {
        BrandCard(modifier = Modifier.fillMaxWidth()) {
            Row(
                modifier = Modifier
                    .padding(horizontal = 16.dp, vertical = 12.dp)
                    .fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.weight(1f),
                ) {
                    Icon(
                        Icons.Default.Place,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(20.dp),
                    )
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(
                            bin.code,
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.SemiBold,
                        )
                        val address = listOfNotNull(
                            bin.aisle?.let { "Aisle $it" },
                            bin.shelf?.let { "Shelf $it" },
                            bin.bin?.let { "Bin $it" },
                        ).joinToString(" · ")
                        if (address.isNotBlank()) {
                            Text(
                                address,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        if (!bin.description.isNullOrBlank()) {
                            Text(
                                bin.description,
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }

                IconButton(
                    onClick = onDelete,
                    modifier = Modifier.semantics {
                        contentDescription = "Delete bin ${bin.code}"
                    },
                ) {
                    Icon(
                        Icons.Default.Delete,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.error,
                    )
                }
            }
        }
    }
    HorizontalDivider(modifier = Modifier.padding(horizontal = 4.dp))
}

// ─── Create dialog ────────────────────────────────────────────────────────────

@Composable
private fun CreateBinDialog(
    isCreating: Boolean,
    onDismiss: () -> Unit,
    onCreate: (code: String, description: String, aisle: String, shelf: String, bin: String) -> Unit,
) {
    var code by rememberSaveable { mutableStateOf("") }
    var description by rememberSaveable { mutableStateOf("") }
    var aisle by rememberSaveable { mutableStateOf("") }
    var shelf by rememberSaveable { mutableStateOf("") }
    var binField by rememberSaveable { mutableStateOf("") }

    val codeError = code.isBlank()

    AlertDialog(
        onDismissRequest = { if (!isCreating) onDismiss() },
        title = { Text("New Bin Location") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = code,
                    onValueChange = { code = it },
                    label = { Text("Code *") },
                    placeholder = { Text("e.g. A1-S2-B3") },
                    isError = code.isNotBlank().not() && code.isNotEmpty(),
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = description,
                    onValueChange = { description = it },
                    label = { Text("Description") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                    modifier = Modifier.fillMaxWidth(),
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = aisle,
                        onValueChange = { aisle = it },
                        label = { Text("Aisle") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                        modifier = Modifier.weight(1f),
                    )
                    OutlinedTextField(
                        value = shelf,
                        onValueChange = { shelf = it },
                        label = { Text("Shelf") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                        modifier = Modifier.weight(1f),
                    )
                    OutlinedTextField(
                        value = binField,
                        onValueChange = { binField = it },
                        label = { Text("Bin") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onCreate(code, description, aisle, shelf, binField) },
                enabled = !codeError && !isCreating,
            ) {
                if (isCreating) {
                    CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                } else {
                    Text("Create")
                }
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, enabled = !isCreating) { Text("Cancel") }
        },
    )
}
