package com.bizarreelectronics.crm.ui.screens.inventory

import android.util.Log
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.RmaApi
import com.bizarreelectronics.crm.data.remote.dto.RmaCreateRequest
import com.bizarreelectronics.crm.data.remote.dto.RmaItemRequest
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

// ─── Draft item ────────────────────────────────────────────────────────────

/** Mutable draft line-item before submission. */
data class DraftRmaItem(
    val name: String = "",
    val quantity: String = "1",
    val reason: String = "",
)

// ─── UI state ─────────────────────────────────────────────────────────────

data class RmaCreateUiState(
    val supplierName: String = "",
    val reason: String = "",
    val notes: String = "",
    val lineItems: List<DraftRmaItem> = listOf(DraftRmaItem()),
    val isSubmitting: Boolean = false,
    val submitError: String? = null,
    val createdRmaId: Long? = null,
)

// ─── ViewModel ─────────────────────────────────────────────────────────────

@HiltViewModel
class RmaCreateViewModel @Inject constructor(
    private val api: RmaApi,
) : ViewModel() {

    private val _state = MutableStateFlow(RmaCreateUiState())
    val state = _state.asStateFlow()

    fun onSupplierNameChanged(v: String) {
        _state.value = _state.value.copy(supplierName = v)
    }

    fun onReasonChanged(v: String) {
        _state.value = _state.value.copy(reason = v)
    }

    fun onNotesChanged(v: String) {
        _state.value = _state.value.copy(notes = v)
    }

    fun onItemNameChanged(index: Int, v: String) {
        val updated = _state.value.lineItems.toMutableList()
        updated[index] = updated[index].copy(name = v)
        _state.value = _state.value.copy(lineItems = updated)
    }

    fun onItemQtyChanged(index: Int, v: String) {
        val updated = _state.value.lineItems.toMutableList()
        updated[index] = updated[index].copy(quantity = v)
        _state.value = _state.value.copy(lineItems = updated)
    }

    fun onItemReasonChanged(index: Int, v: String) {
        val updated = _state.value.lineItems.toMutableList()
        updated[index] = updated[index].copy(reason = v)
        _state.value = _state.value.copy(lineItems = updated)
    }

    fun addLineItem() {
        val updated = _state.value.lineItems + DraftRmaItem()
        _state.value = _state.value.copy(lineItems = updated)
    }

    fun removeLineItem(index: Int) {
        if (_state.value.lineItems.size <= 1) return   // keep at least one item
        val updated = _state.value.lineItems.toMutableList().also { it.removeAt(index) }
        _state.value = _state.value.copy(lineItems = updated)
    }

    fun clearSubmitError() {
        _state.value = _state.value.copy(submitError = null)
    }

    fun submit() {
        val s = _state.value
        if (s.isSubmitting) return

        // Basic client validation
        if (s.lineItems.any { it.name.isBlank() }) {
            _state.value = s.copy(submitError = "All items need a name.")
            return
        }
        if (s.lineItems.any { it.reason.isBlank() }) {
            _state.value = s.copy(submitError = "All items need a return reason.")
            return
        }
        if (s.lineItems.any { (it.quantity.toIntOrNull() ?: 0) < 1 }) {
            _state.value = s.copy(submitError = "Quantity must be at least 1 for each item.")
            return
        }

        viewModelScope.launch {
            _state.value = s.copy(isSubmitting = true, submitError = null)
            try {
                val items = s.lineItems.map { draft ->
                    RmaItemRequest(
                        name = draft.name.trim(),
                        quantity = draft.quantity.toIntOrNull() ?: 1,
                        reason = draft.reason.trim(),
                    )
                }
                val request = RmaCreateRequest(
                    supplierName = s.supplierName.trim().ifBlank { null },
                    reason = s.reason.trim().ifBlank { null },
                    notes = s.notes.trim().ifBlank { null },
                    items = items,
                )
                val response = api.createRma(request)
                if (response.success && response.data != null) {
                    _state.value = _state.value.copy(
                        isSubmitting = false,
                        createdRmaId = response.data.id,
                    )
                } else {
                    _state.value = _state.value.copy(
                        isSubmitting = false,
                        submitError = response.message ?: "Failed to create return.",
                    )
                }
            } catch (e: Exception) {
                Log.w(TAG, "submit failed: ${e.message}")
                _state.value = _state.value.copy(
                    isSubmitting = false,
                    submitError = e.message ?: "Failed to create return.",
                )
            }
        }
    }

    companion object { private const val TAG = "RmaCreateVM" }
}

// ─── Screen ────────────────────────────────────────────────────────────────

/**
 * §61.5 — Create a vendor return (RMA).
 *
 * Collects supplier name, an optional overall reason, an optional note, and one
 * or more line items (name + quantity + per-item reason). On success, calls
 * [onCreated] with the new RMA id so the caller can navigate to the detail screen.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RmaCreateScreen(
    onCreated: (Long) -> Unit,
    onBack: () -> Unit,
    viewModel: RmaCreateViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    // Navigate out once created
    LaunchedEffect(state.createdRmaId) {
        val id = state.createdRmaId ?: return@LaunchedEffect
        onCreated(id)
    }

    // Show submit errors in snackbar
    LaunchedEffect(state.submitError) {
        val err = state.submitError ?: return@LaunchedEffect
        snackbarHostState.showSnackbar(err)
        viewModel.clearSubmitError()
    }

    val isSubmitEnabled = !state.isSubmitting &&
        state.lineItems.isNotEmpty() &&
        state.lineItems.all { it.name.isNotBlank() && it.reason.isNotBlank() }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            BrandTopAppBar(
                title = "New Vendor Return",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    TextButton(
                        onClick = { viewModel.submit() },
                        enabled = isSubmitEnabled,
                    ) {
                        if (state.isSubmitting) {
                            CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                        } else {
                            Text("Submit")
                        }
                    }
                },
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // Supplier name
            item {
                OutlinedTextField(
                    value = state.supplierName,
                    onValueChange = viewModel::onSupplierNameChanged,
                    label = { Text("Supplier name (optional)") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.Words,
                        imeAction = ImeAction.Next,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            // Overall reason
            item {
                OutlinedTextField(
                    value = state.reason,
                    onValueChange = viewModel::onReasonChanged,
                    label = { Text("Overall reason (optional)") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.Sentences,
                        imeAction = ImeAction.Next,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            // Notes
            item {
                OutlinedTextField(
                    value = state.notes,
                    onValueChange = viewModel::onNotesChanged,
                    label = { Text("Notes (optional)") },
                    minLines = 2,
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.Sentences,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            // Section header for items
            item {
                Text(
                    "Items to return",
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 4.dp),
                )
            }

            // Line items
            itemsIndexed(state.lineItems) { index, draft ->
                RmaLineItemCard(
                    index = index,
                    draft = draft,
                    canRemove = state.lineItems.size > 1,
                    onNameChanged = { viewModel.onItemNameChanged(index, it) },
                    onQtyChanged = { viewModel.onItemQtyChanged(index, it) },
                    onReasonChanged = { viewModel.onItemReasonChanged(index, it) },
                    onRemove = { viewModel.removeLineItem(index) },
                )
            }

            // Add item button
            item {
                OutlinedButton(
                    onClick = { viewModel.addLineItem() },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("Add item")
                }
            }
        }
    }
}

// ─── Line item card ────────────────────────────────────────────────────────

@Composable
private fun RmaLineItemCard(
    index: Int,
    draft: DraftRmaItem,
    canRemove: Boolean,
    onNameChanged: (String) -> Unit,
    onQtyChanged: (String) -> Unit,
    onReasonChanged: (String) -> Unit,
    onRemove: () -> Unit,
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "Item ${index + 1}",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (canRemove) {
                    IconButton(onClick = onRemove, modifier = Modifier.size(32.dp)) {
                        Icon(
                            Icons.Default.Delete,
                            contentDescription = "Remove item ${index + 1}",
                            tint = MaterialTheme.colorScheme.error,
                            modifier = Modifier.size(18.dp),
                        )
                    }
                }
            }

            OutlinedTextField(
                value = draft.name,
                onValueChange = onNameChanged,
                label = { Text("Item name *") },
                singleLine = true,
                isError = draft.name.isBlank(),
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.Words,
                    imeAction = ImeAction.Next,
                ),
                modifier = Modifier.fillMaxWidth(),
            )

            OutlinedTextField(
                value = draft.quantity,
                onValueChange = onQtyChanged,
                label = { Text("Quantity") },
                singleLine = true,
                isError = (draft.quantity.toIntOrNull() ?: 0) < 1,
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Number,
                    imeAction = ImeAction.Next,
                ),
                modifier = Modifier.width(120.dp),
            )

            OutlinedTextField(
                value = draft.reason,
                onValueChange = onReasonChanged,
                label = { Text("Return reason *") },
                singleLine = true,
                isError = draft.reason.isBlank(),
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.Sentences,
                    imeAction = ImeAction.Done,
                ),
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}
