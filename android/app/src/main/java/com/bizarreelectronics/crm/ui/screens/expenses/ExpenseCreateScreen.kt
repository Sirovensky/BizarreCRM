package com.bizarreelectronics.crm.ui.screens.expenses

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.draft.DraftStore
import com.bizarreelectronics.crm.data.remote.dto.CreateExpenseRequest
import com.bizarreelectronics.crm.data.repository.ExpenseRepository
import com.bizarreelectronics.crm.ui.components.DraftRecoveryPrompt
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.google.gson.Gson
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.LocalDate
import javax.inject.Inject

private const val DRAFT_AUTOSAVE_DEBOUNCE_MS = 2_000L

data class ExpenseCreateUiState(
    val category: String = "",
    val amount: String = "",
    val description: String = "",
    val date: String = LocalDate.now().toString(),
    val isSubmitting: Boolean = false,
    val error: String? = null,
    val createdId: Long? = null,
)

@HiltViewModel
class ExpenseCreateViewModel @Inject constructor(
    private val expenseRepository: ExpenseRepository,
    private val draftStore: DraftStore,
    private val gson: Gson,
) : ViewModel() {

    private val _state = MutableStateFlow(ExpenseCreateUiState())
    val state = _state.asStateFlow()

    private val _pendingDraft = MutableStateFlow<DraftStore.Draft?>(null)
    val pendingDraft: StateFlow<DraftStore.Draft?> = _pendingDraft.asStateFlow()

    private var autosaveJob: Job? = null

    init {
        viewModelScope.launch {
            val draft = draftStore.load(DraftStore.DraftType.EXPENSE)
            if (draft != null && isFormEmpty()) {
                _pendingDraft.value = draft
            }
        }
    }

    private fun isFormEmpty(): Boolean {
        val s = _state.value
        return s.category.isBlank() && s.amount.isBlank() && s.description.isBlank()
    }

    fun updateCategory(value: String) {
        _state.value = _state.value.copy(category = value)
        onFieldChanged()
    }

    fun updateAmount(value: String) {
        if (value.isEmpty() || value.matches(Regex("^\\d*\\.?\\d{0,2}$"))) {
            _state.value = _state.value.copy(amount = value)
            onFieldChanged()
        }
    }

    fun updateDescription(value: String) {
        _state.value = _state.value.copy(description = value)
        onFieldChanged()
    }

    fun updateDate(value: String) {
        _state.value = _state.value.copy(date = value)
        onFieldChanged()
    }

    fun clearError() {
        _state.value = _state.value.copy(error = null)
    }

    // ── Draft autosave ────────────────────────────────────────────────

    /**
     * Call after every user-driven field change.
     * Cancels the previous pending autosave and starts a fresh 2-second
     * countdown before persisting the current form to DraftStore.
     */
    fun onFieldChanged() {
        autosaveJob?.cancel()
        autosaveJob = viewModelScope.launch {
            delay(DRAFT_AUTOSAVE_DEBOUNCE_MS)
            val json = serializeCurrentForm()
            draftStore.save(DraftStore.DraftType.EXPENSE, json)
        }
    }

    /** Serialise the expense form fields for draft persistence. */
    private fun serializeCurrentForm(): String {
        val s = _state.value
        val obj = JsonObject()
        if (s.category.isNotBlank()) obj.addProperty("category", s.category)
        if (s.amount.isNotBlank()) obj.addProperty("amount", s.amount)
        if (s.description.isNotBlank()) obj.addProperty("description", s.description)
        if (s.date.isNotBlank()) obj.addProperty("date", s.date)
        return gson.toJson(obj)
    }

    /**
     * Restore form state from a persisted draft.
     * All fields are plain text — no secondary API calls required.
     */
    fun resumeDraft(draft: DraftStore.Draft) {
        _pendingDraft.value = null
        val obj = try {
            JsonParser.parseString(draft.payloadJson).asJsonObject
        } catch (_: Exception) {
            return
        }
        val category    = obj.get("category")?.takeIf { !it.isJsonNull }?.asString ?: ""
        val amount      = obj.get("amount")?.takeIf { !it.isJsonNull }?.asString ?: ""
        val description = obj.get("description")?.takeIf { !it.isJsonNull }?.asString ?: ""
        val date        = obj.get("date")?.takeIf { !it.isJsonNull }?.asString
            ?: LocalDate.now().toString()
        _state.value = _state.value.copy(
            category    = category,
            amount      = amount,
            description = description,
            date        = date,
        )
    }

    /** Permanently discard the pending draft and clear the recovery prompt. */
    fun discardDraft() {
        _pendingDraft.value = null
        viewModelScope.launch {
            draftStore.discard(DraftStore.DraftType.EXPENSE)
        }
    }

    fun save() {
        val current = _state.value
        if (current.category.isBlank()) {
            _state.value = current.copy(error = "Category is required")
            return
        }
        val amount = current.amount.toDoubleOrNull()
        if (amount == null || amount <= 0) {
            _state.value = current.copy(error = "Amount must be greater than 0")
            return
        }

        viewModelScope.launch {
            _state.value = _state.value.copy(isSubmitting = true, error = null)
            try {
                val request = CreateExpenseRequest(
                    category = current.category,
                    amount = amount,
                    description = current.description.trim().ifBlank { null },
                    date = current.date.trim().ifBlank { null },
                )
                val createdId = expenseRepository.createExpense(request)
                // Expense created successfully — draft is no longer needed.
                discardDraft()
                _state.value = _state.value.copy(
                    isSubmitting = false,
                    createdId = createdId,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isSubmitting = false,
                    error = e.message ?: "Failed to create expense",
                )
            }
        }
    }
}

/**
 * Build a short, human-readable preview string from an expense draft payload JSON.
 * Used by [DraftRecoveryPrompt] so the user can identify the draft at a glance.
 *
 * Example outputs:
 *   "Expense $45.00 for Parts on 2026-04-23"
 *   "$12.50 for Shipping"
 *   "New expense (no details)"
 */
private fun buildExpenseDraftPreview(json: String): String {
    return try {
        val obj = JsonParser.parseString(json).asJsonObject
        val amount   = obj.get("amount")?.takeIf { !it.isJsonNull }?.asString
        val category = obj.get("category")?.takeIf { !it.isJsonNull }?.asString
        val date     = obj.get("date")?.takeIf { !it.isJsonNull }?.asString
        val parts = mutableListOf<String>()
        val amountStr = if (!amount.isNullOrBlank()) "\$$amount" else null
        if (amountStr != null && !category.isNullOrBlank()) {
            parts.add("Expense $amountStr for $category")
        } else if (amountStr != null) {
            parts.add("Expense $amountStr")
        } else if (!category.isNullOrBlank()) {
            parts.add(category)
        }
        if (!date.isNullOrBlank()) parts.add("on $date")
        if (parts.isEmpty()) "New expense (no details)" else parts.joinToString(" ")
    } catch (_: Exception) {
        "New expense"
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExpenseCreateScreen(
    onBack: () -> Unit,
    onCreated: (Long) -> Unit,
    viewModel: ExpenseCreateViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val pendingDraft by viewModel.pendingDraft.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    // U7 fix: dropdown state saved across rotation.
    var showCategoryDropdown by rememberSaveable { mutableStateOf(false) }
    // D5-6: IME actions — Next moves focus, Done clears focus and triggers
    // the same save flow the toolbar action uses.
    val focusManager = LocalFocusManager.current
    val onNext = KeyboardActions(onNext = { focusManager.moveFocus(FocusDirection.Down) })
    val onDoneSave = KeyboardActions(
        onDone = {
            focusManager.clearFocus()
            viewModel.save()
        },
    )

    LaunchedEffect(state.createdId) {
        val id = state.createdId
        if (id != null) {
            onCreated(id)
        }
    }

    LaunchedEffect(state.error) {
        val error = state.error
        if (error != null) {
            snackbarHostState.showSnackbar(error)
            viewModel.clearError()
        }
    }

    val canSave = state.category.isNotBlank() &&
        (state.amount.toDoubleOrNull()?.let { it > 0 } == true)

    // Draft recovery prompt — surfaces as a modal bottom sheet when a previously
    // saved draft exists and the form is currently empty (no in-progress entry).
    val isFormEmpty = state.category.isBlank() && state.amount.isBlank() &&
        state.description.isBlank()
    if (pendingDraft != null && isFormEmpty) {
        DraftRecoveryPrompt(
            draft = pendingDraft!!,
            previewFormatter = { json -> buildExpenseDraftPreview(json) },
            onResume = { viewModel.resumeDraft(pendingDraft!!) },
            onDiscard = { viewModel.discardDraft() },
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            BrandTopAppBar(
                title = "New Expense",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    if (state.isSubmitting) {
                        // In-toolbar spinner — keep bare spinner per spec (not skeleton)
                        CircularProgressIndicator(
                            modifier = Modifier.size(24.dp),
                            strokeWidth = 2.dp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Spacer(modifier = Modifier.width(16.dp))
                    } else {
                        TextButton(
                            onClick = { viewModel.save() },
                            enabled = canSave,
                            colors = ButtonDefaults.textButtonColors(
                                contentColor = MaterialTheme.colorScheme.primary,
                                disabledContentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                            ),
                        ) {
                            Text("Save")
                        }
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .imePadding()
                .padding(16.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // Category dropdown — OutlinedTextField inherits purple focus ring from theme
            Box {
                OutlinedTextField(
                    value = state.category,
                    onValueChange = {},
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Category *") },
                    readOnly = true,
                    trailingIcon = {
                        IconButton(onClick = { showCategoryDropdown = true }) {
                            Icon(Icons.Default.ArrowDropDown, contentDescription = "Select category")
                        }
                    },
                )
                DropdownMenu(
                    expanded = showCategoryDropdown,
                    onDismissRequest = { showCategoryDropdown = false },
                ) {
                    EXPENSE_CATEGORIES.forEach { category ->
                        DropdownMenuItem(
                            text = { Text(category) },
                            onClick = {
                                viewModel.updateCategory(category)
                                showCategoryDropdown = false
                            },
                        )
                    }
                }
            }

            // Amount — orange focus ring via theme.
            // CROSS32-ext: unified money-input affordance — $ leadingIcon
            // + "0.00" placeholder to match ticket wizard / inventory /
            // invoice-payment sites.
            OutlinedTextField(
                value = state.amount,
                onValueChange = viewModel::updateAmount,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Amount *") },
                leadingIcon = {
                    Text(
                        "$",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                },
                placeholder = { Text("0.00") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Decimal,
                    imeAction = ImeAction.Next,
                ),
                keyboardActions = onNext,
            )

            OutlinedTextField(
                value = state.description,
                onValueChange = viewModel::updateDescription,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Description") },
                singleLine = false,
                minLines = 2,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                keyboardActions = onNext,
            )

            OutlinedTextField(
                value = state.date,
                onValueChange = viewModel::updateDate,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Date (YYYY-MM-DD)") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                keyboardActions = onDoneSave,
            )
        }
    }
}
