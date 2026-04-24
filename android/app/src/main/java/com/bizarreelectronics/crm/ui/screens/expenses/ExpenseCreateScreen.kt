package com.bizarreelectronics.crm.ui.screens.expenses

import android.net.Uri
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
import androidx.compose.ui.platform.LocalContext
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
import com.bizarreelectronics.crm.ui.screens.expenses.components.ReceiptOcrScanner
import com.bizarreelectronics.crm.ui.screens.expenses.components.ReceiptPhotoPicker
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
    /** URI of the receipt photo chosen from the photo picker (local, not yet uploaded). */
    val receiptUri: Uri? = null,
    /** True while ML Kit OCR is running on the picked image. */
    val isOcrRunning: Boolean = false,
    /** Non-null when OCR runs but finds no useful fields. */
    val ocrToast: String? = null,
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

    fun clearOcrToast() {
        _state.value = _state.value.copy(ocrToast = null)
    }

    fun clearReceiptUri() {
        _state.value = _state.value.copy(receiptUri = null)
    }

    /**
     * Called when a receipt image is picked via PhotoPicker.
     * Stores the URI then triggers ML Kit OCR to auto-fill form fields.
     */
    fun onReceiptPicked(context: android.content.Context, uri: Uri) {
        _state.value = _state.value.copy(receiptUri = uri, isOcrRunning = true, ocrToast = null)
        viewModelScope.launch {
            try {
                val result = ReceiptOcrScanner.scanReceipt(context, uri)
                val hasUsefulData = result.total != null || result.vendor != null || result.date != null
                if (hasUsefulData) {
                    val current = _state.value
                    _state.value = current.copy(
                        isOcrRunning = false,
                        amount = result.total?.takeIf { current.amount.isBlank() } ?: current.amount,
                        description = result.vendor?.takeIf { current.description.isBlank() } ?: current.description,
                        date = result.date?.takeIf { current.date.isBlank() } ?: current.date,
                    )
                } else {
                    _state.value = _state.value.copy(
                        isOcrRunning = false,
                        ocrToast = "OCR found no data — please fill in manually",
                    )
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isOcrRunning = false,
                    ocrToast = "Receipt scan failed — please fill in manually",
                )
            }
        }
    }

    // ── Draft autosave ────────────────────────────────────────────────

    fun onFieldChanged() {
        autosaveJob?.cancel()
        autosaveJob = viewModelScope.launch {
            delay(DRAFT_AUTOSAVE_DEBOUNCE_MS)
            val json = serializeCurrentForm()
            draftStore.save(DraftStore.DraftType.EXPENSE, json)
        }
    }

    private fun serializeCurrentForm(): String {
        val s = _state.value
        val obj = JsonObject()
        if (s.category.isNotBlank()) obj.addProperty("category", s.category)
        if (s.amount.isNotBlank()) obj.addProperty("amount", s.amount)
        if (s.description.isNotBlank()) obj.addProperty("description", s.description)
        if (s.date.isNotBlank()) obj.addProperty("date", s.date)
        return gson.toJson(obj)
    }

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
    var showCategoryDropdown by rememberSaveable { mutableStateOf(false) }
    val focusManager = LocalFocusManager.current
    val context = LocalContext.current
    val onNext = KeyboardActions(onNext = { focusManager.moveFocus(FocusDirection.Down) })
    val onDoneSave = KeyboardActions(
        onDone = {
            focusManager.clearFocus()
            viewModel.save()
        },
    )

    LaunchedEffect(state.createdId) {
        val id = state.createdId
        if (id != null) onCreated(id)
    }

    LaunchedEffect(state.error) {
        val error = state.error
        if (error != null) {
            snackbarHostState.showSnackbar(error)
            viewModel.clearError()
        }
    }

    LaunchedEffect(state.ocrToast) {
        val toast = state.ocrToast
        if (toast != null) {
            snackbarHostState.showSnackbar(toast)
            viewModel.clearOcrToast()
        }
    }

    val canSave = state.category.isNotBlank() &&
        (state.amount.toDoubleOrNull()?.let { it > 0 } == true)

    val isFormEmpty = state.category.isBlank() && state.amount.isBlank() && state.description.isBlank()
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
            // Receipt photo picker + OCR
            ReceiptPhotoPicker(
                selectedUri = state.receiptUri,
                isOcrRunning = state.isOcrRunning,
                onImagePicked = { uri -> viewModel.onReceiptPicked(context, uri) },
                onClear = { viewModel.clearReceiptUri() },
                modifier = Modifier.fillMaxWidth(),
            )

            // Category dropdown
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

            OutlinedTextField(
                value = state.amount,
                onValueChange = viewModel::updateAmount,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Amount *") },
                leadingIcon = {
                    Text("$", color = MaterialTheme.colorScheme.onSurfaceVariant)
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
                label = { Text("Description / Vendor") },
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
