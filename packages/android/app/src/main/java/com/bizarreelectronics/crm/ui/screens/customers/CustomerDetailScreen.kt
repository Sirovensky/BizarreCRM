package com.bizarreelectronics.crm.ui.screens.customers

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.CustomerApi
import com.bizarreelectronics.crm.data.remote.dto.CustomerDetail
import com.bizarreelectronics.crm.data.remote.dto.UpdateCustomerRequest
import com.bizarreelectronics.crm.ui.theme.*
import com.bizarreelectronics.crm.util.DateFormatter
import com.bizarreelectronics.crm.util.PhoneFormatter
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class CustomerDetailUiState(
    val customer: CustomerDetail? = null,
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
    val saveMessage: String? = null,
)

@HiltViewModel
class CustomerDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val customerApi: CustomerApi,
) : ViewModel() {

    private val customerId: Long = savedStateHandle.get<String>("id")?.toLongOrNull() ?: 0L

    private val _state = MutableStateFlow(CustomerDetailUiState())
    val state = _state.asStateFlow()

    init {
        loadCustomer()
    }

    fun loadCustomer() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)
            try {
                val response = customerApi.getCustomer(customerId)
                val customer = response.data
                _state.value = _state.value.copy(customer = customer, isLoading = false)
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
                )
                val response = customerApi.updateCustomer(customerId, request)
                val updated = response.data
                _state.value = _state.value.copy(
                    customer = updated,
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
            TopAppBar(
                title = {
                    if (state.isEditing) {
                        Text("Edit Customer")
                    } else {
                        val name = customer?.let {
                            listOfNotNull(it.firstName, it.lastName)
                                .joinToString(" ")
                                .ifBlank { null }
                        } ?: if (state.isLoading) "Loading..." else "Customer #$customerId"
                        Text(name)
                    }
                },
                navigationIcon = {
                    IconButton(onClick = {
                        if (state.isEditing) viewModel.cancelEditing() else onBack()
                    }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
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
                            ) {
                                Text("Save")
                            }
                        }
                    } else {
                        IconButton(onClick = { viewModel.startEditing() }) {
                            Icon(Icons.Default.Edit, contentDescription = "Edit")
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
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(state.error ?: "Error", color = MaterialTheme.colorScheme.error)
                        Spacer(modifier = Modifier.height(8.dp))
                        TextButton(onClick = { viewModel.loadCustomer() }) { Text("Retry") }
                    }
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
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
            )
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
    customer: CustomerDetail,
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

        // Contact info card
        item {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text("Contact Info", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)

                    // Primary phone/mobile
                    val allPhones = buildList {
                        customer.mobile?.let { add(it to "Mobile") }
                        customer.phone?.let { add(it to "Phone") }
                        customer.phones?.forEach { add(it.phone to (it.label ?: "Phone")) }
                    }.distinctBy { it.first }

                    allPhones.forEach { (phone, label) ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { onCallPhone(phone) },
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(Icons.Default.Phone, contentDescription = null, modifier = Modifier.size(16.dp), tint = MaterialTheme.colorScheme.primary)
                            Column {
                                Text(PhoneFormatter.format(phone), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary)
                                Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }

                    // Emails
                    val allEmails = buildList {
                        customer.email?.let { add(it to "Primary") }
                        customer.emails?.forEach { add(it.email to (it.label ?: "Email")) }
                    }.distinctBy { it.first }

                    allEmails.forEach { (email, label) ->
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(Icons.Default.Email, contentDescription = null, modifier = Modifier.size(16.dp))
                            Column {
                                Text(email, style = MaterialTheme.typography.bodyMedium)
                                Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
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
                            Icon(Icons.Default.LocationOn, contentDescription = null, modifier = Modifier.size(16.dp))
                            Text(address, style = MaterialTheme.typography.bodyMedium)
                        }
                    }

                    if (!customer.organization.isNullOrBlank()) {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(Icons.Default.Business, contentDescription = null, modifier = Modifier.size(16.dp))
                            Text(customer.organization, style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                }
            }
        }

        // Tags
        if (!customer.customerTags.isNullOrBlank()) {
            item {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text("Tags", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(customer.customerTags, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }

        // Analytics card
        item {
            val ticketCount = customer.tickets?.size ?: 0
            val lifetimeValue = customer.tickets?.sumOf { it.total ?: 0.0 } ?: 0.0

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Card(modifier = Modifier.weight(1f)) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Text(
                            "$ticketCount",
                            style = MaterialTheme.typography.headlineMedium,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.primary,
                        )
                        Text("Tickets", style = MaterialTheme.typography.bodySmall)
                    }
                }
                Card(modifier = Modifier.weight(1f)) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Text(
                            String.format("$%.2f", lifetimeValue),
                            style = MaterialTheme.typography.headlineMedium,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.primary,
                        )
                        Text("Lifetime Value", style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }

        // Recent tickets
        val tickets = customer.tickets ?: emptyList()
        if (tickets.isNotEmpty()) {
            item {
                Text("Recent Tickets", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            }

            items(tickets.take(10), key = { it.id }) { ticket ->
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { onNavigateToTicket(ticket.id) },
                ) {
                    Row(
                        modifier = Modifier
                            .padding(12.dp)
                            .fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Column {
                            Text(ticket.orderId, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Medium)
                            val deviceName = ticket.devices?.firstOrNull()?.deviceName ?: ""
                            if (deviceName.isNotEmpty()) {
                                Text(deviceName, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                        Column(horizontalAlignment = Alignment.End) {
                            val ticketStatusBg = try {
                                Color(android.graphics.Color.parseColor(ticket.statusColor ?: "#6b7280"))
                            } catch (_: Exception) {
                                MaterialTheme.colorScheme.primary
                            }
                            Surface(
                                shape = MaterialTheme.shapes.small,
                                color = ticketStatusBg,
                            ) {
                                Text(
                                    ticket.statusName ?: "",
                                    modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = contrastTextColor(ticketStatusBg),
                                )
                            }
                            Spacer(modifier = Modifier.height(4.dp))
                            Text(
                                DateFormatter.formatDate(ticket.createdAt),
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
        }

        // Recent invoices
        val invoices = customer.invoices ?: emptyList()
        if (invoices.isNotEmpty()) {
            item {
                Text("Recent Invoices", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            }

            items(invoices.take(10), key = { it.id }) { invoice ->
                Card(modifier = Modifier.fillMaxWidth()) {
                    Row(
                        modifier = Modifier
                            .padding(12.dp)
                            .fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Column {
                            Text(invoice.orderId ?: "INV-${invoice.id}", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Medium)
                            Text(
                                DateFormatter.formatDate(invoice.createdAt),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Column(horizontalAlignment = Alignment.End) {
                            val invStatusColor = when (invoice.status) {
                                "Paid" -> SuccessGreen
                                "Unpaid" -> ErrorRed
                                "Partial" -> WarningAmber
                                else -> Color.Gray
                            }
                            Surface(shape = MaterialTheme.shapes.small, color = invStatusColor) {
                                Text(
                                    invoice.status ?: "",
                                    modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = contrastTextColor(invStatusColor),
                                )
                            }
                            Spacer(modifier = Modifier.height(4.dp))
                            Text(
                                String.format("$%.2f", invoice.total ?: 0.0),
                                style = MaterialTheme.typography.bodySmall,
                                fontWeight = FontWeight.Medium,
                            )
                        }
                    }
                }
            }
        }

        // Comments
        if (!customer.comments.isNullOrBlank()) {
            item {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text("Notes", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(customer.comments, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}
