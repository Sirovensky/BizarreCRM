package com.bizarreelectronics.crm.ui.screens.customers

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.draft.DraftStore
import com.bizarreelectronics.crm.data.remote.dto.CreateCustomerRequest
import com.bizarreelectronics.crm.data.repository.CustomerRepository
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
import javax.inject.Inject

private const val DRAFT_AUTOSAVE_DEBOUNCE_MS = 2_000L

data class CustomerCreateUiState(
    val firstName: String = "",
    val lastName: String = "",
    val phone: String = "",
    val email: String = "",
    val organization: String = "",
    val address: String = "",
    val city: String = "",
    val state: String = "",
    val isSubmitting: Boolean = false,
    val error: String? = null,
    val createdId: Long? = null,
)

@HiltViewModel
class CustomerCreateViewModel @Inject constructor(
    private val customerRepository: CustomerRepository,
    private val savedStateHandle: SavedStateHandle,
    private val draftStore: DraftStore,
    private val gson: Gson,
) : ViewModel() {

    // AUDIT-AND-037: key constants for process-death survival. We persist all
    // visible form fields so the user's typed input is not lost when Android
    // kills the process while the form is open (e.g. incoming call).
    private companion object {
        const val KEY_FIRST_NAME = "cust_create_first_name"
        const val KEY_LAST_NAME  = "cust_create_last_name"
        const val KEY_PHONE      = "cust_create_phone"
        const val KEY_EMAIL      = "cust_create_email"
        const val KEY_ORG        = "cust_create_org"
        const val KEY_ADDRESS    = "cust_create_address"
        const val KEY_CITY       = "cust_create_city"
        const val KEY_STATE      = "cust_create_state"
    }

    private val _state = MutableStateFlow(
        // AUDIT-AND-037: restore persisted form fields on process-death recreate.
        CustomerCreateUiState(
            firstName    = savedStateHandle.get<String>(KEY_FIRST_NAME) ?: "",
            lastName     = savedStateHandle.get<String>(KEY_LAST_NAME)  ?: "",
            phone        = savedStateHandle.get<String>(KEY_PHONE)      ?: "",
            email        = savedStateHandle.get<String>(KEY_EMAIL)      ?: "",
            organization = savedStateHandle.get<String>(KEY_ORG)        ?: "",
            address      = savedStateHandle.get<String>(KEY_ADDRESS)    ?: "",
            city         = savedStateHandle.get<String>(KEY_CITY)       ?: "",
            state        = savedStateHandle.get<String>(KEY_STATE)      ?: "",
        )
    )
    val state = _state.asStateFlow()

    private val _pendingDraft = MutableStateFlow<DraftStore.Draft?>(null)
    val pendingDraft: StateFlow<DraftStore.Draft?> = _pendingDraft.asStateFlow()

    private var autosaveJob: Job? = null

    init {
        // Load any persisted draft for the customer-create form.
        // Only surface the recovery prompt when the form is truly empty —
        // process-death restore via SavedStateHandle already covered typed
        // input, so a stale draft from a previous session would be confusing
        // noise if the user already has text in a field.
        viewModelScope.launch {
            val draft = draftStore.load(DraftStore.DraftType.CUSTOMER)
            if (draft != null && isFormEmpty()) {
                _pendingDraft.value = draft
            }
        }
    }

    private fun isFormEmpty(): Boolean {
        val s = _state.value
        return s.firstName.isBlank() && s.lastName.isBlank() && s.phone.isBlank() &&
            s.email.isBlank() && s.organization.isBlank() && s.address.isBlank() &&
            s.city.isBlank() && s.state.isBlank()
    }

    fun updateFirstName(value: String) {
        _state.value = _state.value.copy(firstName = value)
        savedStateHandle[KEY_FIRST_NAME] = value
        onFieldChanged()
    }

    fun updateLastName(value: String) {
        _state.value = _state.value.copy(lastName = value)
        savedStateHandle[KEY_LAST_NAME] = value
        onFieldChanged()
    }

    fun updatePhone(value: String) {
        // CROSS7: normalize + format on input so phones save in canonical
        // "+1 (XXX)-XXX-XXXX" shape instead of raw 5555551234. Accepts paste,
        // handles partial input, and strips unintended characters.
        val formatted = formatPhoneInput(value)
        _state.value = _state.value.copy(phone = formatted)
        savedStateHandle[KEY_PHONE] = formatted
        onFieldChanged()
    }

    fun updateEmail(value: String) {
        _state.value = _state.value.copy(email = value)
        savedStateHandle[KEY_EMAIL] = value
        onFieldChanged()
    }

    fun updateOrganization(value: String) {
        _state.value = _state.value.copy(organization = value)
        savedStateHandle[KEY_ORG] = value
        onFieldChanged()
    }

    fun updateAddress(value: String) {
        _state.value = _state.value.copy(address = value)
        savedStateHandle[KEY_ADDRESS] = value
        onFieldChanged()
    }

    fun updateCity(value: String) {
        _state.value = _state.value.copy(city = value)
        savedStateHandle[KEY_CITY] = value
        onFieldChanged()
    }

    fun updateState(value: String) {
        _state.value = _state.value.copy(state = value)
        savedStateHandle[KEY_STATE] = value
        onFieldChanged()
    }

    fun clearError() {
        _state.value = _state.value.copy(error = null)
    }

    // ── Draft autosave ────────────────────────────────────────────────

    /**
     * Call this after every user-driven field change.
     * Cancels the previous pending autosave and starts a new 2-second
     * countdown before persisting the current form state to DraftStore.
     */
    fun onFieldChanged() {
        autosaveJob?.cancel()
        autosaveJob = viewModelScope.launch {
            delay(DRAFT_AUTOSAVE_DEBOUNCE_MS)
            val json = serializeCurrentForm()
            draftStore.save(DraftStore.DraftType.CUSTOMER, json)
        }
    }

    /** Serialise the form fields needed to restore the customer-create form. */
    private fun serializeCurrentForm(): String {
        val s = _state.value
        val obj = JsonObject()
        if (s.firstName.isNotBlank()) obj.addProperty("firstName", s.firstName)
        if (s.lastName.isNotBlank()) obj.addProperty("lastName", s.lastName)
        if (s.phone.isNotBlank()) obj.addProperty("phone", s.phone)
        if (s.email.isNotBlank()) obj.addProperty("email", s.email)
        if (s.organization.isNotBlank()) obj.addProperty("organization", s.organization)
        if (s.address.isNotBlank()) obj.addProperty("address", s.address)
        if (s.city.isNotBlank()) obj.addProperty("city", s.city)
        if (s.state.isNotBlank()) obj.addProperty("state", s.state)
        return gson.toJson(obj)
    }

    /**
     * Restore the form state from a persisted draft.
     * Directly restores all text fields — no additional API calls required
     * for a customer form (unlike tickets which need customer/device lookups).
     */
    fun resumeDraft(draft: DraftStore.Draft) {
        _pendingDraft.value = null
        val obj = try {
            JsonParser.parseString(draft.payloadJson).asJsonObject
        } catch (_: Exception) {
            return
        }
        val firstName    = obj.get("firstName")?.takeIf { !it.isJsonNull }?.asString ?: ""
        val lastName     = obj.get("lastName")?.takeIf { !it.isJsonNull }?.asString ?: ""
        val phone        = obj.get("phone")?.takeIf { !it.isJsonNull }?.asString ?: ""
        val email        = obj.get("email")?.takeIf { !it.isJsonNull }?.asString ?: ""
        val organization = obj.get("organization")?.takeIf { !it.isJsonNull }?.asString ?: ""
        val address      = obj.get("address")?.takeIf { !it.isJsonNull }?.asString ?: ""
        val city         = obj.get("city")?.takeIf { !it.isJsonNull }?.asString ?: ""
        val stateField   = obj.get("state")?.takeIf { !it.isJsonNull }?.asString ?: ""
        _state.value = _state.value.copy(
            firstName    = firstName,
            lastName     = lastName,
            phone        = phone,
            email        = email,
            organization = organization,
            address      = address,
            city         = city,
            state        = stateField,
        )
        // Sync restored values back to SavedStateHandle for process-death safety.
        savedStateHandle[KEY_FIRST_NAME] = firstName
        savedStateHandle[KEY_LAST_NAME]  = lastName
        savedStateHandle[KEY_PHONE]      = phone
        savedStateHandle[KEY_EMAIL]      = email
        savedStateHandle[KEY_ORG]        = organization
        savedStateHandle[KEY_ADDRESS]    = address
        savedStateHandle[KEY_CITY]       = city
        savedStateHandle[KEY_STATE]      = stateField
    }

    /** Permanently discard the pending draft and clear the recovery prompt. */
    fun discardDraft() {
        _pendingDraft.value = null
        viewModelScope.launch {
            draftStore.discard(DraftStore.DraftType.CUSTOMER)
        }
    }

    fun save() {
        val current = _state.value
        // N7 fix: mirror server-side validation so users get a clear error
        // BEFORE a round trip to a server that will reject the payload.
        // - firstName: required, non-blank after trim, max 255 chars
        // - email: if provided, must match the server's regex
        // - phone: if provided, must be 10–15 digits after stripping symbols
        val trimmedFirstName = current.firstName.trim()
        if (trimmedFirstName.isEmpty()) {
            _state.value = current.copy(error = "First name is required")
            return
        }
        if (trimmedFirstName.length > 255) {
            _state.value = current.copy(error = "First name is too long (max 255 characters)")
            return
        }

        val trimmedEmail = current.email.trim()
        if (trimmedEmail.isNotEmpty()) {
            if (trimmedEmail.length > 254) {
                _state.value = current.copy(error = "Email is too long")
                return
            }
            // Match server regex (packages/server/src/utils/validate.ts).
            val emailRegex = Regex(
                "^[^\\s@.]+(?:\\.[^\\s@.]+)*@[^\\s@.]+(?:\\.[^\\s@.]+)*\\.[^\\s@.]{2,}$",
            )
            if (!emailRegex.matches(trimmedEmail.lowercase())) {
                _state.value = current.copy(error = "Enter a valid email address")
                return
            }
        }

        val trimmedPhone = current.phone.trim()
        if (trimmedPhone.isNotEmpty()) {
            val digits = trimmedPhone.filter { it.isDigit() }
            if (digits.length !in 10..15) {
                _state.value = current.copy(
                    error = "Phone number must be 10-15 digits",
                )
                return
            }
        }

        viewModelScope.launch {
            _state.value = _state.value.copy(isSubmitting = true, error = null)
            try {
                val request = CreateCustomerRequest(
                    firstName = current.firstName.trim(),
                    lastName = current.lastName.trim().ifBlank { null },
                    phone = current.phone.trim().ifBlank { null },
                    email = current.email.trim().ifBlank { null },
                    organization = current.organization.trim().ifBlank { null },
                    address1 = current.address.trim().ifBlank { null },
                    city = current.city.trim().ifBlank { null },
                    state = current.state.trim().ifBlank { null },
                )
                val createdId = customerRepository.createCustomer(request)
                // Customer created successfully — draft is no longer needed.
                discardDraft()
                _state.value = _state.value.copy(
                    isSubmitting = false,
                    createdId = createdId,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isSubmitting = false,
                    error = e.message ?: "Failed to create customer",
                )
            }
        }
    }
}

// CROSS7: Format a phone-number input as the user types. The TextField always
// feeds us the full current value, which includes our own "+1 (" prefix from
// the previous onValueChange — that prefix must not be counted as user input.
// Strategy: strip any known country-code prefix (+1, 1, etc.) that our formatter
// might have added, then keep only digits from what remains. Result is the user-
// typed local digits (max 10). Partial inputs get partial formatting — "555" →
// "+1 (555", "5555" → "+1 (555)-5". Matches MEMORY rule "+1 (XXX)-XXX-XXXX".
private fun formatPhoneInput(raw: String): String {
    if (raw.isBlank()) return ""
    // Strip our own country-code prefix first so "+1 (555" + user typing "5"
    // doesn't double-count the "1". Variants handled: "+1 (", "+1", "1 ".
    val withoutPrefix = raw
        .removePrefix("+1 (")
        .let { if (it === raw) raw.removePrefix("+1 ") else it }
        .let { if (it === raw) raw.removePrefix("+1") else it }
    var digits = withoutPrefix.filter { it.isDigit() }
    // Defense in depth: if somehow we still have 11 digits starting with 1
    // (e.g. paste of "15555551234"), strip the leading 1.
    if (digits.length == 11 && digits.startsWith("1")) digits = digits.drop(1)
    if (digits.length > 10) digits = digits.take(10)
    return when {
        digits.isEmpty() -> ""
        digits.length <= 3 -> "+1 ($digits"
        digits.length <= 6 -> "+1 (${digits.substring(0, 3)})-${digits.substring(3)}"
        else -> "+1 (${digits.substring(0, 3)})-${digits.substring(3, 6)}-${digits.substring(6)}"
    }
}

/**
 * Build a short, human-readable preview string from a customer draft payload JSON.
 * Used by [DraftRecoveryPrompt] so the user can identify the draft at a glance.
 *
 * Example outputs:
 *   "Jane Doe — +1 (555)-123-4567 — jane@example.com"
 *   "John — Bizarre Electronics"
 *   "New customer (no details)"
 */
private fun buildCustomerDraftPreview(json: String): String {
    return try {
        val obj = JsonParser.parseString(json).asJsonObject
        val parts = mutableListOf<String>()
        val firstName = obj.get("firstName")?.takeIf { !it.isJsonNull }?.asString
        val lastName  = obj.get("lastName")?.takeIf { !it.isJsonNull }?.asString
        val nameStr   = listOfNotNull(firstName, lastName).joinToString(" ").trim()
        if (nameStr.isNotBlank()) parts.add(nameStr)
        val phone = obj.get("phone")?.takeIf { !it.isJsonNull }?.asString
        if (!phone.isNullOrBlank()) parts.add(phone)
        val email = obj.get("email")?.takeIf { !it.isJsonNull }?.asString
        if (!email.isNullOrBlank()) parts.add(email)
        val org = obj.get("organization")?.takeIf { !it.isJsonNull }?.asString
        if (!org.isNullOrBlank()) parts.add(org)
        if (parts.isEmpty()) "New customer (no details)" else parts.joinToString(" — ")
    } catch (_: Exception) {
        "New customer"
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CustomerCreateScreen(
    onBack: () -> Unit,
    onCreated: (Long) -> Unit,
    viewModel: CustomerCreateViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val pendingDraft by viewModel.pendingDraft.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    // D5-6: IME actions need explicit handlers — Next advances focus, Done
    // clears focus and submits through the same path the toolbar Save uses.
    val focusManager = LocalFocusManager.current
    val onNext = KeyboardActions(onNext = { focusManager.moveFocus(FocusDirection.Down) })
    val onDoneSave = KeyboardActions(
        onDone = {
            focusManager.clearFocus()
            viewModel.save()
        },
    )

    // Navigate on successful creation
    LaunchedEffect(state.createdId) {
        val id = state.createdId
        if (id != null) {
            onCreated(id)
        }
    }

    // Show error via snackbar
    LaunchedEffect(state.error) {
        val error = state.error
        if (error != null) {
            snackbarHostState.showSnackbar(error)
            viewModel.clearError()
        }
    }

    // Draft recovery prompt — surfaces as a modal bottom sheet when a previously
    // saved draft exists and the form is currently empty (no SavedStateHandle
    // restore is active, i.e. this is genuinely a fresh open after a crash).
    val isFormEmpty = state.firstName.isBlank() && state.lastName.isBlank() &&
        state.phone.isBlank() && state.email.isBlank() &&
        state.organization.isBlank() && state.address.isBlank() &&
        state.city.isBlank() && state.state.isBlank()
    if (pendingDraft != null && isFormEmpty) {
        DraftRecoveryPrompt(
            draft = pendingDraft!!,
            previewFormatter = { json -> buildCustomerDraftPreview(json) },
            onResume = { viewModel.resumeDraft(pendingDraft!!) },
            onDiscard = { viewModel.discardDraft() },
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            BrandTopAppBar(
                title = "New Customer",
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
                        )
                        Spacer(modifier = Modifier.width(16.dp))
                    } else {
                        TextButton(
                            onClick = { viewModel.save() },
                            enabled = state.firstName.isNotBlank(),
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
            // OutlinedTextFields inherit purple focus ring from theme — no per-field overrides needed.

            OutlinedTextField(
                value = state.firstName,
                onValueChange = viewModel::updateFirstName,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("First Name *") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                keyboardActions = onNext,
            )

            OutlinedTextField(
                value = state.lastName,
                onValueChange = viewModel::updateLastName,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Last Name") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                keyboardActions = onNext,
            )

            OutlinedTextField(
                value = state.phone,
                onValueChange = viewModel::updatePhone,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Phone") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Phone,
                    imeAction = ImeAction.Next,
                ),
                keyboardActions = onNext,
            )

            OutlinedTextField(
                value = state.email,
                onValueChange = viewModel::updateEmail,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Email") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Email,
                    imeAction = ImeAction.Next,
                ),
                keyboardActions = onNext,
            )

            OutlinedTextField(
                value = state.organization,
                onValueChange = viewModel::updateOrganization,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Organization") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                keyboardActions = onNext,
            )

            OutlinedTextField(
                value = state.address,
                onValueChange = viewModel::updateAddress,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Address") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                keyboardActions = onNext,
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                OutlinedTextField(
                    value = state.city,
                    onValueChange = viewModel::updateCity,
                    modifier = Modifier.weight(1f),
                    label = { Text("City") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                    keyboardActions = onNext,
                )

                OutlinedTextField(
                    value = state.state,
                    onValueChange = viewModel::updateState,
                    modifier = Modifier.weight(1f),
                    label = { Text("State") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                    keyboardActions = onDoneSave,
                )
            }
        }
    }
}
