package com.bizarreelectronics.crm.ui.screens.expenses

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.dto.CreateExpenseRequest
import com.bizarreelectronics.crm.data.repository.ExpenseRepository
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.LocalDate
import javax.inject.Inject

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
) : ViewModel() {

    private val _state = MutableStateFlow(ExpenseCreateUiState())
    val state = _state.asStateFlow()

    fun updateCategory(value: String) {
        _state.value = _state.value.copy(category = value)
    }

    fun updateAmount(value: String) {
        if (value.isEmpty() || value.matches(Regex("^\\d*\\.?\\d{0,2}$"))) {
            _state.value = _state.value.copy(amount = value)
        }
    }

    fun updateDescription(value: String) {
        _state.value = _state.value.copy(description = value)
    }

    fun updateDate(value: String) {
        _state.value = _state.value.copy(date = value)
    }

    fun clearError() {
        _state.value = _state.value.copy(error = null)
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExpenseCreateScreen(
    onBack: () -> Unit,
    onCreated: (Long) -> Unit,
    viewModel: ExpenseCreateViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    // U7 fix: dropdown state saved across rotation.
    var showCategoryDropdown by rememberSaveable { mutableStateOf(false) }

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

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            BrandTopAppBar(
                title = "New expense",
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

            // Amount — OutlinedTextField inherits purple focus ring from theme
            OutlinedTextField(
                value = state.amount,
                onValueChange = viewModel::updateAmount,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Amount *") },
                prefix = { Text("$") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Decimal,
                    imeAction = ImeAction.Next,
                ),
            )

            OutlinedTextField(
                value = state.description,
                onValueChange = viewModel::updateDescription,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Description") },
                singleLine = false,
                minLines = 2,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
            )

            OutlinedTextField(
                value = state.date,
                onValueChange = viewModel::updateDate,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Date (YYYY-MM-DD)") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
            )
        }
    }
}
