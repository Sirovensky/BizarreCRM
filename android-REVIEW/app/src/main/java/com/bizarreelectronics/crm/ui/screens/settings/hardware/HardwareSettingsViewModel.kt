package com.bizarreelectronics.crm.ui.screens.settings.hardware

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.blockchyp.BlockChypClient
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import timber.log.Timber
import java.util.UUID
import javax.inject.Inject

// Minimum firmware version the operator must be running. Checked after
// getStatus(). Any string comparison below this prefix triggers the banner.
private const val MIN_FIRMWARE = "1.0.0"

data class HardwareSettingsUiState(
    val isPaired: Boolean = false,
    val pairedIp: String? = null,
    val isLoading: Boolean = false,
    val feedback: String? = null,
    val firmwareUpdateAvailable: Boolean = false,
    val firmwareVersion: String? = null,
    val lastTransactionId: String? = null,
)

@HiltViewModel
class HardwareSettingsViewModel @Inject constructor(
    private val blockChypClient: BlockChypClient,
) : ViewModel() {

    private val _uiState = MutableStateFlow(
        HardwareSettingsUiState(isPaired = blockChypClient.isPaired()),
    )
    val uiState: StateFlow<HardwareSettingsUiState> = _uiState.asStateFlow()

    // ── Pairing ───────────────────────────────────────────────────────────────

    fun savePairing(ip: String) {
        blockChypClient.savePairing(terminalIp = ip)
        _uiState.update { it.copy(isPaired = true, pairedIp = ip, feedback = "Terminal paired at $ip") }
    }

    fun clearPairing() {
        blockChypClient.clearPairing()
        _uiState.update { it.copy(isPaired = false, pairedIp = null, feedback = "Terminal unpaired") }
    }

    // ── Terminal actions ──────────────────────────────────────────────────────

    fun testConnection() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            val terminalName = blockChypClient.pairedTerminalName() ?: ""
            blockChypClient.testConnection(terminalName).fold(
                onSuccess = {
                    _uiState.update { it.copy(isLoading = false, feedback = "Terminal reachable") }
                },
                onFailure = { err ->
                    Timber.w(err, "testConnection failed")
                    _uiState.update {
                        it.copy(isLoading = false, feedback = "Connection failed: ${err.message}")
                    }
                },
            )
        }
    }

    /** Test charge — uses a $0.01 amount so it is safe to run in a test environment. */
    fun testCharge() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            val idempotencyKey = UUID.randomUUID().toString()
            // orderId "0" — the server will reject with 404 "Invoice not found".
            // This tests the card-dip path without completing a real charge.
            blockChypClient.charge(
                amountCents = 1L,
                orderId = "0",
                idempotencyKey = idempotencyKey,
            ).fold(
                onSuccess = { receipt ->
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            feedback = "Charged \$0.01 — txn ${receipt.transactionId}",
                            lastTransactionId = receipt.transactionId,
                        )
                    }
                },
                onFailure = { err ->
                    Timber.w(err, "testCharge failed")
                    _uiState.update {
                        it.copy(isLoading = false, feedback = "Charge error: ${err.message}")
                    }
                },
            )
        }
    }

    fun voidLast() {
        val txnId = _uiState.value.lastTransactionId ?: return
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            blockChypClient.voidTransaction(txnId).fold(
                onSuccess = {
                    _uiState.update {
                        it.copy(isLoading = false, feedback = "Voided $txnId", lastTransactionId = null)
                    }
                },
                onFailure = { err ->
                    Timber.w(err, "void failed")
                    _uiState.update {
                        it.copy(isLoading = false, feedback = "Void error: ${err.message}")
                    }
                },
            )
        }
    }

    fun captureSignature() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            blockChypClient.captureCheckInSignature(0L).fold(
                onSuccess = { sig ->
                    val preview = sig.base64DataUrl.take(40)
                    _uiState.update {
                        it.copy(isLoading = false, feedback = "Signature captured ($preview…)")
                    }
                },
                onFailure = { err ->
                    Timber.w(err, "captureSignature failed")
                    _uiState.update {
                        it.copy(isLoading = false, feedback = "Capture error: ${err.message}")
                    }
                },
            )
        }
    }

    fun adjustTip() {
        val txnId = _uiState.value.lastTransactionId ?: run {
            _uiState.update { it.copy(feedback = "No transaction to adjust — charge first") }
            return
        }
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            blockChypClient.adjustTip(txnId, newTipCents = 100L).fold(
                onSuccess = {
                    _uiState.update { it.copy(isLoading = false, feedback = "Tip adjusted +\$1.00") }
                },
                onFailure = { err ->
                    Timber.w(err, "adjustTip failed")
                    _uiState.update {
                        it.copy(isLoading = false, feedback = "Tip adjust: ${err.message}")
                    }
                },
            )
        }
    }

    /**
     * Fetch the current firmware version from the server and show the update
     * banner if the version is below [MIN_FIRMWARE].
     */
    fun checkFirmware() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            val status = blockChypClient.status()
            val version = status.firmwareVersion
            val needsUpdate = version != null && version < MIN_FIRMWARE
            _uiState.update {
                it.copy(
                    isLoading = false,
                    firmwareVersion = version,
                    firmwareUpdateAvailable = needsUpdate,
                    feedback = if (version != null) "Firmware: $version" else "Firmware version unavailable",
                )
            }
        }
    }

    fun dismissFirmwareBanner() {
        _uiState.update { it.copy(firmwareUpdateAvailable = false) }
    }

    fun clearFeedback() {
        _uiState.update { it.copy(feedback = null) }
    }
}
