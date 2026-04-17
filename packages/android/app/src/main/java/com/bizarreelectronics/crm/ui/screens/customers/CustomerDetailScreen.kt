package com.bizarreelectronics.crm.ui.screens.customers

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.entities.CustomerEntity
import com.bizarreelectronics.crm.data.remote.dto.UpdateCustomerRequest
import com.bizarreelectronics.crm.data.repository.CustomerRepository
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.util.formatPhoneDisplay
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import javax.inject.Inject

data class CustomerDetailUiState(
    val customer: CustomerEntity? = null,
    val isLoading: Boolean = true,
    val error: String? = null,
    val isEditing: Boolean = false,
    val isSaving: Boolean = false,
    val editFirstName: String = "",
    val editLastName: String = "",
    val editPhone: String = "",
    val editEmail: String = "",
    val editOrganization: String = "",
    val editAddress: String = "",
    val editCity: String = "",
    val editState: String = "",
    /** Comma-separated tag list, matching the web app's Tags field. */
    val editTags: String = "",
    /** Currently assigned customer group id. Full group dropdown TBD; for now edit supports clearing. */
    val editGroupId: Long? = null,
    /** Display-only group name snapshot captured when editing begins. */
    val editGroupName: String? = null,
    val saveMessage: String? = null,
)

@HiltViewModel
class CustomerDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val customerRepository: CustomerRepository,
) : ViewModel() {

    private val customerId: Long = savedStateHandle.get<String>("id")?.toLongOrNull() ?: 0L

    private val _state = MutableStateFlow(CustomerDetailUiState())
    val state = _state.asStateFlow()
    private var collectJob: Job? = null

    init {
        loadCustomer()
    }

    fun loadCustomer() {
        collectJob?.cancel()
        collectJob = viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                customerRepository.getCustomer(customerId).collectLatest { customer ->
                    _state.value = _state.value.copy(customer = customer, isLoading = false)
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = "Failed to load customer details. Check your connection and try again.",
                )
            }
        }
    }

    fun startEditing() {
        val c = _state.value.customer ?: return
        _state.value = _state.value.copy(
            isEditing = true,
            editFirstName = c.firstName ?: "",
            editLastName = c.lastName ?: "",
            editPhone = c.mobile ?: c.phone ?: "",
            editEmail = c.email ?: "",
            editOrganization = c.organization ?: "",
            editAddress = c.address1 ?: "",
            editCity = c.city ?: "",
            editState = c.state ?: "",
            editTags = c.tags ?: "",
            editGroupId = c.groupId,
            editGroupName = c.groupName,
        )
    }

    fun cancelEditing() {
        _state.value = _state.value.copy(isEditing = false)
    }

    fun updateEditFirstName(value: String) { _state.value = _state.value.copy(editFirstName = value) }
    fun updateEditLastName(value: String) { _state.value = _state.value.copy(editLastName = value) }
    fun updateEditPhone(value: String) { _state.value = _state.value.copy(editPhone = value) }
    fun updateEditEmail(value: String) { _state.value = _state.value.copy(editEmail = value) }
    fun updateEditOrganization(value: String) { _state.value = _state.value.copy(editOrganization = value) }
    fun updateEditAddress(value: String) { _state.value = _state.value.copy(editAddress = value) }
    fun updateEditCity(value: String) { _state.value = _state.value.copy(editCity = value) }
    fun updateEditState(value: String) { _state.value = _state.value.copy(editState = value) }
    fun updateEditTags(value: String) { _state.value = _state.value.copy(editTags = value) }
    fun clearEditGroup() { _state.value = _state.value.copy(editGroupId = null, editGroupName = null) }

    fun clearSaveMessage() {
        _state.value = _state.value.copy(saveMessage = null)
    }

    fun saveCustomer() {
        val current = _state.value
        if (current.editFirstName.isBlank()) {
            _state.value = current.copy(saveMessage = "First name is required")
            return
        }

        viewModelScope.launch {
            _state.value = _state.value.copy(isSaving = true)
            try {
                val request = UpdateCustomerRequest(
                    firstName = current.editFirstName.trim(),
                    lastName = current.editLastName.trim().ifBlank { null },
                    phone = current.editPhone.trim().ifBlank { null },
                    email = current.editEmail.trim().ifBlank { null },
                    organization = current.editOrganization.trim().ifBlank { null },
                    address1 = current.editAddress.trim().ifBlank { null },
                    city = current.editCity.trim().ifBlank { null },
                    state = current.editState.trim().ifBlank { null },
                    customerTags = current.editTags
                        .split(",")
                        .map { it.trim() }
                        .filter { it.isNotBlank() }
                        .joinToString(", ")
                        .ifBlank { null },
                    customerGroupId = current.editGroupId,
                )
                customerRepository.updateCustomer(customerId, request)
                _state.value = _state.value.copy(
                    isEditing = false,
                    isSaving = false,
                    saveMessage = "Customer updated",
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isSaving = false,
                    saveMessage = e.message ?: "Failed to update customer",
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CustomerDetailScreen(
    customerId: Long,
    onBack: () -> Unit,
    onNavigateToTicket: (Long) -> Unit,
    onNavigateToSms: ((String) -> Unit)? = null,
    viewModel: CustomerDetailViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val customer = state.customer
    val context = LocalContext.current
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(state.saveMessage) {
        val msg = state.saveMessage
        if (msg != null) {
            snackbarHostState.showSnackbar(msg)
            viewModel.clearSaveMessage()
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            BrandTopAppBar(
                title = when {
                    state.isEditing -> "Edit customer"
                    else -> customer?.let {
                        listOfNotNull(it.firstName, it.lastName)
                            .joinToString(" ")
                            .ifBlank { null }
                    } ?: if (state.isLoading) "Loading..." else "Customer #$customerId"
                },
                navigationIcon = {
                    IconButton(onClick = {
                        if (state.isEditing) viewModel.cancelEditing() else onBack()
                    }) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                        )
                    }
                },
                actions = {
                    if (state.isEditing) {
                        if (state.isSaving) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(24.dp),
                                strokeWidth = 2.dp,
                            )
                            Spacer(modifier = Modifier.width(16.dp))
                        } else {
                            TextButton(
                                onClick = { viewModel.saveCustomer() },
                                enabled = state.editFirstName.isNotBlank(),
                                colors = ButtonDefaults.textButtonColors(
                                    contentColor = MaterialTheme.colorScheme.primary,
                                ),
                            ) {
                                Text("Save")
                            }
                        }
                    } else {
                        IconButton(onClick = { viewModel.startEditing() }) {
                            Icon(
                                Icons.Default.Edit,
                                contentDescription = "Edit",
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                },
            )
        },
    ) { padding ->
        when {
            state.isLoading -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            }
            state.error != null -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    ErrorState(
                        message = state.error ?: "Error",
                        onRetry = { viewModel.loadCustomer() },
                    )
                }
            }
            state.isEditing -> {
                CustomerEditContent(
                    state = state,
                    padding = padding,
                    viewModel = viewModel,
                )
            }
            customer != null -> {
                CustomerDetailContent(
                    customer = customer,
                    padding = padding,
                    onNavigateToTicket = onNavigateToTicket,
                    onCallPhone = { phone ->
                        val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:$phone"))
                        context.startActivity(intent)
                    },
                    onSmsPhone = { phone ->
                        if (onNavigateToSms != null) {
                            val normalized = phone.replace(Regex("[^0-9]"), "").let {
                                if (it.length == 11 && it.startsWith("1")) it.substring(1) else it
                            }
                            onNavigateToSms(normalized)
                        } else {
                            val intent = Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:$phone"))
                            context.startActivity(intent)
                        }
                    },
                )
            }
        }
    }
}

@Composable
private fun CustomerEditContent(
    state: CustomerDetailUiState,
    padding: PaddingValues,
    viewModel: CustomerDetailViewModel,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding)
            .imePadding()
            .padding(16.dp)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        OutlinedTextField(
            value = state.editFirstName,
            onValueChange = viewModel::updateEditFirstName,
            modifier = Modifier.fillMaxWidth(),
            label = { Text("First Name *") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
        )

        OutlinedTextField(
            value = state.editLastName,
            onValueChange = viewModel::updateEditLastName,
            modifier = Modifier.fillMaxWidth(),
            label = { Text("Last Name") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
        )

        OutlinedTextField(
            value = state.editPhone,
            onValueChange = viewModel::updateEditPhone,
            modifier = Modifier.fillMaxWidth(),
            label = { Text("Phone") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(
                keyboardType = KeyboardType.Phone,
                imeAction = ImeAction.Next,
            ),
        )

        OutlinedTextField(
            value = state.editEmail,
            onValueChange = viewModel::updateEditEmail,
            modifier = Modifier.fillMaxWidth(),
            label = { Text("Email") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(
                keyboardType = KeyboardType.Email,
                imeAction = ImeAction.Next,
            ),
        )

        OutlinedTextField(
            value = state.editOrganization,
            onValueChange = viewModel::updateEditOrganization,
            modifier = Modifier.fillMaxWidth(),
            label = { Text("Organization") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
        )

        OutlinedTextField(
            value = state.editAddress,
            onValueChange = viewModel::updateEditAddress,
            modifier = Modifier.fillMaxWidth(),
            label = { Text("Address") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            OutlinedTextField(
                value = state.editCity,
                onValueChange = viewModel::updateEditCity,
                modifier = Modifier.weight(1f),
                label = { Text("City") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
            )

            OutlinedTextField(
                value = state.editState,
                onValueChange = viewModel::updateEditState,
                modifier = Modifier.weight(1f),
                label = { Text("State") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
            )
        }

        // Tags (comma-separated)
        OutlinedTextField(
            value = state.editTags,
            onValueChange = viewModel::updateEditTags,
            modifier = Modifier.fillMaxWidth(),
            label = { Text("Tags") },
            placeholder = { Text("tag1, tag2, tag3") },
            supportingText = { Text("Comma-separated") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
        )

        // Group (read-only display + clear button; full group picker requires groups API)
        BrandCard(modifier = Modifier.fillMaxWidth()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        "Group",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        state.editGroupName ?: "None",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
                if (state.editGroupId != null) {
                    TextButton(
                        onClick = { viewModel.clearEditGroup() },
                        colors = ButtonDefaults.textButtonColors(
                            contentColor = MaterialTheme.colorScheme.secondary, // teal
                        ),
                    ) {
                        Text("Clear")
                    }
                }
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            OutlinedButton(
                onClick = { viewModel.cancelEditing() },
                modifier = Modifier.weight(1f),
            ) {
                Text("Cancel")
            }
            Button(
                onClick = { viewModel.saveCustomer() },
                modifier = Modifier.weight(1f),
                enabled = state.editFirstName.isNotBlank() && !state.isSaving,
            ) {
                if (state.isSaving) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onPrimary,
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                }
                Text("Save")
            }
        }
    }
}

@Composable
private fun CustomerDetailContent(
    customer: CustomerEntity,
    padding: PaddingValues,
    onNavigateToTicket: (Long) -> Unit,
    onCallPhone: (String) -> Unit,
    onSmsPhone: (String) -> Unit,
) {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Quick action buttons
        item {
            val primaryPhone = customer.mobile ?: customer.phone
            if (primaryPhone != null) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Button(
                        onClick = { onCallPhone(primaryPhone) },
                        modifier = Modifier.weight(1f),
                    ) {
                        Icon(Icons.Default.Phone, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Call")
                    }
                    OutlinedButton(
                        onClick = { onSmsPhone(primaryPhone) },
                        modifier = Modifier.weight(1f),
                    ) {
                        Icon(Icons.Default.Sms, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("SMS")
                    }
                }
            }
        }

        // Contact info card — BrandCard
        item {
            BrandCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(
                        "Contact info",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                    )

                    // Phone numbers from entity fields
                    val allPhones = buildList {
                        customer.mobile?.let { add(it to "Mobile") }
                        customer.phone?.let { add(it to "Phone") }
                    }.distinctBy { it.first }

                    allPhones.forEach { (phone, label) ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { onCallPhone(phone) },
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(
                                Icons.Default.Phone,
                                contentDescription = null,
                                modifier = Modifier.size(16.dp),
                                tint = MaterialTheme.colorScheme.primary,
                            )
                            Column {
                                Text(
                                    formatPhoneDisplay(phone),
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.primary,
                                )
                                Text(
                                    label,
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }

                    // Email
                    if (!customer.email.isNullOrBlank()) {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(
                                Icons.Default.Email,
                                contentDescription = null,
                                modifier = Modifier.size(16.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Text(customer.email, style = MaterialTheme.typography.bodyMedium)
                        }
                    }

                    // Address
                    val address = buildList {
                        customer.address1?.let { add(it) }
                        customer.address2?.let { add(it) }
                        val cityStateZip = listOfNotNull(customer.city, customer.state, customer.postcode)
                            .filter { it.isNotBlank() }
                            .joinToString(", ")
                        if (cityStateZip.isNotBlank()) add(cityStateZip)
                    }.joinToString("\n")

                    if (address.isNotBlank()) {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.Top,
                        ) {
                            Icon(
                                Icons.Default.LocationOn,
                                contentDescription = null,
                                modifier = Modifier.size(16.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Text(address, style = MaterialTheme.typography.bodyMedium)
                        }
                    }

                    if (!customer.organization.isNullOrBlank()) {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(
                                Icons.Default.Business,
                                contentDescription = null,
                                modifier = Modifier.size(16.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Text(customer.organization, style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                }
            }
        }

        // Tags — BrandCard
        if (!customer.tags.isNullOrBlank()) {
            item {
                BrandCard(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text(
                            "Tags",
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(
                            customer.tags,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }

        // Comments — BrandCard
        if (!customer.comments.isNullOrBlank()) {
            item {
                BrandCard(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text(
                            "Notes",
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(
                            customer.comments,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }
}
