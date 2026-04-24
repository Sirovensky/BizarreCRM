package com.bizarreelectronics.crm.ui.auth

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.util.PinBlocklist
import com.bizarreelectronics.crm.util.isMediumOrExpandedWidth
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * §2.5 PIN lock — full-screen unlock gate.
 *
 * §2.15 additions:
 *  - Offline verify: [PinLockViewModel] checks local PBKDF2 hash before hitting server.
 *  - Rotation banner: non-blocking info card shown after unlock when 90 days have elapsed.
 *  - Show-tap-hold: holding down on [PinDots] reveals the entered digits for up to 3 seconds.
 *  - Forgot PIN? TextButton below keypad navigates to [onForgotPin] (§2.15 L387).
 *    Kept above the destructive "Sign out" action so the self-service path is
 *    preferred. Hard-lockout collapses to Sign-out-only (user must full-auth).
 *
 * Hosted by MainActivity when [com.bizarreelectronics.crm.data.local.prefs.PinPreferences.shouldLock]
 * returns true. The screen covers the nav graph so deep links and FCM taps
 * queue up behind it rather than rendering locked content.
 */
@Composable
fun PinLockScreen(
    onUnlocked: () -> Unit,
    onSignOut: () -> Unit,
    onForgotPin: (() -> Unit)? = null,
    viewModel: PinLockViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    LaunchedEffect(Unit) {
        viewModel.startVerify()
    }

    LaunchedEffect(state.unlocked) {
        if (state.unlocked) onUnlocked()
    }

    PinGateScaffold(
        title = "Enter your PIN",
        subtitle = when {
            state.hardLockout -> "Too many wrong tries. Sign out and log in again."
            state.isInLockout -> "Locked for ${state.lockoutRemainingSeconds}s."
            else -> "Unlock BizarreCRM to continue."
        },
        state = state,
        onDigit = viewModel::onDigit,
        onBackspace = viewModel::onBackspace,
        onRevealStart = viewModel::onPinRevealStart,
        onRevealEnd = viewModel::onPinRevealEnd,
        rotationBanner = state.showRotationBanner,
        footer = {
            if (state.hardLockout) {
                // Hard lockout: self-service reset won't help (too many wrong tries).
                // Only show destructive sign-out.
                OutlinedButton(onClick = onSignOut) {
                    Text("Sign out")
                }
            } else {
                // §2.15 L387 — "Forgot PIN?" first (self-service, non-destructive).
                // "Sign out" second (destructive — clears session).
                if (onForgotPin != null) {
                    TextButton(onClick = onForgotPin) {
                        Text("Forgot PIN?")
                    }
                }
                TextButton(onClick = onSignOut) {
                    Text("Sign out")
                }
            }
        },
    )
}

/**
 * §2.5 first-time setup — collects a new PIN twice before POSTing to
 * `/auth/change-pin`.
 *
 * §2.15: Blocklist check via [PinBlocklist.isBlocked] is surfaced here so the
 * user gets instant feedback before any network round-trip. The ViewModel /
 * PinRepository also check via PinBlocklist and the server enforces its own
 * entropy rules independently — this is an additional UX guardrail.
 */
@Composable
fun PinSetupScreen(
    onDone: () -> Unit,
    onCancel: (() -> Unit)? = null,
    viewModel: PinLockViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val blockedError = remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        viewModel.startSetup()
    }

    LaunchedEffect(state.pinChanged) {
        if (state.pinChanged) onDone()
    }

    // Blocklist-aware digit handler: intercepts when PIN is complete in EnterNew step.
    val onDigitWithBlocklistCheck: (Char) -> Unit = { c ->
        val nextEntered = (state.entered + c).take(state.pinLength)
        if (
            state.setupStep == PinLockViewModel.SetupStep.EnterNew &&
            nextEntered.length == state.pinLength &&
            PinBlocklist.isBlocked(nextEntered)
        ) {
            // Show inline error; do NOT forward to viewModel so no state is advanced.
            blockedError.value = "This PIN is too common. Choose a less guessable one."
            viewModel.onBackspace() // clear any partial state
        } else {
            blockedError.value = null
            viewModel.onDigit(c)
        }
    }

    PinGateScaffold(
        title = when (state.setupStep) {
            PinLockViewModel.SetupStep.EnterNew -> "Create a PIN"
            PinLockViewModel.SetupStep.ConfirmNew -> "Confirm your PIN"
            PinLockViewModel.SetupStep.EnterCurrent -> "Enter current PIN"
        },
        subtitle = when (state.setupStep) {
            PinLockViewModel.SetupStep.EnterNew ->
                "4–6 digits. You'll use this to unlock the app."
            PinLockViewModel.SetupStep.ConfirmNew ->
                "Type your PIN again to confirm."
            else -> ""
        },
        state = state,
        onDigit = onDigitWithBlocklistCheck,
        onBackspace = {
            blockedError.value = null
            viewModel.onBackspace()
        },
        onRevealStart = viewModel::onPinRevealStart,
        onRevealEnd = viewModel::onPinRevealEnd,
        rotationBanner = false,
        extraError = blockedError.value,
        footer = {
            if (onCancel != null) {
                TextButton(onClick = onCancel) { Text("Skip for now") }
            }
        },
    )
}

/**
 * Shared chrome used by both verify + setup screens. Keeps the layout + color
 * treatment identical so the transition feels like one flow.
 *
 * §2.15 additions:
 *  - [onRevealStart] / [onRevealEnd]: tap-hold callbacks wired to [PinDots].
 *  - [rotationBanner]: renders an advisory banner when 90-day rotation is due.
 *  - [extraError]: additional inline error (e.g. blocklist rejection) shown below
 *    the normal [PinLockViewModel.State.errorMessage].
 *
 * On medium/expanded widths (tablet/desktop, ≥600dp) the keypad content is
 * centred inside an [ElevatedCard] capped at 420dp so it doesn't stretch
 * full-screen. Phone/compact layout is unchanged.
 */
@Composable
private fun PinGateScaffold(
    title: String,
    subtitle: String,
    state: PinLockViewModel.State,
    onDigit: (Char) -> Unit,
    onBackspace: () -> Unit,
    onRevealStart: () -> Unit,
    onRevealEnd: () -> Unit,
    rotationBanner: Boolean,
    extraError: String? = null,
    footer: @Composable () -> Unit,
) {
    val isTablet = isMediumOrExpandedWidth()
    val haptic = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()

    /**
     * §2.15 — tap-hold reveal modifier for [PinDots].
     *
     * ACTION_DOWN → notify ViewModel → schedule 3-second auto-hide coroutine.
     * ACTION_UP / CANCEL → notify ViewModel immediately (cancel auto-hide via coroutine scope).
     * Haptic feedback fires on reveal to confirm the gesture.
     */
    val revealModifier = Modifier.pointerInput(Unit) {
        awaitPointerEventScope {
            while (true) {
                val down = awaitPointerEvent()
                if (down.changes.any { it.pressed }) {
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    onRevealStart()
                    val autoHideJob = scope.launch {
                        delay(3_000L)
                        onRevealEnd()
                    }
                    // Wait for pointer-up or cancel
                    awaitPointerEvent()
                    autoHideJob.cancel()
                    onRevealEnd()
                }
            }
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.surface),
        contentAlignment = Alignment.Center,
    ) {
        // §2.15 rotation banner — rendered above the lock card, non-blocking.
        if (rotationBanner) {
            RotationReminderBanner(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = 16.dp, start = 16.dp, end = 16.dp),
            )
        }

        // On tablet/desktop: wrap the keypad region in a centred ElevatedCard.
        // On phone: keep the original full-column layout with no card chrome.
        if (isTablet) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 24.dp, vertical = 48.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                ElevatedCard(
                    modifier = Modifier
                        .widthIn(max = 420.dp)
                        .align(Alignment.CenterHorizontally),
                ) {
                    Column(
                        modifier = Modifier
                            .padding(horizontal = 32.dp, vertical = 36.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(24.dp),
                    ) {
                        Text(
                            text = title,
                            style = MaterialTheme.typography.headlineMedium,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.onSurface,
                        )
                        if (subtitle.isNotBlank()) {
                            Text(
                                text = subtitle,
                                style = MaterialTheme.typography.bodyMedium,
                                textAlign = TextAlign.Center,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.widthIn(max = 360.dp),
                            )
                        }
                        PinDots(
                            entered = state.entered.length,
                            length = state.pinLength,
                            shakeTrigger = state.wrongShakes,
                            revealDigits = state.pinsVisible,
                            enteredDigits = state.entered,
                            modifier = revealModifier,
                        )
                        val displayError = extraError ?: state.errorMessage
                        if (displayError != null) {
                            Text(
                                text = displayError,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.error,
                                textAlign = TextAlign.Center,
                                modifier = Modifier.widthIn(max = 360.dp),
                            )
                        }
                        if (state.isWorking) {
                            CircularProgressIndicator(modifier = Modifier.widthIn(max = 32.dp))
                        } else {
                            PinKeypad(
                                enabled = !state.isInLockout && !state.hardLockout,
                                onDigit = onDigit,
                                onBackspace = onBackspace,
                                modifier = Modifier.widthIn(max = 320.dp),
                            )
                        }
                        Spacer(Modifier.height(8.dp))
                        footer()
                    }
                }
            }
        } else {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 24.dp, vertical = 48.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(24.dp, Alignment.CenterVertically),
            ) {
                Text(
                    text = title,
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                if (subtitle.isNotBlank()) {
                    Text(
                        text = subtitle,
                        style = MaterialTheme.typography.bodyMedium,
                        textAlign = TextAlign.Center,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.widthIn(max = 360.dp),
                    )
                }
                PinDots(
                    entered = state.entered.length,
                    length = state.pinLength,
                    shakeTrigger = state.wrongShakes,
                    revealDigits = state.pinsVisible,
                    enteredDigits = state.entered,
                    modifier = revealModifier,
                )
                val displayError = extraError ?: state.errorMessage
                if (displayError != null) {
                    Text(
                        text = displayError,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.widthIn(max = 360.dp),
                    )
                }
                if (state.isWorking) {
                    CircularProgressIndicator(modifier = Modifier.widthIn(max = 32.dp))
                } else {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .widthIn(max = 320.dp),
                    ) {
                        PinKeypad(
                            enabled = !state.isInLockout && !state.hardLockout,
                            onDigit = onDigit,
                            onBackspace = onBackspace,
                        )
                    }
                }
                Spacer(Modifier.height(8.dp))
                footer()
            }
        }
    }
}

/**
 * §2.15 — Non-blocking advisory banner shown after successful verify when the
 * 90-day PIN rotation deadline has passed.
 *
 * Directs the user to Settings → Security → Change PIN. Does NOT block unlock.
 */
@Composable
private fun RotationReminderBanner(modifier: Modifier = Modifier) {
    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.tertiaryContainer,
        ),
    ) {
        Text(
            text = "Change your PIN — it's been 90 days since the last update. " +
                "Settings \u2192 Security \u2192 Change PIN.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onTertiaryContainer,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp),
        )
    }
}
