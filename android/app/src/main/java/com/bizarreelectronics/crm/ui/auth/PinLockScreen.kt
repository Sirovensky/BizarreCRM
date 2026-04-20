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
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel

/**
 * §2.5 PIN lock — full-screen unlock gate.
 *
 * Hosted by MainActivity when [com.bizarreelectronics.crm.data.local.prefs.PinPreferences.shouldLock]
 * returns true. The screen covers the nav graph so deep links and FCM taps
 * queue up behind it rather than rendering locked content.
 */
@Composable
fun PinLockScreen(
    onUnlocked: () -> Unit,
    onSignOut: () -> Unit,
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
        footer = {
            if (state.hardLockout) {
                OutlinedButton(onClick = onSignOut) {
                    Text("Sign out")
                }
            } else {
                TextButton(onClick = onSignOut) {
                    Text("Forgot PIN? Sign out")
                }
            }
        },
    )
}

/**
 * §2.5 first-time setup — collects a new PIN twice before POSTing to
 * `/auth/change-pin`.
 */
@Composable
fun PinSetupScreen(
    onDone: () -> Unit,
    onCancel: (() -> Unit)? = null,
    viewModel: PinLockViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    LaunchedEffect(Unit) {
        viewModel.startSetup()
    }

    LaunchedEffect(state.pinChanged) {
        if (state.pinChanged) onDone()
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
        onDigit = viewModel::onDigit,
        onBackspace = viewModel::onBackspace,
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
 */
@Composable
private fun PinGateScaffold(
    title: String,
    subtitle: String,
    state: PinLockViewModel.State,
    onDigit: (Char) -> Unit,
    onBackspace: () -> Unit,
    footer: @Composable () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.surface),
        contentAlignment = Alignment.Center,
    ) {
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
            )
            if (state.errorMessage != null) {
                Text(
                    text = state.errorMessage,
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
