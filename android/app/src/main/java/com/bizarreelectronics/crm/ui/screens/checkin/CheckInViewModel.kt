package com.bizarreelectronics.crm.ui.screens.checkin

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.db.BizarreDatabase
import com.bizarreelectronics.crm.data.local.db.dao.CheckInDraftDao
import com.bizarreelectronics.crm.data.local.db.entities.CheckInDraftEntity
import com.bizarreelectronics.crm.data.remote.api.InventoryApi
import com.bizarreelectronics.crm.data.remote.api.RepairPricingApi
import com.bizarreelectronics.crm.data.remote.api.TicketApi
import com.bizarreelectronics.crm.data.remote.dto.CreateTicketDeviceRequest
import com.bizarreelectronics.crm.data.remote.dto.CreateTicketRequest
import com.google.gson.Gson
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class CheckInViewModel @Inject constructor(
    private val ticketApi: TicketApi,
    private val inventoryApi: InventoryApi,
    private val repairPricingApi: RepairPricingApi,
    private val checkInDraftDao: CheckInDraftDao,
    private val gson: Gson,
) : ViewModel() {

    private val _uiState = MutableStateFlow(CheckInUiState())
    val uiState: StateFlow<CheckInUiState> = _uiState.asStateFlow()

    private var autosaveJob: Job? = null
    private var customerId: Long = 0L
    private var deviceId: Long = 0L

    fun init(customerId: Long, deviceId: Long) {
        this.customerId = customerId
        this.deviceId = deviceId
        viewModelScope.launch { loadDraftIfPresent() }
    }

    // ── Step navigation ────────────────────────────────────────────────────────

    fun advance() {
        val current = _uiState.value.currentStep
        if (current < TOTAL_STEPS - 1) {
            val next = current + 1
            _uiState.update { it.copy(currentStep = next) }
            // Quote step (index 4) — auto-fill subtotal from RepairPricingApi
            // catalog. Server services seeded at first-run setup wizard
            // (todofixes426 commit 07ec4c4b). Honors user override: skips if
            // subtotal already set or auto-fill already ran.
            if (next == 4) maybeAutoFillQuoteSubtotal()
        }
    }

    fun goBack() {
        val current = _uiState.value.currentStep
        if (current > 0) {
            _uiState.update { it.copy(currentStep = current - 1) }
        }
    }

    fun canAdvance(): Boolean {
        val s = _uiState.value
        return when (s.currentStep) {
            0 -> s.symptoms.isNotEmpty()
            5 -> s.signatureBase64 != null && s.agreedToTerms && s.consentBackup &&
                    (s.depositCents == 0L || s.authorizedDeposit)
            else -> true
        }
    }

    // ── Step 1: Symptoms ───────────────────────────────────────────────────────

    fun toggleSymptom(symptom: String) {
        val current = _uiState.value.symptoms
        val updated = if (symptom in current) current - symptom else current + symptom
        _uiState.update { it.copy(symptoms = updated) }
        scheduleSave()
    }

    // ── Step 2: Details ────────────────────────────────────────────────────────

    fun setCustomerNotes(text: String) {
        _uiState.update { it.copy(customerNotes = text) }
        scheduleSave()
    }

    fun setInternalNotes(text: String) {
        _uiState.update { it.copy(internalNotes = text) }
        scheduleSave()
    }

    fun setPasscodeFormat(format: PasscodeFormat) {
        _uiState.update { it.copy(passcodeFormat = format, passcode = "") }
        scheduleSave()
    }

    fun setPasscode(value: String) {
        _uiState.update { it.copy(passcode = value) }
        scheduleSave()
    }

    fun addPhoto(uri: String) {
        val updated = (_uiState.value.photoUris + uri).take(MAX_PHOTOS)
        _uiState.update { it.copy(photoUris = updated) }
        scheduleSave()
    }

    fun removePhoto(uri: String) {
        _uiState.update { it.copy(photoUris = it.photoUris - uri) }
        scheduleSave()
    }

    // ── Step 3: Damage ─────────────────────────────────────────────────────────

    fun addDamageMarker(marker: DamageMarker) {
        _uiState.update { it.copy(damageMarkers = it.damageMarkers + marker) }
        scheduleSave()
    }

    fun removeDamageMarker(marker: DamageMarker) {
        _uiState.update { it.copy(damageMarkers = it.damageMarkers - marker) }
        scheduleSave()
    }

    fun setDamageTab(tab: DeviceSide) {
        _uiState.update { it.copy(activeDamageSide = tab) }
    }

    fun setCondition(condition: DeviceCondition) {
        _uiState.update { it.copy(overallCondition = condition) }
        scheduleSave()
    }

    fun toggleAccessory(item: String) {
        val current = _uiState.value.includes
        val updated = if (item in current) current - item else current + item
        _uiState.update { it.copy(includes = updated) }
        scheduleSave()
    }

    fun setLdiStatus(status: LdiStatus) {
        _uiState.update { it.copy(ldiStatus = status) }
        scheduleSave()
    }

    // ── Step 4: Diagnostic ─────────────────────────────────────────────────────

    fun setDiagnosticResult(test: String, result: TriState) {
        val updated = _uiState.value.diagnostics.toMutableMap().also { it[test] = result }
        _uiState.update { it.copy(diagnostics = updated) }
        scheduleSave()
    }

    fun setAllOk() {
        val allOk = DIAGNOSTIC_TESTS.associateWith { TriState.PASS }
        _uiState.update { it.copy(diagnostics = allOk) }
        scheduleSave()
    }

    fun setBatteryHealth(percent: Int?, cycles: Int?) {
        _uiState.update { it.copy(batteryHealthPercent = percent, batteryCycles = cycles) }
    }

    // ── Step 5: Quote ──────────────────────────────────────────────────────────

    fun setDepositCents(cents: Long) {
        _uiState.update { it.copy(depositCents = cents) }
        scheduleSave()
    }

    fun setDepositFullBalance(fullBalance: Boolean) {
        val s = _uiState.value
        val cents = if (fullBalance) s.quoteTotalCents else s.depositCents
        _uiState.update { it.copy(depositFullBalance = fullBalance, depositCents = cents) }
        scheduleSave()
    }

    fun setLaborMinutes(minutes: Int) {
        _uiState.update { it.copy(laborMinutes = minutes) }
        scheduleSave()
    }

    fun setLaborTechId(techId: Long) {
        _uiState.update { it.copy(laborTechId = techId) }
        scheduleSave()
    }

    fun setQuoteSubtotalCents(cents: Long) {
        // Mark as user-touched so subsequent advance()→Quote re-entries don't
        // overwrite the manual value with the auto-fill.
        _uiState.update { it.copy(quoteSubtotalCents = cents, subtotalAutoFilled = true) }
        scheduleSave()
    }

    /**
     * Symptom-label → service-search-term map used to translate the cashier's
     * symptom selection into a fuzzy service catalog query. Server matches
     * `q` against `repair_services.name LIKE %q%` so simple keywords work.
     */
    private val symptomToServiceQuery = mapOf(
        "Cracked screen" to "screen",
        "Battery drain" to "battery",
        "Won't charge" to "charge",
        "Liquid damage" to "liquid",
        "No sound" to "speaker",
        "Camera" to "camera",
        "Buttons" to "button",
    )

    private fun maybeAutoFillQuoteSubtotal() {
        val s = _uiState.value
        if (s.quoteSubtotalCents > 0L || s.subtotalAutoFilled) return
        if (s.symptoms.isEmpty()) return
        viewModelScope.launch {
            var totalCents = 0L
            var matched = false
            try {
                for (symptom in s.symptoms) {
                    val query = symptomToServiceQuery[symptom] ?: continue
                    val response = repairPricingApi.getServices(query = query)
                    val first = response.data?.firstOrNull { it.isActive == 1 }
                    if (first != null && first.laborPrice > 0.0) {
                        totalCents += (first.laborPrice * 100).toLong()
                        matched = true
                    }
                }
            } catch (_: Exception) {
                // Network/server failure — leave subtotal blank so cashier
                // notices and enters manually. Don't surface an error: the
                // pricing catalog may simply be empty pre-setup-wizard.
                return@launch
            }
            if (matched) {
                _uiState.update {
                    it.copy(quoteSubtotalCents = totalCents, subtotalAutoFilled = true)
                }
                scheduleSave()
            }
        }
    }

    fun setTaxRateBps(bps: Int) {
        _uiState.update { it.copy(taxRateBps = bps) }
        scheduleSave()
    }

    // ── Step 6: Signature ──────────────────────────────────────────────────────

    fun setAgreedToTerms(agreed: Boolean) {
        _uiState.update { it.copy(agreedToTerms = agreed) }
    }

    fun setConsentBackup(consent: Boolean) {
        _uiState.update { it.copy(consentBackup = consent) }
    }

    fun setAuthorizedDeposit(auth: Boolean) {
        _uiState.update { it.copy(authorizedDeposit = auth) }
    }

    fun setOptInSms(optIn: Boolean) {
        _uiState.update { it.copy(optInSms = optIn) }
    }

    fun setSignature(base64: String) {
        _uiState.update { it.copy(signatureBase64 = base64) }
    }

    // ── Submit ─────────────────────────────────────────────────────────────────

    fun createTicket(onSuccess: (Long) -> Unit, onError: (String) -> Unit) {
        viewModelScope.launch {
            _uiState.update { it.copy(isSubmitting = true, submitError = null) }
            try {
                val s = _uiState.value
                val request = buildCreateTicketRequest(s)
                val response = ticketApi.createTicket(request)
                val ticket = response.data
                    ?: throw IllegalStateException("Server returned null ticket data")
                checkInDraftDao.delete(customerId, deviceId)
                _uiState.update { it.copy(isSubmitting = false) }
                onSuccess(ticket.id)
            } catch (e: Exception) {
                _uiState.update { it.copy(isSubmitting = false, submitError = e.message) }
                onError(e.message ?: "Failed to create ticket")
            }
        }
    }

    // ── Autosave ───────────────────────────────────────────────────────────────

    private fun scheduleSave() {
        autosaveJob?.cancel()
        autosaveJob = viewModelScope.launch {
            delay(AUTOSAVE_DEBOUNCE_MS)
            saveDraft()
        }
    }

    suspend fun saveDraft() {
        val s = _uiState.value
        val payload = gson.toJson(s)
        checkInDraftDao.upsert(
            CheckInDraftEntity(
                customerId = customerId,
                deviceId = deviceId,
                step = s.currentStep,
                payloadJson = payload,
                updatedAt = System.currentTimeMillis(),
            )
        )
    }

    private suspend fun loadDraftIfPresent() {
        val entity = checkInDraftDao.get(customerId, deviceId) ?: return
        val restored = try {
            gson.fromJson(entity.payloadJson, CheckInUiState::class.java)
        } catch (_: Exception) {
            return
        }
        _uiState.update { restored.copy(hasDraft = true) }
    }

    fun dismissDraftChip() {
        _uiState.update { it.copy(hasDraft = false) }
    }

    // ── Request builder ────────────────────────────────────────────────────────

    private fun buildCreateTicketRequest(s: CheckInUiState): CreateTicketRequest {
        val symptomsText = s.symptoms.joinToString(", ")
        val notesText = buildString {
            if (s.customerNotes.isNotBlank()) append(s.customerNotes)
            if (s.symptoms.isNotEmpty()) {
                if (isNotEmpty()) append("\n\n")
                append("Reported symptoms: $symptomsText")
            }
        }
        return CreateTicketRequest(
            customerId = customerId,
            devices = listOf(
                CreateTicketDeviceRequest(
                    customerComments = notesText.ifBlank { null },
                    staffComments = s.internalNotes.ifBlank { null },
                    preConditions = s.symptoms.toList(),
                )
            )
        )
    }

    companion object {
        const val TOTAL_STEPS = 6
        private const val AUTOSAVE_DEBOUNCE_MS = 500L
        private const val MAX_PHOTOS = 10

        val DIAGNOSTIC_TESTS = listOf(
            "Power on",
            "Touchscreen",
            "Face ID / Touch ID",
            "Speakers",
            "Cameras",
            "Wi-Fi + BT",
            "Cellular / SIM",
        )
    }
}

// ── State ──────────────────────────────────────────────────────────────────────

data class CheckInUiState(
    val currentStep: Int = 0,
    val hasDraft: Boolean = false,
    // Step 1
    val symptoms: Set<String> = emptySet(),
    // Step 2
    val customerNotes: String = "",
    val internalNotes: String = "",
    val passcodeFormat: PasscodeFormat = PasscodeFormat.NONE,
    val passcode: String = "",
    val photoUris: List<String> = emptyList(),
    // Step 3
    val damageMarkers: List<DamageMarker> = emptyList(),
    val activeDamageSide: DeviceSide = DeviceSide.FRONT,
    val overallCondition: DeviceCondition = DeviceCondition.GOOD,
    val includes: Set<String> = emptySet(),
    val ldiStatus: LdiStatus = LdiStatus.NOT_TESTED,
    // Step 4
    val diagnostics: Map<String, TriState> = emptyMap(),
    val batteryHealthPercent: Int? = null,
    val batteryCycles: Int? = null,
    // Step 5
    val quoteSubtotalCents: Long = 0L,
    /** True once the cashier has touched the subtotal field, OR the auto-fill
     *  from the pricing catalog has run. Prevents repeat advance()→Quote
     *  visits from clobbering a manually-entered value. */
    val subtotalAutoFilled: Boolean = false,
    val taxRateBps: Int = 800,
    val depositCents: Long = 0L,
    val depositFullBalance: Boolean = false,
    val laborMinutes: Int = 0,
    val laborTechId: Long = 0L,
    // Step 6
    val agreedToTerms: Boolean = false,
    val consentBackup: Boolean = false,
    val authorizedDeposit: Boolean = false,
    val optInSms: Boolean = false,
    val signatureBase64: String? = null,
    // Submission
    val isSubmitting: Boolean = false,
    val submitError: String? = null,
) {
    val taxCents: Long get() = quoteSubtotalCents * taxRateBps / 10_000
    val quoteTotalCents: Long get() = quoteSubtotalCents + taxCents
    val dueOnPickupCents: Long get() = (quoteTotalCents - depositCents).coerceAtLeast(0L)
    val progressFraction: Float get() = (currentStep + 1) / CheckInViewModel.TOTAL_STEPS.toFloat()
}

// ── Domain types ───────────────────────────────────────────────────────────────

enum class PasscodeFormat(val label: String) {
    NONE("None"),
    FOUR_DIGIT("4-digit PIN"),
    SIX_DIGIT("6-digit PIN"),
    ALPHANUMERIC("Alphanumeric"),
    PATTERN("Pattern"),
}

enum class DeviceSide(val label: String) {
    FRONT("Front"),
    BACK("Back"),
    SIDES("Sides"),
}

enum class DeviceCondition(val label: String) {
    MINT("Mint"),
    GOOD("Good"),
    FAIR("Fair"),
    POOR("Poor"),
    SALVAGE("Salvage"),
}

enum class LdiStatus(val label: String) {
    NOT_TESTED("Not tested"),
    CLEAN("Clean"),
    TRIPPED("Tripped"),
}

enum class TriState(val label: String) {
    PASS("✓"),
    FAIL("✕"),
    UNKNOWN("?"),
}

data class DamageMarker(
    val side: DeviceSide,
    val xFraction: Float,
    val yFraction: Float,
    val type: DamageType,
)

enum class DamageType(val symbol: String, val colorToken: String) {
    CRACK("✖", "error"),
    SCRATCH("/", "warning"),
    DENT("●", "warning"),
    STAIN("●", "teal"),
}
