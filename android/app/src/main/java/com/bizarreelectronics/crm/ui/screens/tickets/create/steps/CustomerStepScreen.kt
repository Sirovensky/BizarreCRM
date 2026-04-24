package com.bizarreelectronics.crm.ui.screens.tickets.create.steps

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.dto.CustomerListItem

/**
 * Step 1 — Customer selection.
 *
 * Provides:
 * - Debounced search (300 ms, min 2 chars) against `GET /customers/search?q=`.
 * - "New customer" inline mini-form (first name, last name, phone, email).
 * - "Walk-in" shortcut that bypasses customer selection entirely.
 *
 * ### Layout
 * Phone: full-screen scrollable column.
 * Tablet: same content rendered inside the right pane of the wizard shell.
 *
 * Validation: Next is enabled when `selectedCustomer != null || isWalkIn`.
 */
@Composable
fun CustomerStepScreen(
    query: String,
    results: List<CustomerListItem>,
    isSearching: Boolean,
    selectedCustomer: CustomerListItem?,
    isWalkIn: Boolean,
    onQueryChange: (String) -> Unit,
    onSelect: (CustomerListItem) -> Unit,
    onSelectWalkIn: () -> Unit,
    onClear: () -> Unit,
    showNewCustomerForm: Boolean,
    onToggleNewCustomerForm: () -> Unit,
    newCustFirstName: String,
    newCustLastName: String,
    newCustPhone: String,
    newCustEmail: String,
    isCreatingCustomer: Boolean,
    onNewCustFirstNameChange: (String) -> Unit,
    onNewCustLastNameChange: (String) -> Unit,
    onNewCustPhoneChange: (String) -> Unit,
    onNewCustEmailChange: (String) -> Unit,
    onCreateAndSelect: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val focusManager = LocalFocusManager.current

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        // ── Selected customer chip ──────────────────────────────────────
        if (selectedCustomer != null || isWalkIn) {
            item(key = "selected") {
                SelectedCustomerBanner(
                    customer = selectedCustomer,
                    isWalkIn = isWalkIn,
                    onClear = onClear,
                )
            }
        }

        // ── Search field ────────────────────────────────────────────────
        item(key = "search") {
            OutlinedTextField(
                value = query,
                onValueChange = onQueryChange,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Search customers") },
                leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                trailingIcon = {
                    if (isSearching) CircularProgressIndicator(modifier = Modifier.size(20.dp))
                },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                keyboardActions = KeyboardActions(onSearch = { focusManager.clearFocus() }),
            )
        }

        // ── Search results ─────────────────────────────────────────────
        items(results, key = { "result_${it.id}" }) { customer ->
            CustomerResultRow(
                customer = customer,
                isSelected = selectedCustomer?.id == customer.id,
                onSelect = { onSelect(customer) },
            )
        }

        // ── Walk-in + New customer actions ────────────────────────────
        item(key = "actions") {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                OutlinedButton(
                    onClick = onSelectWalkIn,
                    modifier = Modifier.weight(1f),
                ) {
                    Text(if (isWalkIn) "Walk-in selected" else "Walk-in")
                }
                OutlinedButton(
                    onClick = onToggleNewCustomerForm,
                    modifier = Modifier.weight(1f),
                ) {
                    Text(if (showNewCustomerForm) "Cancel" else "New customer")
                }
            }
        }

        // ── Inline new-customer form ────────────────────────────────────
        if (showNewCustomerForm) {
            item(key = "new_cust_form") {
                NewCustomerForm(
                    firstName = newCustFirstName,
                    lastName = newCustLastName,
                    phone = newCustPhone,
                    email = newCustEmail,
                    isCreating = isCreatingCustomer,
                    onFirstNameChange = onNewCustFirstNameChange,
                    onLastNameChange = onNewCustLastNameChange,
                    onPhoneChange = onNewCustPhoneChange,
                    onEmailChange = onNewCustEmailChange,
                    onSubmit = onCreateAndSelect,
                )
            }
        }
    }
}

// ── Private sub-composables ─────────────────────────────────────────────────

@Composable
private fun SelectedCustomerBanner(
    customer: CustomerListItem?,
    isWalkIn: Boolean,
    onClear: () -> Unit,
) {
    val name = when {
        isWalkIn -> "Walk-in customer"
        customer != null -> listOfNotNull(customer.firstName, customer.lastName).joinToString(" ").ifBlank { "Unknown" }
        else -> ""
    }
    if (name.isEmpty()) return

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.primaryContainer,
        ),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Default.Check, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.width(8.dp))
            Column(Modifier.weight(1f)) {
                Text(name, style = MaterialTheme.typography.bodyLarge)
                customer?.phone?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
            }
            TextButton(onClick = onClear) { Text("Change") }
        }
    }
}

@Composable
private fun CustomerResultRow(
    customer: CustomerListItem,
    isSelected: Boolean,
    onSelect: () -> Unit,
) {
    val name = listOfNotNull(customer.firstName, customer.lastName).joinToString(" ").ifBlank { customer.organization ?: "Unknown" }
    ListItem(
        headlineContent = { Text(name) },
        supportingContent = {
            Text(listOfNotNull(customer.phone ?: customer.mobile, customer.email).joinToString(" · "))
        },
        leadingContent = {
            Icon(Icons.Default.Person, contentDescription = null)
        },
        trailingContent = {
            if (isSelected) Icon(Icons.Default.Check, contentDescription = "Selected", tint = MaterialTheme.colorScheme.primary)
        },
        modifier = Modifier.clickable(onClick = onSelect),
    )
    HorizontalDivider()
}

@Composable
private fun NewCustomerForm(
    firstName: String,
    lastName: String,
    phone: String,
    email: String,
    isCreating: Boolean,
    onFirstNameChange: (String) -> Unit,
    onLastNameChange: (String) -> Unit,
    onPhoneChange: (String) -> Unit,
    onEmailChange: (String) -> Unit,
    onSubmit: () -> Unit,
) {
    val focusManager = LocalFocusManager.current
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text("New Customer", style = MaterialTheme.typography.titleSmall)

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = firstName,
                    onValueChange = onFirstNameChange,
                    modifier = Modifier.weight(1f),
                    label = { Text("First name*") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                    keyboardActions = KeyboardActions(onNext = { focusManager.moveFocus(FocusDirection.Next) }),
                )
                OutlinedTextField(
                    value = lastName,
                    onValueChange = onLastNameChange,
                    modifier = Modifier.weight(1f),
                    label = { Text("Last name") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                    keyboardActions = KeyboardActions(onNext = { focusManager.moveFocus(FocusDirection.Next) }),
                )
            }
            OutlinedTextField(
                value = phone,
                onValueChange = onPhoneChange,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Phone*") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone, imeAction = ImeAction.Next),
                keyboardActions = KeyboardActions(onNext = { focusManager.moveFocus(FocusDirection.Next) }),
            )
            OutlinedTextField(
                value = email,
                onValueChange = onEmailChange,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Email") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email, imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { focusManager.clearFocus() }),
            )
            Button(
                onClick = onSubmit,
                enabled = firstName.isNotBlank() && phone.isNotBlank() && !isCreating,
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (isCreating) {
                    CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                } else {
                    Text("Create & Select")
                }
            }
        }
    }
}
