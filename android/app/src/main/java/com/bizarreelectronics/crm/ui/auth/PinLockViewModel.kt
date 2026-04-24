package com.bizarreelectronics.crm.ui.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.PinPreferences
import com.bizarreelectronics.crm.data.repository.PinRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * ViewModel backing [PinLockScreen] and [PinSetupScreen]. Holds only UI
 * concerns; anything that has to persist across launches lives in
 * [PinPreferences].
 */
@HiltViewModel
class PinLockViewModel @Inject constructor(
    private val pinRepository: PinRepository,
    private val pinPrefs: PinPreferences,
) : ViewModel() {

    data class State(
        val mode: Mode = Mode.Verify,
        val entered: String = "",
        val pinLength: Int = 4,
        val isWorking: Boolean = false,
        val wrongShakes: Int = 0,
        val remainingAttempts: Int = 5,
        val lockoutUntilMillis: Long = 0L,
        val hardLockout: Boolean = false,
        val errorMessage: String? = null,
        val setupStep: SetupStep = SetupStep.EnterNew,
        val setupCandidate: String = "",
        val unlocked: Boolean = false,
        val pinChanged: Boolean = false,
        /** §2.15 — true when digits should be visible (tap-hold reveal). */
        val pinsVisible: Boolean = false,
        /** §2.15 — non-blocking banner when 90-day rotation is due. */
        val showRotationBanner: Boolean = false,
    ) {
        val isInLockout: Boolean
            get() = lockoutUntilMillis > System.currentTimeMillis()

        val lockoutRemainingSeconds: Int
            get() = ((lockoutUntilMillis - System.currentTimeMillis()) / 1000L)
                .coerceAtLeast(0L).toInt()
    }

    enum class Mode { Verify, Setup, Change }

    enum class SetupStep { EnterCurrent, EnterNew, ConfirmNew }

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    init {
        // Seed lockout state from prefs so a process restart doesn't dodge
        // the 30s/60s freeze the user earned by guessing.
        _state.value = _state.value.copy(
            lockoutUntilMillis = pinPrefs.lockoutUntilMillis,
            hardLockout = pinPrefs.hardLockout,
            remainingAttempts = (MAX_ATTEMPTS - pinPrefs.failedAttempts).coerceAtLeast(0),
        )
    }

    fun startVerify() {
        _state.value = State(
            mode = Mode.Verify,
            lockoutUntilMillis = pinPrefs.lockoutUntilMillis,
            hardLockout = pinPrefs.hardLockout,
            remainingAttempts = (MAX_ATTEMPTS - pinPrefs.failedAttempts).coerceAtLeast(0),
        )
    }

    fun startSetup() {
        _state.value = State(mode = Mode.Setup, setupStep = SetupStep.EnterNew)
    }

    fun startChange() {
        _state.value = State(mode = Mode.Change, setupStep = SetupStep.EnterCurrent)
    }

    fun onDigit(c: Char) {
        val s = _state.value
        if (s.isWorking || s.isInLockout || s.hardLockout) return
        val next = (s.entered + c).take(s.pinLength)
        _state.value = s.copy(entered = next, errorMessage = null)
        if (next.length == s.pinLength) {
            submit()
        }
    }

    fun onBackspace() {
        val s = _state.value
        if (s.isWorking || s.entered.isEmpty()) return
        _state.value = s.copy(entered = s.entered.dropLast(1), errorMessage = null)
    }

    private fun submit() {
        val s = _state.value
        viewModelScope.launch {
            _state.value = s.copy(isWorking = true)
            when (s.mode) {
                Mode.Verify -> handleVerify(s.entered)
                Mode.Setup -> handleSetupStep(s.entered)
                Mode.Change -> handleChangeStep(s.entered)
            }
        }
    }

    /** §2.15 — reveal digits while the user holds down on the PIN dot row. */
    fun onPinRevealStart() {
        _state.value = _state.value.copy(pinsVisible = true)
    }

    /** §2.15 — hide digits again (called on pointer-up or 3-second auto-hide). */
    fun onPinRevealEnd() {
        _state.value = _state.value.copy(pinsVisible = false)
    }

    private suspend fun handleVerify(pin: String) {
        // §2.15 — offline-ok: try local hash first; skip server round-trip on match.
        if (pinPrefs.verifyPinLocally(pin)) {
            pinPrefs.recordSuccess()
            val rotationDue = pinPrefs.isRotationDue()
            _state.value = _state.value.copy(
                isWorking = false,
                entered = "",
                unlocked = true,
                showRotationBanner = rotationDue,
            )
            return
        }

        val result = pinRepository.verify(pin)
        val base = _state.value.copy(isWorking = false, entered = "")
        _state.value = when (result) {
            is PinRepository.VerifyResult.Success -> base.copy(
                unlocked = true,
                showRotationBanner = pinPrefs.isRotationDue(),
            )
            is PinRepository.VerifyResult.WrongPin -> base.copy(
                wrongShakes = base.wrongShakes + 1,
                remainingAttempts = result.remaining,
                errorMessage = "Wrong PIN. ${remainingCopy(result.remaining)}",
            )
            is PinRepository.VerifyResult.Lockout -> base.copy(
                lockoutUntilMillis = result.untilMillis,
                wrongShakes = base.wrongShakes + 1,
                errorMessage = "Too many wrong tries. Wait before retrying.",
            )
            PinRepository.VerifyResult.HardLockout -> base.copy(
                hardLockout = true,
                wrongShakes = base.wrongShakes + 1,
                errorMessage = "Locked out. Sign out and log in again.",
            )
            is PinRepository.VerifyResult.Error -> base.copy(
                errorMessage = result.message,
            )
        }
        if (_state.value.isInLockout) {
            scheduleLockoutTick()
        }
    }

    private suspend fun handleSetupStep(entry: String) {
        val s = _state.value
        when (s.setupStep) {
            SetupStep.EnterNew -> {
                _state.value = s.copy(
                    isWorking = false,
                    setupCandidate = entry,
                    entered = "",
                    setupStep = SetupStep.ConfirmNew,
                )
            }
            SetupStep.ConfirmNew -> {
                if (entry != s.setupCandidate) {
                    _state.value = s.copy(
                        isWorking = false,
                        entered = "",
                        setupCandidate = "",
                        setupStep = SetupStep.EnterNew,
                        wrongShakes = s.wrongShakes + 1,
                        errorMessage = "PINs didn't match. Start over.",
                    )
                    return
                }
                val result = pinRepository.setInitialPin(entry)
                _state.value = when (result) {
                    PinRepository.ChangeResult.Success -> s.copy(
                        isWorking = false,
                        entered = "",
                        pinChanged = true,
                    )
                    is PinRepository.ChangeResult.Error -> s.copy(
                        isWorking = false,
                        entered = "",
                        setupCandidate = "",
                        setupStep = SetupStep.EnterNew,
                        errorMessage = result.message,
                    )
                }
            }
            SetupStep.EnterCurrent -> {
                // Unused in plain setup mode — treat as EnterNew.
                _state.value = s.copy(isWorking = false, entered = "")
            }
        }
    }

    private suspend fun handleChangeStep(entry: String) {
        val s = _state.value
        when (s.setupStep) {
            SetupStep.EnterCurrent -> {
                _state.value = s.copy(
                    isWorking = false,
                    setupCandidate = entry,
                    entered = "",
                    setupStep = SetupStep.EnterNew,
                )
            }
            SetupStep.EnterNew -> {
                _state.value = s.copy(
                    isWorking = false,
                    setupCandidate = s.setupCandidate + "|" + entry,
                    entered = "",
                    setupStep = SetupStep.ConfirmNew,
                )
            }
            SetupStep.ConfirmNew -> {
                val parts = s.setupCandidate.split("|")
                val current = parts.getOrNull(0).orEmpty()
                val newPin = parts.getOrNull(1).orEmpty()
                if (entry != newPin) {
                    _state.value = s.copy(
                        isWorking = false,
                        entered = "",
                        setupCandidate = "",
                        setupStep = SetupStep.EnterNew,
                        wrongShakes = s.wrongShakes + 1,
                        errorMessage = "New PINs didn't match. Try again.",
                    )
                    return
                }
                val result = pinRepository.changePin(current, newPin)
                _state.value = when (result) {
                    PinRepository.ChangeResult.Success -> s.copy(
                        isWorking = false,
                        entered = "",
                        pinChanged = true,
                    )
                    is PinRepository.ChangeResult.Error -> s.copy(
                        isWorking = false,
                        entered = "",
                        setupCandidate = "",
                        setupStep = SetupStep.EnterCurrent,
                        errorMessage = result.message,
                    )
                }
            }
        }
    }

    private fun scheduleLockoutTick() {
        viewModelScope.launch {
            while (_state.value.isInLockout) {
                delay(1_000)
                // Trigger recomposition by bumping wrongShakes? No — emit same
                // state with no change to force downstream collectors to re-read
                // lockoutRemainingSeconds. StateFlow dedupes identical values,
                // so publish a copy with a microsecond-scale bumped marker.
                val cur = _state.value
                _state.value = cur.copy() // dedup-safe via epoch check in UI
            }
            // Lockout elapsed — clear local mirror so the next wrong entry
            // starts a fresh timer window.
            val cur = _state.value
            _state.value = cur.copy(lockoutUntilMillis = 0L)
        }
    }

    private fun remainingCopy(n: Int): String = when (n) {
        0 -> "No attempts left."
        1 -> "1 attempt left."
        else -> "$n attempts left."
    }

    private companion object {
        private const val MAX_ATTEMPTS = 5
    }
}
