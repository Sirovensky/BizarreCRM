package com.bizarreelectronics.crm.ui.screens.customers

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ContactPage
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.draft.DraftStore
import com.bizarreelectronics.crm.data.remote.api.CustomerApi
import com.bizarreelectronics.crm.data.remote.api.SettingsApi
import com.bizarreelectronics.crm.data.remote.dto.CreateCustomerRequest
import com.bizarreelectronics.crm.data.remote.dto.CustomerEmail
import com.bizarreelectronics.crm.data.remote.dto.CustomerListItem
import com.bizarreelectronics.crm.data.remote.dto.CustomerPhone
import com.bizarreelectronics.crm.data.repository.CustomerRepository
import com.bizarreelectronics.crm.ui.components.TagChip
import com.bizarreelectronics.crm.ui.components.hashTagToColor
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
import retrofit2.HttpException
import java.util.UUID
import javax.inject.Inject

private const val DRAFT_AUTOSAVE_DEBOUNCE_MS = 2_000L

/** A single row in the multi-phone list. */
data class PhoneEntry(val label: String = "Mobile", val number: String = "")

/** A single row in the multi-email list. */
data class EmailEntry(val label: String = "Home", val email: String = "")

data class CustomerCreateUiState(
    // Core identity
    val firstName: String = "",
    val lastName: String = "",
    val type: String = "individual", // "individual" | "business"

    // Multi-phone and multi-email
    val phones: List<PhoneEntry> = listOf(PhoneEntry()),
    val emails: List<EmailEntry> = listOf(EmailEntry()),

    // Legacy single fields kept for backward compat with draft restore
    val phone: String = "",
    val email: String = "",

    // Organization
    val organization: String = "",

    // Mailing address
    val address: String = "",
    val city: String = "",
    val state: String = "",
    val zip: String = "",

    // Billing address (shown when sameAsMailing = false)
    val sameAsMailing: Boolean = true,
    val billingAddress: String = "",
    val billingCity: String = "",
    val billingState: String = "",
    val billingZip: String = "",

    // Tags (free-form chip list)
    val tags: List<String> = emptyList(),
    val tagInput: String = "",

    // Communication preferences
    val smsOptIn: Boolean = true,
    val emailOptIn: Boolean = true,
    val phoneCallsOptIn: Boolean = true,

    // Referral source
    val referralSource: String = "",

    // Birthday (display string "MM/DD/YYYY" or blank)
    val birthday: String = "",

    // Notes
    val notes: String = "",

    // UI state
    val isSubmitting: Boolean = false,
    val error: String? = null,
    val createdId: Long? = null,

    // Duplicate detection
    val duplicateCandidates: List<CustomerListItem> = emptyList(),
    val showDuplicateDialog: Boolean = false,

    // Tag palette from server (tag label → Color)
    val tagPalette: Map<String, Color> = emptyMap(),
)

@HiltViewModel
class CustomerCreateViewModel @Inject constructor(
    private val customerRepository: CustomerRepository,
    private val customerApi: CustomerApi,
    private val settingsApi: SettingsApi,
    private val savedStateHandle: SavedStateHandle,
    private val draftStore: DraftStore,
    private val gson: Gson,
) : ViewModel() {

    private companion object {
        const val KEY_FIRST_NAME = "cust_create_first_name"
        const val KEY_LAST_NAME  = "cust_create_last_name"
        const val KEY_PHONE      = "cust_create_phone"
        const val KEY_EMAIL      = "cust_create_email"
        const val KEY_ORG        = "cust_create_org"
        const val KEY_ADDRESS    = "cust_create_address"
        const val KEY_CITY       = "cust_create_city"
        const val KEY_STATE      = "cust_create_state"
        const val KEY_ZIP        = "cust_create_zip"
        const val KEY_NOTES      = "cust_create_notes"
        const val KEY_TYPE       = "cust_create_type"
        const val KEY_REFERRAL   = "cust_create_referral"

        val REFERRAL_OPTIONS = listOf("", "Web", "Phone", "Referral", "Walk-in", "Other")
        val PHONE_LABELS = listOf("Mobile", "Home", "Work", "Other")
        val EMAIL_LABELS = listOf("Home", "Work", "Other")
    }

    private val _state = MutableStateFlow(
        CustomerCreateUiState(
            firstName    = savedStateHandle.get<String>(KEY_FIRST_NAME) ?: "",
            lastName     = savedStateHandle.get<String>(KEY_LAST_NAME)  ?: "",
            phone        = savedStateHandle.get<String>(KEY_PHONE)      ?: "",
            email        = savedStateHandle.get<String>(KEY_EMAIL)      ?: "",
            organization = savedStateHandle.get<String>(KEY_ORG)        ?: "",
            address      = savedStateHandle.get<String>(KEY_ADDRESS)    ?: "",
            city         = savedStateHandle.get<String>(KEY_CITY)       ?: "",
            state        = savedStateHandle.get<String>(KEY_STATE)      ?: "",
            zip          = savedStateHandle.get<String>(KEY_ZIP)        ?: "",
            notes        = savedStateHandle.get<String>(KEY_NOTES)      ?: "",
            type         = savedStateHandle.get<String>(KEY_TYPE)       ?: "individual",
            referralSource = savedStateHandle.get<String>(KEY_REFERRAL) ?: "",
            // Seed multi-phone/email from legacy single fields if present
            phones = run {
                val p = savedStateHandle.get<String>(KEY_PHONE) ?: ""
                if (p.isNotBlank()) listOf(PhoneEntry(number = p)) else listOf(PhoneEntry())
            },
            emails = run {
                val e = savedStateHandle.get<String>(KEY_EMAIL) ?: ""
                if (e.isNotBlank()) listOf(EmailEntry(email = e)) else listOf(EmailEntry())
            },
        )
    )
    val state = _state.asStateFlow()

    private val _pendingDraft = MutableStateFlow<DraftStore.Draft?>(null)
    val pendingDraft: StateFlow<DraftStore.Draft?> = _pendingDraft.asStateFlow()

    private var autosaveJob: Job? = null

    init {
        viewModelScope.launch {
            val draft = draftStore.load(DraftStore.DraftType.CUSTOMER)
            if (draft != null && isFormEmpty()) {
                _pendingDraft.value = draft
            }
        }
        loadTagPalette()
    }

    private fun loadTagPalette() {
        viewModelScope.launch {
            try {
                val response = settingsApi.getTagPalette()
                val raw = response.data ?: return@launch
                val palette = raw.mapValues { (_, hex) ->
                    try {
                        Color(android.graphics.Color.parseColor(hex))
                    } catch (_: Exception) {
                        hashTagToColor(hex)
                    }
                }
                _state.value = _state.value.copy(tagPalette = palette)
            } catch (_: HttpException) {
                // 404 expected — default palette cycle will be used
            } catch (_: Exception) {
                // silent degrade
            }
        }
    }

    private fun isFormEmpty(): Boolean {
        val s = _state.value
        return s.firstName.isBlank() && s.lastName.isBlank() &&
            s.phones.all { it.number.isBlank() } &&
            s.emails.all { it.email.isBlank() } &&
            s.organization.isBlank() && s.address.isBlank() &&
            s.city.isBlank() && s.state.isBlank() && s.notes.isBlank()
    }

    // ── Field updaters ────────────────────────────────────────────────

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

    fun updateType(value: String) {
        _state.value = _state.value.copy(type = value)
        savedStateHandle[KEY_TYPE] = value
        onFieldChanged()
    }

    // Multi-phone
    fun updatePhoneNumber(index: Int, number: String) {
        val formatted = formatPhoneInput(number)
        val updated = _state.value.phones.toMutableList().also { it[index] = it[index].copy(number = formatted) }
        _state.value = _state.value.copy(phones = updated)
        onFieldChanged()
    }

    fun updatePhoneLabel(index: Int, label: String) {
        val updated = _state.value.phones.toMutableList().also { it[index] = it[index].copy(label = label) }
        _state.value = _state.value.copy(phones = updated)
        onFieldChanged()
    }

    fun addPhone() {
        if (_state.value.phones.size >= 5) return
        _state.value = _state.value.copy(phones = _state.value.phones + PhoneEntry())
        onFieldChanged()
    }

    fun removePhone(index: Int) {
        if (_state.value.phones.size <= 1) return
        _state.value = _state.value.copy(phones = _state.value.phones.filterIndexed { i, _ -> i != index })
        onFieldChanged()
    }

    // Multi-email
    fun updateEmailAddress(index: Int, email: String) {
        val updated = _state.value.emails.toMutableList().also { it[index] = it[index].copy(email = email) }
        _state.value = _state.value.copy(emails = updated)
        onFieldChanged()
    }

    fun updateEmailLabel(index: Int, label: String) {
        val updated = _state.value.emails.toMutableList().also { it[index] = it[index].copy(label = label) }
        _state.value = _state.value.copy(emails = updated)
        onFieldChanged()
    }

    fun addEmail() {
        if (_state.value.emails.size >= 5) return
        _state.value = _state.value.copy(emails = _state.value.emails + EmailEntry())
        onFieldChanged()
    }

    fun removeEmail(index: Int) {
        if (_state.value.emails.size <= 1) return
        _state.value = _state.value.copy(emails = _state.value.emails.filterIndexed { i, _ -> i != index })
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

    fun updateZip(value: String) {
        _state.value = _state.value.copy(zip = value)
        savedStateHandle[KEY_ZIP] = value
        onFieldChanged()
    }

    fun updateSameAsMailing(value: Boolean) {
        _state.value = _state.value.copy(sameAsMailing = value)
        onFieldChanged()
    }

    fun updateBillingAddress(value: String) {
        _state.value = _state.value.copy(billingAddress = value)
        onFieldChanged()
    }

    fun updateBillingCity(value: String) {
        _state.value = _state.value.copy(billingCity = value)
        onFieldChanged()
    }

    fun updateBillingState(value: String) {
        _state.value = _state.value.copy(billingState = value)
        onFieldChanged()
    }

    fun updateBillingZip(value: String) {
        _state.value = _state.value.copy(billingZip = value)
        onFieldChanged()
    }

    // Tags
    fun updateTagInput(value: String) {
        _state.value = _state.value.copy(tagInput = value)
    }

    fun addTag() {
        val raw = _state.value.tagInput.trim()
        if (raw.isBlank()) return
        val existing = _state.value.tags
        if (!existing.contains(raw)) {
            _state.value = _state.value.copy(tags = existing + raw, tagInput = "")
        } else {
            _state.value = _state.value.copy(tagInput = "")
        }
        onFieldChanged()
    }

    fun removeTag(tag: String) {
        _state.value = _state.value.copy(tags = _state.value.tags.filter { it != tag })
        onFieldChanged()
    }

    // Communication prefs
    fun updateSmsOptIn(value: Boolean) {
        _state.value = _state.value.copy(smsOptIn = value)
        onFieldChanged()
    }

    fun updateEmailOptIn(value: Boolean) {
        _state.value = _state.value.copy(emailOptIn = value)
        onFieldChanged()
    }

    fun updatePhoneCallsOptIn(value: Boolean) {
        _state.value = _state.value.copy(phoneCallsOptIn = value)
        onFieldChanged()
    }

    fun updateReferralSource(value: String) {
        _state.value = _state.value.copy(referralSource = value)
        savedStateHandle[KEY_REFERRAL] = value
        onFieldChanged()
    }

    fun updateBirthday(value: String) {
        _state.value = _state.value.copy(birthday = value)
        onFieldChanged()
    }

    fun updateNotes(value: String) {
        _state.value = _state.value.copy(notes = value)
        savedStateHandle[KEY_NOTES] = value
        onFieldChanged()
    }

    // ── Contact import prefill ────────────────────────────────────────

    /** Called when the user picks a contact from the system picker. */
    fun prefillFromContact(displayName: String?, phone: String?, email: String?) {
        // Split display name into first/last heuristically
        val parts = displayName?.trim()?.split(" ", limit = 2) ?: emptyList()
        val first = parts.getOrNull(0) ?: ""
        val last  = parts.getOrNull(1) ?: ""

        val formattedPhone = phone?.let { formatPhoneInput(it) } ?: ""
        _state.value = _state.value.copy(
            firstName = first,
            lastName  = last,
            phones    = if (formattedPhone.isNotBlank()) listOf(PhoneEntry(number = formattedPhone)) else _state.value.phones,
            emails    = if (!email.isNullOrBlank()) listOf(EmailEntry(email = email)) else _state.value.emails,
        )
        savedStateHandle[KEY_FIRST_NAME] = first
        savedStateHandle[KEY_LAST_NAME]  = last
        onFieldChanged()
    }

    fun clearError() {
        _state.value = _state.value.copy(error = null)
    }

    // ── Draft autosave ────────────────────────────────────────────────

    fun onFieldChanged() {
        autosaveJob?.cancel()
        autosaveJob = viewModelScope.launch {
            delay(DRAFT_AUTOSAVE_DEBOUNCE_MS)
            val json = serializeCurrentForm()
            draftStore.save(DraftStore.DraftType.CUSTOMER, json)
        }
    }

    private fun serializeCurrentForm(): String {
        val s = _state.value
        val obj = JsonObject()
        if (s.firstName.isNotBlank()) obj.addProperty("firstName", s.firstName)
        if (s.lastName.isNotBlank()) obj.addProperty("lastName", s.lastName)
        val primaryPhone = s.phones.firstOrNull()?.number ?: ""
        if (primaryPhone.isNotBlank()) obj.addProperty("phone", primaryPhone)
        val primaryEmail = s.emails.firstOrNull()?.email ?: ""
        if (primaryEmail.isNotBlank()) obj.addProperty("email", primaryEmail)
        if (s.organization.isNotBlank()) obj.addProperty("organization", s.organization)
        if (s.address.isNotBlank()) obj.addProperty("address", s.address)
        if (s.city.isNotBlank()) obj.addProperty("city", s.city)
        if (s.state.isNotBlank()) obj.addProperty("state", s.state)
        if (s.notes.isNotBlank()) obj.addProperty("notes", s.notes)
        return gson.toJson(obj)
    }

    fun resumeDraft(draft: DraftStore.Draft) {
        _pendingDraft.value = null
        val obj = try {
            JsonParser.parseString(draft.payloadJson).asJsonObject
        } catch (_: Exception) {
            return
        }
        val firstName    = obj.get("firstName")?.takeIf { !it.isJsonNull }?.asString ?: ""
        val lastName     = obj.get("lastName")?.takeIf  { !it.isJsonNull }?.asString ?: ""
        val phone        = obj.get("phone")?.takeIf     { !it.isJsonNull }?.asString ?: ""
        val email        = obj.get("email")?.takeIf     { !it.isJsonNull }?.asString ?: ""
        val organization = obj.get("organization")?.takeIf { !it.isJsonNull }?.asString ?: ""
        val address      = obj.get("address")?.takeIf   { !it.isJsonNull }?.asString ?: ""
        val city         = obj.get("city")?.takeIf      { !it.isJsonNull }?.asString ?: ""
        val stateField   = obj.get("state")?.takeIf     { !it.isJsonNull }?.asString ?: ""
        val notes        = obj.get("notes")?.takeIf     { !it.isJsonNull }?.asString ?: ""
        _state.value = _state.value.copy(
            firstName    = firstName,
            lastName     = lastName,
            phones       = if (phone.isNotBlank()) listOf(PhoneEntry(number = phone)) else listOf(PhoneEntry()),
            emails       = if (email.isNotBlank()) listOf(EmailEntry(email = email)) else listOf(EmailEntry()),
            organization = organization,
            address      = address,
            city         = city,
            state        = stateField,
            notes        = notes,
        )
        savedStateHandle[KEY_FIRST_NAME] = firstName
        savedStateHandle[KEY_LAST_NAME]  = lastName
        savedStateHandle[KEY_PHONE]      = phone
        savedStateHandle[KEY_EMAIL]      = email
        savedStateHandle[KEY_ORG]        = organization
        savedStateHandle[KEY_ADDRESS]    = address
        savedStateHandle[KEY_CITY]       = city
        savedStateHandle[KEY_STATE]      = stateField
        savedStateHandle[KEY_NOTES]      = notes
    }

    fun discardDraft() {
        _pendingDraft.value = null
        viewModelScope.launch { draftStore.discard(DraftStore.DraftType.CUSTOMER) }
    }

    // ── Duplicate detection ──────────────────────────────────────────

    /** Search by primary phone + primary email; if any hits, surface the dialog. */
    private suspend fun checkForDuplicates(): List<CustomerListItem> {
        val primaryPhone = _state.value.phones.firstOrNull { it.number.isNotBlank() }?.number ?: ""
        val primaryEmail = _state.value.emails.firstOrNull { it.email.isNotBlank() }?.email ?: ""
        val candidates = mutableListOf<CustomerListItem>()
        try {
            if (primaryPhone.isNotBlank()) {
                val digits = primaryPhone.filter { it.isDigit() }
                val resp = customerApi.searchCustomers(digits)
                resp.data?.let { candidates.addAll(it) }
            }
            if (primaryEmail.isNotBlank()) {
                val resp = customerApi.searchCustomers(primaryEmail)
                resp.data?.let { hits ->
                    for (h in hits) {
                        if (candidates.none { it.id == h.id }) candidates.add(h)
                    }
                }
            }
        } catch (_: Exception) {
            // Network failure → skip duplicate check, proceed with create
        }
        return candidates
    }

    fun dismissDuplicateDialog() {
        _state.value = _state.value.copy(showDuplicateDialog = false, duplicateCandidates = emptyList())
    }

    fun useExistingCustomer(id: Long) {
        _state.value = _state.value.copy(
            showDuplicateDialog = false,
            duplicateCandidates = emptyList(),
            createdId = id,
        )
    }

    // ── Save ──────────────────────────────────────────────────────────

    /** Called by "Create anyway" button in the duplicate dialog. */
    fun saveForce() {
        _state.value = _state.value.copy(showDuplicateDialog = false, duplicateCandidates = emptyList())
        doSave()
    }

    fun save() {
        val current = _state.value

        val trimmedFirstName = current.firstName.trim()
        if (trimmedFirstName.isEmpty()) {
            _state.value = current.copy(error = "First name is required")
            return
        }
        if (trimmedFirstName.length > 255) {
            _state.value = current.copy(error = "First name is too long (max 255 characters)")
            return
        }

        val primaryEmail = current.emails.firstOrNull()?.email?.trim() ?: ""
        if (primaryEmail.isNotEmpty()) {
            if (primaryEmail.length > 254) {
                _state.value = current.copy(error = "Email is too long")
                return
            }
            val emailRegex = Regex("^[^\\s@.]+(?:\\.[^\\s@.]+)*@[^\\s@.]+(?:\\.[^\\s@.]+)*\\.[^\\s@.]{2,}$")
            if (!emailRegex.matches(primaryEmail.lowercase())) {
                _state.value = current.copy(error = "Enter a valid email address")
                return
            }
        }

        val primaryPhone = current.phones.firstOrNull()?.number?.trim() ?: ""
        if (primaryPhone.isNotEmpty()) {
            val digits = primaryPhone.filter { it.isDigit() }
            if (digits.length !in 10..15) {
                _state.value = current.copy(error = "Phone number must be 10-15 digits")
                return
            }
        }

        // Duplicate check before POST
        viewModelScope.launch {
            _state.value = _state.value.copy(isSubmitting = true, error = null)
            val dupes = checkForDuplicates()
            if (dupes.isNotEmpty()) {
                _state.value = _state.value.copy(
                    isSubmitting = false,
                    duplicateCandidates = dupes,
                    showDuplicateDialog = true,
                )
                return@launch
            }
            doSave()
        }
    }

    private fun doSave() {
        val current = _state.value
        viewModelScope.launch {
            _state.value = _state.value.copy(isSubmitting = true, error = null)
            try {
                val primaryPhone = current.phones.firstOrNull { it.number.isNotBlank() }
                val primaryEmail = current.emails.firstOrNull { it.email.isNotBlank() }

                // Build multi-phone list (exclude empty entries)
                val allPhones = current.phones
                    .filter { it.number.isNotBlank() }
                    .map { CustomerPhone(id = null, phone = it.number.trim(), label = it.label) }

                // Build multi-email list
                val allEmails = current.emails
                    .filter { it.email.isNotBlank() }
                    .map { CustomerEmail(id = null, email = it.email.trim(), label = it.label) }

                val tagsStr = current.tags.joinToString(", ").ifBlank { null }

                val request = CreateCustomerRequest(
                    firstName    = current.firstName.trim(),
                    lastName     = current.lastName.trim().ifBlank { null },
                    phone        = primaryPhone?.number?.trim()?.ifBlank { null },
                    email        = primaryEmail?.email?.trim()?.ifBlank { null },
                    organization = current.organization.trim().ifBlank { null },
                    address1     = current.address.trim().ifBlank { null },
                    city         = current.city.trim().ifBlank { null },
                    state        = current.state.trim().ifBlank { null },
                    postcode     = current.zip.trim().ifBlank { null },
                    address2     = if (!current.sameAsMailing) current.billingAddress.trim().ifBlank { null } else null,
                    type         = current.type,
                    phones       = allPhones.ifEmpty { null },
                    emails       = allEmails.ifEmpty { null },
                    customerTags = tagsStr,
                    smsOptIn     = if (current.smsOptIn) 1 else 0,
                    emailOptIn   = if (current.emailOptIn) 1 else 0,
                    referredBy   = current.referralSource.ifBlank { null },
                    comments     = current.notes.trim().ifBlank { null },
                    // AP5: UUID idempotency key so retries don't create duplicates
                    clientRequestId = UUID.randomUUID().toString(),
                )
                val createdId = customerRepository.createCustomer(request)
                discardDraft()
                _state.value = _state.value.copy(isSubmitting = false, createdId = createdId)
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isSubmitting = false,
                    error = e.message ?: "Failed to create customer",
                )
            }
        }
    }

    companion object {
        val REFERRAL_OPTIONS = listOf("", "Web", "Phone", "Referral", "Walk-in", "Other")
        val PHONE_LABELS     = listOf("Mobile", "Home", "Work", "Other")
        val EMAIL_LABELS     = listOf("Home", "Work", "Other")
    }
}

// ── Phone formatting helper ───────────────────────────────────────────────────

/**
 * Format a phone-number input as the user types (CROSS7).
 * Strips known country-code prefix we injected, keeps max 10 local digits,
 * emits `+1 (NNN)-NNN-NNNN` progressively.
 */
private fun formatPhoneInput(raw: String): String {
    if (raw.isBlank()) return ""
    val withoutPrefix = raw
        .removePrefix("+1 (")
        .let { if (it === raw) raw.removePrefix("+1 ") else it }
        .let { if (it === raw) raw.removePrefix("+1") else it }
    var digits = withoutPrefix.filter { it.isDigit() }
    if (digits.length == 11 && digits.startsWith("1")) digits = digits.drop(1)
    if (digits.length > 10) digits = digits.take(10)
    return when {
        digits.isEmpty()     -> ""
        digits.length <= 3   -> "+1 ($digits"
        digits.length <= 6   -> "+1 (${digits.substring(0, 3)})-${digits.substring(3)}"
        else                 -> "+1 (${digits.substring(0, 3)})-${digits.substring(3, 6)}-${digits.substring(6)}"
    }
}

// ── Draft preview helper ──────────────────────────────────────────────────────

private fun buildCustomerDraftPreview(json: String): String {
    return try {
        val obj = JsonParser.parseString(json).asJsonObject
        val parts = mutableListOf<String>()
        val first = obj.get("firstName")?.takeIf { !it.isJsonNull }?.asString
        val last  = obj.get("lastName")?.takeIf  { !it.isJsonNull }?.asString
        val name  = listOfNotNull(first, last).joinToString(" ").trim()
        if (name.isNotBlank()) parts.add(name)
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

// ── Screen ────────────────────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun CustomerCreateScreen(
    onBack: () -> Unit,
    onCreated: (Long) -> Unit,
    onNavigateToCustomer: (Long) -> Unit = onCreated,
    viewModel: CustomerCreateViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val pendingDraft by viewModel.pendingDraft.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val focusManager = LocalFocusManager.current
    val onNext = KeyboardActions(onNext = { focusManager.moveFocus(FocusDirection.Down) })
    val onDoneSave = KeyboardActions(onDone = { focusManager.clearFocus(); viewModel.save() })

    // Navigate on successful creation
    LaunchedEffect(state.createdId) {
        val id = state.createdId ?: return@LaunchedEffect
        onCreated(id)
    }

    // Show error via snackbar
    LaunchedEffect(state.error) {
        val error = state.error ?: return@LaunchedEffect
        snackbarHostState.showSnackbar(error)
        viewModel.clearError()
    }

    // Draft recovery prompt
    val isFormEmpty = state.firstName.isBlank() && state.lastName.isBlank() &&
        state.phones.all { it.number.isBlank() } &&
        state.emails.all { it.email.isBlank() } &&
        state.organization.isBlank() && state.address.isBlank() &&
        state.city.isBlank() && state.state.isBlank() && state.notes.isBlank()
    if (pendingDraft != null && isFormEmpty) {
        DraftRecoveryPrompt(
            draft = pendingDraft!!,
            previewFormatter = ::buildCustomerDraftPreview,
            onResume = { viewModel.resumeDraft(pendingDraft!!) },
            onDiscard = { viewModel.discardDraft() },
        )
    }

    // ── Duplicate detection dialog ────────────────────────────────────
    if (state.showDuplicateDialog && state.duplicateCandidates.isNotEmpty()) {
        val top = state.duplicateCandidates.first()
        val topName = listOfNotNull(top.firstName, top.lastName).joinToString(" ").ifBlank { "this customer" }
        AlertDialog(
            onDismissRequest = viewModel::dismissDuplicateDialog,
            title = { Text("Possible duplicate") },
            text = {
                Text(
                    "Looks like this might be $topName. " +
                    "Use the existing record, cancel to go back, or create a new one anyway."
                )
            },
            confirmButton = {
                TextButton(onClick = { viewModel.useExistingCustomer(top.id) }) {
                    Text("Use existing")
                }
            },
            dismissButton = {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    TextButton(onClick = viewModel::dismissDuplicateDialog) { Text("Cancel") }
                    TextButton(onClick = viewModel::saveForce) { Text("Create anyway") }
                }
            },
        )
    }

    // ── Birthday date picker ──────────────────────────────────────────
    var showBirthdayPicker by remember { mutableStateOf(false) }
    if (showBirthdayPicker) {
        val today = java.util.Calendar.getInstance()
        val datePickerState = rememberDatePickerState(
            initialSelectedDateMillis = null,
        )
        DatePickerDialog(
            onDismissRequest = { showBirthdayPicker = false },
            confirmButton = {
                TextButton(onClick = {
                    showBirthdayPicker = false
                    val millis = datePickerState.selectedDateMillis
                    if (millis != null) {
                        val cal = java.util.Calendar.getInstance().also { it.timeInMillis = millis }
                        val mm = String.format("%02d", cal.get(java.util.Calendar.MONTH) + 1)
                        val dd = String.format("%02d", cal.get(java.util.Calendar.DAY_OF_MONTH))
                        val yyyy = cal.get(java.util.Calendar.YEAR)
                        viewModel.updateBirthday("$mm/$dd/$yyyy")
                    }
                }) { Text("OK") }
            },
            dismissButton = {
                TextButton(onClick = { showBirthdayPicker = false }) { Text("Cancel") }
            },
        ) {
            DatePicker(state = datePickerState)
        }
    }

    // ── Referral dropdown ─────────────────────────────────────────────
    var referralExpanded by remember { mutableStateOf(false) }

    // ── Contact import ────────────────────────────────────────────────
    val importContact = com.bizarreelectronics.crm.ui.screens.customers.components.rememberCustomerContactImport { contact ->
        viewModel.prefillFromContact(contact.displayName, contact.phone, contact.email)
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
                        CircularProgressIndicator(modifier = Modifier.size(24.dp), strokeWidth = 2.dp)
                        Spacer(modifier = Modifier.width(16.dp))
                    } else {
                        TextButton(
                            onClick = { viewModel.save() },
                            enabled = state.firstName.isNotBlank(),
                            colors = ButtonDefaults.textButtonColors(
                                contentColor = MaterialTheme.colorScheme.primary,
                                disabledContentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                            ),
                        ) { Text("Save") }
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

            // ── Import from Contacts button ───────────────────────────
            OutlinedButton(
                onClick = { importContact() },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(Icons.Default.ContactPage, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(modifier = Modifier.width(8.dp))
                Text("Import from Contacts")
            }

            HorizontalDivider()

            // ── Type radio ────────────────────────────────────────────
            Text("Customer type", style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
                listOf("individual" to "Person", "business" to "Business").forEach { (value, label) ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        RadioButton(
                            selected = state.type == value,
                            onClick = { viewModel.updateType(value) },
                        )
                        Text(label, style = MaterialTheme.typography.bodyMedium)
                    }
                }
            }

            // ── Name ──────────────────────────────────────────────────
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
                value = state.organization,
                onValueChange = viewModel::updateOrganization,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Organization") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                keyboardActions = onNext,
            )

            HorizontalDivider()

            // ── Multi-phone ───────────────────────────────────────────
            Text("Phone numbers", style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            state.phones.forEachIndexed { index, entry ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    // Label dropdown
                    var labelExpanded by remember { mutableStateOf(false) }
                    ExposedDropdownMenuBox(
                        expanded = labelExpanded,
                        onExpandedChange = { labelExpanded = it },
                        modifier = Modifier.width(110.dp),
                    ) {
                        OutlinedTextField(
                            value = entry.label,
                            onValueChange = {},
                            readOnly = true,
                            label = { Text("Label") },
                            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = labelExpanded) },
                            modifier = Modifier.menuAnchor(),
                            singleLine = true,
                        )
                        ExposedDropdownMenu(expanded = labelExpanded, onDismissRequest = { labelExpanded = false }) {
                            CustomerCreateViewModel.PHONE_LABELS.forEach { lbl ->
                                DropdownMenuItem(
                                    text = { Text(lbl) },
                                    onClick = { viewModel.updatePhoneLabel(index, lbl); labelExpanded = false },
                                )
                            }
                        }
                    }

                    OutlinedTextField(
                        value = entry.number,
                        onValueChange = { viewModel.updatePhoneNumber(index, it) },
                        modifier = Modifier.weight(1f),
                        label = { Text("Number") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone, imeAction = ImeAction.Next),
                        keyboardActions = onNext,
                    )

                    if (state.phones.size > 1) {
                        IconButton(onClick = { viewModel.removePhone(index) }) {
                            Icon(Icons.Default.Delete, contentDescription = "Remove phone",
                                tint = MaterialTheme.colorScheme.error, modifier = Modifier.size(20.dp))
                        }
                    }
                }
            }
            if (state.phones.size < 5) {
                TextButton(onClick = viewModel::addPhone) {
                    Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("Add phone")
                }
            }

            HorizontalDivider()

            // ── Multi-email ───────────────────────────────────────────
            Text("Email addresses", style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            state.emails.forEachIndexed { index, entry ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    var labelExpanded by remember { mutableStateOf(false) }
                    ExposedDropdownMenuBox(
                        expanded = labelExpanded,
                        onExpandedChange = { labelExpanded = it },
                        modifier = Modifier.width(90.dp),
                    ) {
                        OutlinedTextField(
                            value = entry.label,
                            onValueChange = {},
                            readOnly = true,
                            label = { Text("Label") },
                            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = labelExpanded) },
                            modifier = Modifier.menuAnchor(),
                            singleLine = true,
                        )
                        ExposedDropdownMenu(expanded = labelExpanded, onDismissRequest = { labelExpanded = false }) {
                            CustomerCreateViewModel.EMAIL_LABELS.forEach { lbl ->
                                DropdownMenuItem(
                                    text = { Text(lbl) },
                                    onClick = { viewModel.updateEmailLabel(index, lbl); labelExpanded = false },
                                )
                            }
                        }
                    }

                    OutlinedTextField(
                        value = entry.email,
                        onValueChange = { viewModel.updateEmailAddress(index, it) },
                        modifier = Modifier.weight(1f),
                        label = { Text("Address") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email, imeAction = ImeAction.Next),
                        keyboardActions = onNext,
                    )

                    if (state.emails.size > 1) {
                        IconButton(onClick = { viewModel.removeEmail(index) }) {
                            Icon(Icons.Default.Delete, contentDescription = "Remove email",
                                tint = MaterialTheme.colorScheme.error, modifier = Modifier.size(20.dp))
                        }
                    }
                }
            }
            if (state.emails.size < 5) {
                TextButton(onClick = viewModel::addEmail) {
                    Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("Add email")
                }
            }

            HorizontalDivider()

            // ── Mailing address ───────────────────────────────────────
            Text("Mailing address", style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            OutlinedTextField(
                value = state.address,
                onValueChange = viewModel::updateAddress,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Street address") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                keyboardActions = onNext,
            )
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
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
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                    keyboardActions = onNext,
                )
                OutlinedTextField(
                    value = state.zip,
                    onValueChange = viewModel::updateZip,
                    modifier = Modifier.weight(1f),
                    label = { Text("ZIP") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Next),
                    keyboardActions = onNext,
                )
            }

            // ── Billing address toggle ────────────────────────────────
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Same as mailing address", style = MaterialTheme.typography.bodyMedium)
                Switch(checked = state.sameAsMailing, onCheckedChange = viewModel::updateSameAsMailing)
            }

            if (!state.sameAsMailing) {
                Text("Billing address", style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                OutlinedTextField(
                    value = state.billingAddress,
                    onValueChange = viewModel::updateBillingAddress,
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Street address") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                    keyboardActions = onNext,
                )
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    OutlinedTextField(
                        value = state.billingCity,
                        onValueChange = viewModel::updateBillingCity,
                        modifier = Modifier.weight(1f),
                        label = { Text("City") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                        keyboardActions = onNext,
                    )
                    OutlinedTextField(
                        value = state.billingState,
                        onValueChange = viewModel::updateBillingState,
                        modifier = Modifier.weight(1f),
                        label = { Text("State") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                        keyboardActions = onNext,
                    )
                    OutlinedTextField(
                        value = state.billingZip,
                        onValueChange = viewModel::updateBillingZip,
                        modifier = Modifier.weight(1f),
                        label = { Text("ZIP") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Next),
                        keyboardActions = onNext,
                    )
                }
            }

            HorizontalDivider()

            // ── Tags chip input ───────────────────────────────────────
            // 5.8.4: max 20 tags; warn at 10
            val tagCount = state.tags.size
            val tagLimitReached = tagCount >= 20
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Tags", style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (tagCount >= 10) {
                    Text(
                        "$tagCount/20 tags",
                        style = MaterialTheme.typography.labelSmall,
                        color = if (tagLimitReached) MaterialTheme.colorScheme.error
                                 else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            if (state.tags.isNotEmpty()) {
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    state.tags.forEach { tag ->
                        TagChip(
                            label = tag,
                            onRemove = { viewModel.removeTag(tag) },
                            tagPalette = state.tagPalette,
                        )
                    }
                }
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                OutlinedTextField(
                    value = state.tagInput,
                    onValueChange = viewModel::updateTagInput,
                    modifier = Modifier.weight(1f),
                    label = { Text("Add tag") },
                    singleLine = true,
                    enabled = !tagLimitReached,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { if (!tagLimitReached) viewModel.addTag() }),
                )
                FilledTonalIconButton(
                    onClick = viewModel::addTag,
                    enabled = state.tagInput.isNotBlank() && !tagLimitReached,
                ) {
                    Icon(Icons.Default.Add, contentDescription = "Add tag")
                }
            }

            HorizontalDivider()

            // ── Communication preferences ─────────────────────────────
            Text("Communication preferences", style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                listOf(
                    Triple("SMS marketing", state.smsOptIn, viewModel::updateSmsOptIn),
                    Triple("Email marketing", state.emailOptIn, viewModel::updateEmailOptIn),
                    Triple("Phone calls", state.phoneCallsOptIn, viewModel::updatePhoneCallsOptIn),
                ).forEach { (label, checked, onToggle) ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(label, style = MaterialTheme.typography.bodyMedium)
                        Switch(checked = checked, onCheckedChange = onToggle)
                    }
                }
            }

            HorizontalDivider()

            // ── Referral source dropdown ──────────────────────────────
            ExposedDropdownMenuBox(
                expanded = referralExpanded,
                onExpandedChange = { referralExpanded = it },
            ) {
                OutlinedTextField(
                    value = state.referralSource.ifBlank { "Select…" },
                    onValueChange = {},
                    readOnly = true,
                    label = { Text("Referral source") },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = referralExpanded) },
                    modifier = Modifier.fillMaxWidth().menuAnchor(),
                    singleLine = true,
                )
                ExposedDropdownMenu(expanded = referralExpanded, onDismissRequest = { referralExpanded = false }) {
                    CustomerCreateViewModel.REFERRAL_OPTIONS.forEach { option ->
                        DropdownMenuItem(
                            text = { Text(option.ifBlank { "None" }) },
                            onClick = { viewModel.updateReferralSource(option); referralExpanded = false },
                        )
                    }
                }
            }

            // ── Birthday ──────────────────────────────────────────────
            OutlinedTextField(
                value = state.birthday,
                onValueChange = {},
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Birthday") },
                placeholder = { Text("MM/DD/YYYY") },
                singleLine = true,
                readOnly = true,
                trailingIcon = {
                    TextButton(onClick = { showBirthdayPicker = true }) { Text("Pick") }
                },
            )

            // ── Notes ─────────────────────────────────────────────────
            OutlinedTextField(
                value = state.notes,
                onValueChange = viewModel::updateNotes,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Notes") },
                minLines = 3,
                maxLines = 6,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                keyboardActions = onDoneSave,
            )

            // TODO: custom fields — render dynamic fields from GET /custom-fields
            // when that endpoint is implemented. Tracked as CUSTOM-FIELDS-001.

            Spacer(Modifier.height(8.dp))
        }
    }
}
