package com.bizarreelectronics.crm.ui.screens.expenses

import android.net.Uri
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
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
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.dto.CreateExpenseRequest
import com.bizarreelectronics.crm.data.remote.dto.CreateMileageExpenseRequest
import com.bizarreelectronics.crm.data.remote.dto.CreatePerDiemExpenseRequest
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
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import javax.inject.Inject
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions

private const val DRAFT_AUTOSAVE_DEBOUNCE_MS = 2_000L

/** Max amount enforced client-side; server validates too. */
private const val MAX_AMOUNT = 100_000.0
private val AMOUNT_DISPLAY_FORMATTER = DateTimeFormatter.ofPattern("MMM d, yyyy")

/** Expense sub-type selected via the segmented button on the create screen. */
enum class ExpenseSubtype { GENERAL, MILEAGE, PER_DIEM }

data class ExpenseCreateUiState(
    val category: String = "",
    val amount: String = "",
    val description: String = "",
    val date: String = LocalDate.now().toString(),
    /** Millis for the DatePickerState; kept in sync with [date]. */
    val dateMillis: Long = System.currentTimeMillis(),
    val isReimbursable: Boolean = false,
    val isSubmitting: Boolean = false,
    val error: String? = null,
    val createdId: Long? = null,
    val receiptUri: Uri? = null,
    val isOcrRunning: Boolean = false,
    val ocrToast: String? = null,
    /** True when offline create was queued (show distinct snackbar). */
    val savedOffline: Boolean = false,
    // ── Mileage / Per-diem sub-type fields ────────────────────────────
    /** Which sub-type is selected in the segmented button. */
    val subtype: ExpenseSubtype = ExpenseSubtype.GENERAL,
    /** Mileage: distance in miles (decimal). */
    val miles: String = "",
    /** Mileage: rate in cents per mile, entered as dollars (e.g. "0.67" = 67 ¢/mi). */
    val mileageRateDollars: String = "0.67",
    /** Mileage: vendor / business purpose. */
    val vendor: String = "",
    /** Per-diem: number of days. */
    val perDiemDays: String = "",
    /** Per-diem: rate in cents per day, entered as dollars (e.g. "75.00" = $75/day). */
    val perDiemRateDollars: String = "75.00",
)

@HiltViewModel
class ExpenseCreateViewModel @Inject constructor(
    private val expenseRepository: ExpenseRepository,
    private val draftStore: DraftStore,
    private val authPreferences: AuthPreferences,
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
        return s.category.isBlank() && s.amount.isBlank() && s.description.isBlank() &&
            s.miles.isBlank() && s.vendor.isBlank() && s.perDiemDays.isBlank()
    }

    fun updateCategory(value: String) {
        _state.value = _state.value.copy(category = value)
        onFieldChanged()
    }

    /**
     * Amount filter: digits + single dot + max 2 decimal places.
     * Rejects values > $100,000. Validation state drives isError on the field.
     */
    fun updateAmount(value: String) {
        // Allow empty or well-formed decimal
        if (value.isEmpty() || value.matches(Regex("^\\d*\\.?\\d{0,2}$"))) {
            _state.value = _state.value.copy(amount = value)
            onFieldChanged()
        }
        // Silently drop characters that would produce invalid input (extra dots, >2 decimals).
    }

    fun updateDescription(value: String) {
        _state.value = _state.value.copy(description = value)
        onFieldChanged()
    }

    fun updateDate(value: String) {
        _state.value = _state.value.copy(date = value)
        onFieldChanged()
    }

    /** Called when the Material3 DatePicker confirms a selection. */
    fun updateDateMillis(millis: Long) {
        val localDate = Instant.ofEpochMilli(millis)
            .atZone(ZoneId.systemDefault())
            .toLocalDate()
        _state.value = _state.value.copy(
            dateMillis = millis,
            date = localDate.toString(),
        )
        onFieldChanged()
    }

    fun updateReimbursable(checked: Boolean) {
        _state.value = _state.value.copy(isReimbursable = checked)
        onFieldChanged()
    }

    fun updateSubtype(value: ExpenseSubtype) {
        _state.value = _state.value.copy(subtype = value)
        onFieldChanged()
    }

    fun updateMiles(value: String) {
        if (value.isEmpty() || value.matches(Regex("^\\d*\\.?\\d{0,2}$"))) {
            _state.value = _state.value.copy(miles = value)
            onFieldChanged()
        }
    }

    fun updateMileageRate(value: String) {
        if (value.isEmpty() || value.matches(Regex("^\\d*\\.?\\d{0,2}$"))) {
            _state.value = _state.value.copy(mileageRateDollars = value)
            onFieldChanged()
        }
    }

    fun updateVendor(value: String) {
        _state.value = _state.value.copy(vendor = value)
        onFieldChanged()
    }

    fun updatePerDiemDays(value: String) {
        if (value.isEmpty() || value.matches(Regex("^\\d{0,3}$"))) {
            _state.value = _state.value.copy(perDiemDays = value)
            onFieldChanged()
        }
    }

    fun updatePerDiemRate(value: String) {
        if (value.isEmpty() || value.matches(Regex("^\\d*\\.?\\d{0,2}$"))) {
            _state.value = _state.value.copy(perDiemRateDollars = value)
            onFieldChanged()
        }
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

    fun clearSavedOffline() {
        _state.value = _state.value.copy(savedOffline = false)
    }

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
        when (current.subtype) {
            ExpenseSubtype.MILEAGE -> saveMileage(current)
            ExpenseSubtype.PER_DIEM -> savePerDiem(current)
            ExpenseSubtype.GENERAL -> saveGeneral(current)
        }
    }

    private fun saveGeneral(current: ExpenseCreateUiState) {
        if (current.category.isBlank()) {
            _state.value = current.copy(error = "Category is required")
            return
        }
        val amount = current.amount.toDoubleOrNull()
        if (amount == null || amount <= 0 || amount > MAX_AMOUNT) {
            _state.value = current.copy(error = "Amount must be between 0.01 and $100,000")
            return
        }
        val userRole = authPreferences.userRole
        val approvalStatus: String? = if (current.isReimbursable && userRole != "admin") "pending" else null
        viewModelScope.launch {
            _state.value = _state.value.copy(isSubmitting = true, error = null)
            try {
                val request = CreateExpenseRequest(
                    category = current.category,
                    amount = amount,
                    description = current.description.trim().ifBlank { null },
                    date = current.date.trim().ifBlank { null },
                    reimbursable = current.isReimbursable,
                    approvalStatus = approvalStatus,
                )
                // ExpenseRepository handles online/offline transparently.
                // Offline path writes to SyncQueueDao and returns a negative temp id.
                val createdId = expenseRepository.createExpense(request)
                val wasOffline = createdId < 0
                discardDraft()
                _state.value = _state.value.copy(
                    isSubmitting = false,
                    createdId = createdId,
                    savedOffline = wasOffline,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isSubmitting = false,
                    error = e.message ?: "Failed to create expense",
                )
            }
        }
    }

    private fun saveMileage(current: ExpenseCreateUiState) {
        if (current.category.isBlank()) {
            _state.value = current.copy(error = "Category is required")
            return
        }
        val miles = current.miles.toDoubleOrNull()
        if (miles == null || miles <= 0 || miles > 1000) {
            _state.value = current.copy(error = "Miles must be between 0.01 and 1,000")
            return
        }
        val rateDollars = current.mileageRateDollars.toDoubleOrNull()
        if (rateDollars == null || rateDollars <= 0) {
            _state.value = current.copy(error = "Rate per mile must be greater than 0")
            return
        }
        val rateCents = (rateDollars * 100).toInt().coerceIn(1, 50_000)
        viewModelScope.launch {
            _state.value = _state.value.copy(isSubmitting = true, error = null)
            try {
                val request = CreateMileageExpenseRequest(
                    vendor = current.vendor.trim().ifBlank { null },
                    description = current.description.trim().ifBlank { null },
                    incurredAt = current.date.trim().ifBlank { null },
                    miles = miles,
                    rateCents = rateCents,
                    category = current.category,
                )
                val createdId = expenseRepository.createMileageExpense(request)
                val wasOffline = createdId < 0
                discardDraft()
                _state.value = _state.value.copy(
                    isSubmitting = false,
                    createdId = createdId,
                    savedOffline = wasOffline,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isSubmitting = false,
                    error = e.message ?: "Failed to create mileage expense",
                )
            }
        }
    }

    private fun savePerDiem(current: ExpenseCreateUiState) {
        if (current.category.isBlank()) {
            _state.value = current.copy(error = "Category is required")
            return
        }
        val days = current.perDiemDays.toIntOrNull()
        if (days == null || days < 1 || days > 90) {
            _state.value = current.copy(error = "Days must be between 1 and 90")
            return
        }
        val rateDollars = current.perDiemRateDollars.toDoubleOrNull()
        if (rateDollars == null || rateDollars <= 0) {
            _state.value = current.copy(error = "Rate per day must be greater than 0")
            return
        }
        val rateCents = (rateDollars * 100).toInt().coerceIn(1, 50_000)
        viewModelScope.launch {
            _state.value = _state.value.copy(isSubmitting = true, error = null)
            try {
                val request = CreatePerDiemExpenseRequest(
                    description = current.description.trim().ifBlank { null },
                    incurredAt = current.date.trim().ifBlank { null },
                    days = days,
                    rateCents = rateCents,
                    category = current.category,
                )
                val createdId = expenseRepository.createPerDiemExpense(request)
                val wasOffline = createdId < 0
                discardDraft()
                _state.value = _state.value.copy(
                    isSubmitting = false,
                    createdId = createdId,
                    savedOffline = wasOffline,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isSubmitting = false,
                    error = e.message ?: "Failed to create per-diem expense",
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
    val focusManager = LocalFocusManager.current
    val context = LocalContext.current

    // ── Category dropdown ─────────────────────────────────────────────
    var categoryExpanded by rememberSaveable { mutableStateOf(false) }

    // ── Date picker ───────────────────────────────────────────────────
    var showDatePicker by rememberSaveable { mutableStateOf(false) }
    val datePickerState = rememberDatePickerState(
        initialSelectedDateMillis = state.dateMillis,
    )

    val onNext = KeyboardActions(onNext = { focusManager.moveFocus(FocusDirection.Down) })
    val onDoneSave = KeyboardActions(
        onDone = {
            focusManager.clearFocus()
            viewModel.save()
        },
    )

    // ── Amount validation (GENERAL sub-type only) ─────────────────────
    val amountDouble = state.amount.toDoubleOrNull()
    val amountError = state.subtype == ExpenseSubtype.GENERAL && state.amount.isNotEmpty() &&
        (amountDouble == null || amountDouble <= 0 || amountDouble > MAX_AMOUNT)

    // ── Mileage computed preview ──────────────────────────────────────
    val milesDouble = state.miles.toDoubleOrNull()
    val mileageRateDouble = state.mileageRateDollars.toDoubleOrNull()
    val mileagePreviewAmount = if (milesDouble != null && mileageRateDouble != null)
        "%.2f".format(milesDouble * mileageRateDouble) else null

    // ── Per-diem computed preview ─────────────────────────────────────
    val perDiemDaysInt = state.perDiemDays.toIntOrNull()
    val perDiemRateDouble = state.perDiemRateDollars.toDoubleOrNull()
    val perDiemPreviewAmount = if (perDiemDaysInt != null && perDiemRateDouble != null)
        "%.2f".format(perDiemDaysInt * perDiemRateDouble) else null

    val canSave = state.category.isNotBlank() && when (state.subtype) {
        ExpenseSubtype.GENERAL ->
            amountDouble != null && amountDouble > 0 && amountDouble <= MAX_AMOUNT
        ExpenseSubtype.MILEAGE ->
            milesDouble != null && milesDouble > 0 && milesDouble <= 1000 &&
                mileageRateDouble != null && mileageRateDouble > 0
        ExpenseSubtype.PER_DIEM ->
            perDiemDaysInt != null && perDiemDaysInt in 1..90 &&
                perDiemRateDouble != null && perDiemRateDouble > 0
    }

    // ── Date display ──────────────────────────────────────────────────
    val displayDate = remember(state.date) {
        runCatching {
            LocalDate.parse(state.date)
                .format(DateTimeFormatter.ofPattern("MMM d, yyyy"))
        }.getOrElse { state.date }
    }

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

    LaunchedEffect(state.savedOffline) {
        if (state.savedOffline) {
            snackbarHostState.showSnackbar("Saved offline; will sync when reconnected")
            viewModel.clearSavedOffline()
        }
    }

    val isFormEmpty = state.category.isBlank() && state.amount.isBlank() && state.description.isBlank()
    if (pendingDraft != null && isFormEmpty) {
        DraftRecoveryPrompt(
            draft = pendingDraft!!,
            previewFormatter = { json -> buildExpenseDraftPreview(json) },
            onResume = { viewModel.resumeDraft(pendingDraft!!) },
            onDiscard = { viewModel.discardDraft() },
        )
    }

    // ── Date picker dialog ────────────────────────────────────────────
    if (showDatePicker) {
        DatePickerDialog(
            onDismissRequest = { showDatePicker = false },
            confirmButton = {
                TextButton(onClick = {
                    datePickerState.selectedDateMillis?.let { viewModel.updateDateMillis(it) }
                    showDatePicker = false
                }) { Text("OK") }
            },
            dismissButton = {
                TextButton(onClick = { showDatePicker = false }) { Text("Cancel") }
            },
        ) {
            DatePicker(state = datePickerState)
        }
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

            // ── 0. Expense sub-type selector ──────────────────────────
            val subtypeLabels = listOf("General", "Mileage", "Per Diem")
            val subtypeValues = ExpenseSubtype.entries.toList()
            SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                subtypeValues.forEachIndexed { index, subtype ->
                    SegmentedButton(
                        selected = state.subtype == subtype,
                        onClick = { viewModel.updateSubtype(subtype) },
                        shape = SegmentedButtonDefaults.itemShape(index, subtypeValues.size),
                        label = { Text(subtypeLabels[index]) },
                    )
                }
            }

            // ── 1. Category — ExposedDropdownMenuBox ─────────────────
            ExposedDropdownMenuBox(
                expanded = categoryExpanded,
                onExpandedChange = { categoryExpanded = it },
            ) {
                OutlinedTextField(
                    value = state.category,
                    onValueChange = {},
                    modifier = Modifier
                        .fillMaxWidth()
                        .menuAnchor(),
                    label = { Text("Category *") },
                    readOnly = true,
                    trailingIcon = {
                        ExposedDropdownMenuDefaults.TrailingIcon(expanded = categoryExpanded)
                    },
                    colors = ExposedDropdownMenuDefaults.outlinedTextFieldColors(),
                )
                ExposedDropdownMenu(
                    expanded = categoryExpanded,
                    onDismissRequest = { categoryExpanded = false },
                ) {
                    // EXPENSE_CATEGORIES is defined in ExpenseListScreen.kt (same package).
                    // No server endpoint for expense-categories exists yet.
                    // TODO: fetch from GET /settings/expense-categories when endpoint is added;
                    //       fall back to EXPENSE_CATEGORIES constant if unavailable.
                    EXPENSE_CATEGORIES.forEach { cat ->
                        DropdownMenuItem(
                            text = { Text(cat) },
                            onClick = {
                                viewModel.updateCategory(cat)
                                categoryExpanded = false
                            },
                        )
                    }
                }
            }

            // ── 2. Sub-type specific fields ───────────────────────────
            when (state.subtype) {
                ExpenseSubtype.GENERAL -> {
                    // Amount field — only shown for general expenses
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
                        isError = amountError,
                        supportingText = if (amountError) {
                            { Text("Must be 0.01–\$100,000") }
                        } else null,
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
                }

                ExpenseSubtype.MILEAGE -> {
                    // Vendor field
                    OutlinedTextField(
                        value = state.vendor,
                        onValueChange = viewModel::updateVendor,
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("Vendor / Business Purpose") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                        keyboardActions = onNext,
                    )
                    // Miles + rate on the same row
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        OutlinedTextField(
                            value = state.miles,
                            onValueChange = viewModel::updateMiles,
                            modifier = Modifier.weight(1f),
                            label = { Text("Miles *") },
                            placeholder = { Text("0.0") },
                            singleLine = true,
                            isError = state.miles.isNotEmpty() && (milesDouble == null || milesDouble <= 0 || milesDouble > 1000),
                            supportingText = if (state.miles.isNotEmpty() && (milesDouble == null || milesDouble <= 0 || milesDouble > 1000)) {
                                { Text("0.01–1,000") }
                            } else null,
                            keyboardOptions = KeyboardOptions(
                                keyboardType = KeyboardType.Decimal,
                                imeAction = ImeAction.Next,
                            ),
                            keyboardActions = onNext,
                        )
                        OutlinedTextField(
                            value = state.mileageRateDollars,
                            onValueChange = viewModel::updateMileageRate,
                            modifier = Modifier.weight(1f),
                            label = { Text("Rate $/mi *") },
                            placeholder = { Text("0.67") },
                            leadingIcon = {
                                Text("$", color = MaterialTheme.colorScheme.onSurfaceVariant)
                            },
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(
                                keyboardType = KeyboardType.Decimal,
                                imeAction = ImeAction.Next,
                            ),
                            keyboardActions = onNext,
                        )
                    }
                    // Computed amount preview
                    if (mileagePreviewAmount != null) {
                        Text(
                            text = "Computed amount: $$mileagePreviewAmount",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    OutlinedTextField(
                        value = state.description,
                        onValueChange = viewModel::updateDescription,
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("Notes") },
                        singleLine = false,
                        minLines = 2,
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                        keyboardActions = onNext,
                    )
                }

                ExpenseSubtype.PER_DIEM -> {
                    // Days + rate on the same row
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        OutlinedTextField(
                            value = state.perDiemDays,
                            onValueChange = viewModel::updatePerDiemDays,
                            modifier = Modifier.weight(1f),
                            label = { Text("Days *") },
                            placeholder = { Text("1") },
                            singleLine = true,
                            isError = state.perDiemDays.isNotEmpty() && (perDiemDaysInt == null || perDiemDaysInt !in 1..90),
                            supportingText = if (state.perDiemDays.isNotEmpty() && (perDiemDaysInt == null || perDiemDaysInt !in 1..90)) {
                                { Text("1–90 days") }
                            } else null,
                            keyboardOptions = KeyboardOptions(
                                keyboardType = KeyboardType.Number,
                                imeAction = ImeAction.Next,
                            ),
                            keyboardActions = onNext,
                        )
                        OutlinedTextField(
                            value = state.perDiemRateDollars,
                            onValueChange = viewModel::updatePerDiemRate,
                            modifier = Modifier.weight(1f),
                            label = { Text("Rate $/day *") },
                            placeholder = { Text("75.00") },
                            leadingIcon = {
                                Text("$", color = MaterialTheme.colorScheme.onSurfaceVariant)
                            },
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(
                                keyboardType = KeyboardType.Decimal,
                                imeAction = ImeAction.Next,
                            ),
                            keyboardActions = onNext,
                        )
                    }
                    // Computed amount preview
                    if (perDiemPreviewAmount != null) {
                        Text(
                            text = "Computed amount: $$perDiemPreviewAmount",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    OutlinedTextField(
                        value = state.description,
                        onValueChange = viewModel::updateDescription,
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("Description / Purpose") },
                        singleLine = false,
                        minLines = 2,
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                        keyboardActions = onNext,
                    )
                }
            }

            // ── 3. Date picker ────────────────────────────────────────
            OutlinedTextField(
                value = displayDate,
                onValueChange = {},
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Date") },
                readOnly = true,
                trailingIcon = {
                    IconButton(onClick = { showDatePicker = true }) {
                        Icon(Icons.Default.CalendarMonth, contentDescription = "Pick date")
                    }
                },
                singleLine = true,
            )

            // ── 4. Reimbursable toggle ────────────────────────────────
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Column {
                    Text(
                        text = "Reimbursable",
                        style = MaterialTheme.typography.bodyLarge,
                    )
                    if (state.isReimbursable) {
                        Text(
                            text = "Approval required (pending)",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                Switch(
                    checked = state.isReimbursable,
                    onCheckedChange = viewModel::updateReimbursable,
                )
            }

            // Offline create is handled by ExpenseRepository: offline path writes to
            // SyncQueueDao and returns a negative temp id. VM sets savedOffline = (createdId < 0);
            // LaunchedEffect above shows the "Saved offline" snackbar and navigates via onCreated.
        }
    }
}
